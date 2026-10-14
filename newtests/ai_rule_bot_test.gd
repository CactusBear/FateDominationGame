extends "res://newtests/a1_06_regular_origin_test.gd"
const Bot = preload("res://scripts/system/ai/rule_bot.gd")
const Planner = preload("res://scripts/system/ai/effect_planner.gd")
const Random = preload("res://scripts/match/rule_random.gd")

func brute(cards:Array,payment:Dictionary,query,position:int = 0,picked:Array = [],flags:Array = []) -> Dictionary:
	var best:Dictionary = {"score":-INF,"group":{}}
	if RegularPlay.can_submit_group(0,picked,flags,false,payment):
		best = {"score":query.preview(0,picked,flags,payment).power_breakdown.total,"group":{"cards":picked,"hidden":flags}}
	for i in range(position,cards.size()):
		# 独立三态枚举，不沿用搜索器的 modes、剪枝或去重。
		for hidden in [false,true]:
			var next:Dictionary = brute(cards,payment,query,i + 1,picked + [cards[i]],flags + [hidden])
			if next.score > best.score: best = next
	return best

func compare(source:SessionContext,label:String) -> Dictionary:
	var bot = Bot.new(source)
	var query = MatchSeatQuery.new(MatchViewBuilder.new(),source)
	var payment:Dictionary = RegularPlay.payment_quote(0,source)
	var expected:Dictionary = brute(RegularPlay.candidates(0),payment,query)
	var before:Dictionary = snapshot()
	var sync:Dictionary = bot.make_search(0).run_sync()
	var async_result:Dictionary = await bot.make_search(0).run_async(get_tree())
	check(label + " brute optimum",sync.score == expected.score)
	check(label + " synchronous asynchronous same exact choice",sync == async_result)
	check(label + " search has no rule side effects",snapshot() == before)
	return sync

func fixture(count:int = 5) -> SessionContext:
	var source:SessionContext = setup()
	Random.start_seed(610613)
	var data:Dictionary = GameData.player_data_library[0]
	data.regular_play_min.number = 2
	data.play_limit.number = 2
	data.command_spell_count.number = 0
	for i in count:
		data.hand_cards.append(new_attack(source,"ai-card-%d" % i,"",[],BaseNumber.new(i % 3),BaseNumber.new(i + 1)))
	return source

func effect_fixture(source:SessionContext,options:Array,max_choices:int = 1,cost:Variant = null) -> BaseEffect:
	TimePointChecker.set_phase_time_points([TimePoints.ACTION_PHASE],source)
	var produced:Array = LoadHelper.load_effects([{"effect_name":"ai-estimate","priority":0,"time_points":[TimePoints.SELF_PREFIX + TimePoints.ACTION_PHASE],"is_pure_passive":false,"is_residue":false,"is_manual":true,"need_activate":false,"effect_numbers":[],"cost":cost,"max_choices":max_choices,"options":options}],null,source)
	check("B factory produced effect",produced.size() == 1)
	if produced.is_empty(): return null
	var effect:BaseEffect = produced[0]
	held.append(effect)
	check("B runtime registration",EffectManager.register_effect(effect,0))
	check("B real manual request availability",EffectManager.request_manual_activation(effect,0) == EffectManager.has_available_options(effect))
	return effect

func option(power:int,max_uses:int = 1) -> Dictionary:
	return {"shown_option_name":str(power),"max_uses":max_uses,"funcs":[{"func_name":"edit_power","parameters":[null,BaseNumber.new(power),0]}]}

