extends Node

# 此守卫只验存在性查询与公开卡状态谓词，不把它们当来源授权或完整时点执行。
var checks:int = 0
var failures:Array = []

func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func make_effect(owner, need_activate:bool, passive:bool = false, effect_name:String = "conceal_scope_probe") -> BaseEffect:
	# 从正式模板加载器取得声明，不为查询夹具绑定运行期来源。
	var loaded:Array = LoadHelper.load_effects([{
		"effect_name":effect_name, "priority":0, "time_points":[],
		"is_pure_passive":passive, "is_residue":false, "effect_numbers":[],
		"need_activate":need_activate, "funcs":[]
	}], owner)
	check(loaded.size() == 1, "PRE declaration factory")
	if loaded.size() != 1:
		return null
	return loaded[0]

func scans() -> void:
	var area:BaseMapArea = MapData.magic_workshop
	var events:Array = area._events
	var buffs:Array = area._buffs
	var situation = MapData.active_situation
	area._events = []
	area._buffs = []
	MapData.active_situation = null
	var event:BaseEvent = BaseEvent.new("scope-event", "", BaseNumber.new(0), [], false)
	var effect:BaseEffect = make_effect(event, true)
	event._effects = [effect]
	area._events.append(event)
	for concealed in [false, true]:
		event._is_concealed = concealed
		check(MapAreaHasEffect.new().exec(area, effect._name), "map event exists concealed=" + str(concealed))
		check(BoardHasEffect.new().exec(effect._name), "board event exists concealed=" + str(concealed))
		check(not MapAreaHasEffect.new().exec(area, "absent_scope_probe"), "map absent name")
		check(event._is_concealed == concealed, "query does not reveal event")
	check(not MapAreaHasEffect.new().exec(null, effect._name), "null area")
	check(not MapAreaHasEffect.new().exec(area, ""), "empty name")
	area._events = []
	var buff:BaseBuff = BaseBuff.new("scope-buff", "")
	var buff_effect:BaseEffect = make_effect(buff, false)
	buff._effects = [buff_effect]
	area._buffs = [buff]
	var player:Dictionary = GameDataManager.find_player_data(0)
	var player_buffs:Array = player.buffs
	player.buffs = [buff]
	for active in [false, true]:
		buff._is_active = active
		check(MapAreaHasEffect.new().exec(area, buff_effect._name) == active, "map buff active=" + str(active))
		check(BoardHasEffect.new().exec(buff_effect._name) == active, "board buff active=" + str(active))
		check(PlayerBuffsHaveEffect.new().exec(buff_effect._name, 0) == active, "player buff active=" + str(active))
		check(EffectManager.card_state_allows(buff_effect) == active, "buff state active=" + str(active))
	var members:int = GameData.player_data_library.size()
	check(not PlayerBuffsHaveEffect.new().exec(buff_effect._name, 989713), "unknown player absent")
	check(GameData.player_data_library.size() == members, "unknown query does not create member")
	player.buffs = player_buffs
	area._events = events
	area._buffs = buffs
	MapData.active_situation = situation

func event_states() -> void:
	var event:BaseEvent = BaseEvent.new("state-event", "", BaseNumber.new(0), [], false)
	check(not event.get_property_list().any(func(p): return p.name == "_is_activating"), "event has no activation field")
	for passive in [false, true]:
		for need in [false, true]:
			var effect:BaseEffect = make_effect(event, need, passive)
			for concealed in [false, true]:
				event._is_concealed = concealed
				check(EffectManager.card_state_allows(effect) == not concealed,
					"event face gate passive=" + str(passive) + " need=" + str(need) + " concealed=" + str(concealed))
				effect._disabled = true
				check(not EffectManager.card_state_allows(effect), "disabled event effect remains blocked")
				effect._disabled = false
				event._text_disabled = true
				check(not EffectManager.card_state_allows(effect), "textless event remains blocked")
				event._text_disabled = false

func activation_independent_of_face() -> void:
	var card:BaseHandCard = BaseHandCard.new()
	for passive in [false, true]:
		for need in [false, true]:
			var effect:BaseEffect = make_effect(card, need, passive)
			for concealed in [false, true]:
				for active in [false, true]:
					card._is_concealed = concealed
					card._is_activating = active
					check(EffectManager.card_state_allows(effect) == (not need or active),
						"hand activate independent passive=" + str(passive) + " need=" + str(need) + " concealed=" + str(concealed) + " active=" + str(active))
	var skill:BaseSkill = BaseSkill.new("unawakened", "", [], BaseNumber.new(0), BaseNumber.new(0), false, [], false)
	skill._is_awakened = false
	skill._is_activating = true
	check(not EffectManager.card_state_allows(make_effect(skill, false, true)), "unawakened skill remains blocked")
	card._is_concealed = true
	check(not CardCountsPower.new().counts_when_played(card, true, 0), "concealed power default off")
	var power_exception:BaseEffect = CountsPowerWhileConcealedEffect.new()
	power_exception.from = card
	card._effects = [power_exception]
	check(CardCountsPower.new().counts_when_played(card, true, 0), "existing concealed power declaration works")
	check(CardHasEffect.new().exec(CountsPowerWhileConcealedEffect.EFFECT_NAME, card), "concealed power declaration exists")
	card._effects.append(NeverCountsPowerEffect.new())
	check(not CardCountsPower.new().counts_when_played(card, true, 0), "never counts still takes precedence")

func run() -> void:
	var session:Dictionary = GameData.reset_game_session([0, 1])
	check(session.get("ok", false), "PRE session")
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("events-only"):
		scans()
	if not args.has("scans-only"):
		event_states()
	activation_independent_of_face()
	print("RESULT ", JSON.stringify({"suite":"conceal_effect_scope", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _ready() -> void:
	call_deferred("run")