func run() -> void:
	var source:SessionContext = fixture()
	await compare(source,"five real cards both orientations")
	var bot = Bot.new(source)
	var data:Dictionary = GameData.player_data_library[0]
	var result:Dictionary = bot.make_search(0).run_sync()
	var expected:float = result.score
	var driver = MatchDriver.new(null,source)
	bot._submit_search(driver,0,result)
	check("real group submitted and completed",RegularPlay.completed(0) and data.played_cards.size() == 2)
	check("real total equals oracle preview",GetPlayerTotalPower.breakdown(0).total == expected)
	source = fixture()
	data = GameData.player_data_library[0]
	data.magic.number = 0
	var zero:Dictionary = await compare(source,"zero magic")
	check("zero magic never spends unaffordable printed cost",zero.group.hidden.size() == 2)
	data.is_magic_immune = true
	await compare(source,"zero magic immune")
	source = fixture(1)
	check("minimum cannot be met returns empty",Bot.new(source).make_search(0).run_sync().group.is_empty())
	source = fixture(0)
	check("empty real hand returns empty",Bot.new(source).make_search(0).run_sync().group.is_empty())
	source = fixture(16)
	var big = Bot.new(source).make_search(0)
	big.seed_greedy()
	var greedy:float = big.best_score
	while not big.done: big.advance()
	check("sixteen real candidates bounded no worse than greedy",big.nodes <= big.NODE_BUDGET and big.best_score >= greedy)
	source = fixture()
	var stale = Bot.new(source).make_search(0)
	stale.seed_greedy()
	GameProgress.current_player_id = 1
	stale.advance()
	check("turn changes discard real best",stale.result().cancelled and stale.result().group.is_empty())
	source = fixture()
	stale = Bot.new(source).make_search(0)
	stale.seed_greedy()
	GameData.player_data_library[0].is_out = true
	stale.advance()
	check("eliminated player discards best",stale.result().cancelled)
	source = fixture()
	stale = Bot.new(source).make_search(0)
	stale.seed_greedy()
	GameProgress.reset_progress()
	stale.advance()
	check("new session discards best",stale.result().cancelled)
	source = fixture()
	var effect:BaseEffect = effect_fixture(source,[option(-3),option(7),option(2)])
	var before:Dictionary = snapshot()
	var plan:Dictionary = Planner.plan(effect,0)
	check("B chooses maximum declared direct power",plan.activate and plan.selection == {1:1} and plan.estimate == 7 and plan.tier == "B")
	check("B planning never settles live effect",snapshot() == before)
	var async_plan:Dictionary = await Planner.plan_async(effect,0,get_tree())
	check("B synchronous asynchronous estimate and choice match",async_plan == plan)
	check("B async planning never settles effect",snapshot() == before)
	Bot.new(source).resolve_active_effect(effect,0)
	check("B chosen option actually executed",GetPlayerTotalPower.breakdown(0).total == 7)
	source = fixture()
	var magic_option:Dictionary = {"shown_option_name":"magic","max_uses":1,"funcs":[{"func_name":"edit_magic","parameters":[null,BaseNumber.new(4),-1.0]}]}
	var bonus_option:Dictionary = {"shown_option_name":"bonus","max_uses":1,"funcs":[{"func_name":"edit_data_number","parameters":["total_power_bonus",null,BaseNumber.new(2),0]}]}
	effect = effect_fixture(source,[magic_option,bonus_option])
	plan = Planner.plan(effect,0)
	check("B declared magic heuristic preserves command spell fallback",plan.selection == {0:1} and plan.estimate == 4)
	effect._options = LoadHelper.load_effect_options([bonus_option],effect,source)
	check("B declared total power bonus shape is recognized",Planner.plan(effect,0).estimate == 2)
	source = fixture()
	effect = effect_fixture(source,[option(-5),option(-1)])
	check("B includes do not activate",not Planner.plan(effect,0).activate)
	source = fixture()
	effect = effect_fixture(source,[option(2,2),option(5,1),option(-4,1)],-1)
	plan = Planner.plan(effect,0)
	check("B multi unlimited choices enumerates repeated uses",plan.selection == {0:2,1:1} and plan.estimate == 9)
	source = fixture()
	effect = effect_fixture(source,[option(2,0)])
	check("B unavailable options decline",not Planner.plan(effect,0).activate)
	source = fixture()
	effect = effect_fixture(source,[option(2)])
	effect._cost = BaseNumber.new(999)
	check("B cannot afford cost declines",not Planner.plan(effect,0).activate)
	source = fixture()
	var quantity_option:Dictionary = {"shown_option_name":"quantity","max_uses":1,"quantity_range":[1,4],"funcs":[{"func_name":"edit_power","parameters":[null,{"option_quantity_index":0},0]}]}
	effect = effect_fixture(source,[quantity_option])
	plan = Planner.plan(effect,0)
	check("B enumerates declared option quantities",plan.activate and plan.quantities == {0:4} and plan.estimate == 4)
	var picks:Array = Planner.choose([1,2,3,4],2,-1,[1],func(value): return value)
	check("B required targets and unlimited selection",picks.size() == 4 and picks.has(1) and picks.has(2) and picks.has(3) and picks.has(4))
	var async_picks:Dictionary = await Planner.choose_async([1,2,3,4],2,-1,[1],func(value): return value,get_tree())
	check("B target synchronous asynchronous same picks",async_picks.group.cards == picks)
	source = fixture()
	data = GameData.player_data_library[0]
	var battlefield = BaseMapArea.new("ai-battlefield")
	var location = BaseLocation.new()
	location.from = battlefield
	data.location = location
	await compare(source,"battlefield faceup requirement")
	data.magic.number = 0
	for card in data.hand_cards: card._cost.number = 8
	check("battlefield all hidden is not legal",Bot.new(source).make_search(0).run_sync().group.is_empty())
	source = fixture(16)
	data = GameData.player_data_library[0]
	var changed_bot = Bot.new(source)
	var changed_driver = MatchDriver.new(null,source)
	get_tree().process_frame.connect(func(): data.magic.number += 1,CONNECT_ONE_SHOT)
	await changed_bot.step_async(changed_driver,0,get_tree())
	check("async live magic change cancels without submitting",changed_bot.last_search.get("cancelled",false) and data.played_cards.is_empty())
	source = fixture(16)
	data = GameData.player_data_library[0]
	changed_bot = Bot.new(source)
	changed_driver = MatchDriver.new(null,source)
	get_tree().process_frame.connect(func(): GameProgress.current_player_id = 1,CONNECT_ONE_SHOT)
	await changed_bot.step_async(changed_driver,0,get_tree())
	check("async actual turn handoff cancels without submitting",changed_bot.last_search.get("cancelled",false) and data.played_cards.is_empty())
	source = fixture(16)
	data = GameData.player_data_library[0]
	var sync_group:Dictionary = Bot.new(source).make_search(0).run_sync().group
	var sync_driver = MatchDriver.new(null,source)
	sync_driver.run_bot_turn(0)
	check("synchronous driver keeps completed synchronous ABI",data.played_cards == sync_group.cards and RegularPlay.completed(0) and not sync_driver._acting)
	source = fixture(16)
	data = GameData.player_data_library[0]
	var expected_group:Dictionary = Bot.new(source).make_search(0).run_sync().group
	var async_driver = MatchDriver.new(null,source)
	var saw_acting:Array = []
	get_tree().process_frame.connect(func():
		saw_acting.append(async_driver._acting)
		async_driver.run_bot_turn(0)
	,CONNECT_ONE_SHOT)
	await async_driver.run_bot_turn_async(0,get_tree())
	check("async driver holds acting guard across actual frames",saw_acting == [true] and not async_driver._acting)
	check("actual async driver submits same optimum",data.played_cards == expected_group.cards and RegularPlay.completed(0))
	await formal_start()
	print("RESULT ",JSON.stringify({"suite":"ai_rule_bot","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func formal_start() -> void:
	GameStart.reset()
	Random.start_seed(610613)
	check("formal data starts",GameStart.game_start([0,1]))
	var source:SessionContext = GameStart.startup_context()
	var driver = MatchDriver.new(null,source)
	var bot = Bot.new(source)
	var areas:Array = driver.ai_deploy_areas()
	var random_before:Dictionary = Random.snapshot()
	var choice:Array = areas.duplicate()
	Random.shuffle(choice)
	var expected = driver.ai_pick_deploy_location(choice[0]) if not choice.is_empty() else null
	Random.restore(random_before)
	bot._deploy(driver,0)
	check("seeded deployment legal and repeatable",expected != null and GameData.player_data_library[0].location == expected)
	GameProgress.current_player_id = 0
	GameProgress.current_phase_index = 2
	GameLog.set_context(GameProgress.current_round,"action")
	var data:Dictionary = GameData.player_data_library[0]
	data.magic.number = 0
	var spells_before:int = int(data.command_spell_count.number)
	TimePointChecker.set_phase_time_points([TimePoints.ACTION_PHASE],source)
	await bot.use_command_spell_if_needed_async(0,data,get_tree())
	check("formal async command spell uses declared magic estimate",data.magic.number == 4 and data.command_spell_count.number == spells_before - 1)
	if RegularPlay.candidates(0).size() <= 8:
		await compare(source,"formal opening")
	else:
		var search = bot.make_search(0)
		var result:Dictionary = search.run_sync()
		check("formal large opening search bounded",result.nodes <= search.NODE_BUDGET and not result.cancelled)
