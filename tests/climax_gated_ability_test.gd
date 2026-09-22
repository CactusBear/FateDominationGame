extends Node

#夹具：AND 时点（require_all_time_points）必须真的按"全部命中"判定。
#背景：曾有两条效果把键名写成 time_points_require_all，加载器不认，
#于是"战斗阶段 + 高潮回合"被静默降级成"命中任一即可"。
#这里既校验加载结果（防键名再写错），也校验实际可发动性随高潮/非高潮切换。

var failures:Array=[]
var checks:int=0

func check(ok:bool,label:String):
	checks+=1
	if not ok:
		failures.append(label)
	print("CHECK ",label," ",ok)

func _ready():
	call_deferred("run")

func run():
	# —— 第一段：数据层。所有声明了 AND 的效果都必须被加载器认到 ——
	# 判据来自卡面原文里的"高潮回合时"，这类效果在非高潮回合不该可发动
	var and_effects:Array=[]
	for card in _all_loaded_cards():
		for effect in card._effects:
			if effect._time_points.size() > 1 and effect._time_points.has("self_climax"):
				and_effects.append(effect)
	check(and_effects.size() > 0, "the card set contains multi-time-point climax effects")
	for effect in and_effects:
		check(effect._time_points_require_all,
			"%s declares an AND time point window" % str(effect._name))
	var wrong_key:Array=[]
	for path in _json_files("res://data"):
		var text:String=FileAccess.get_file_as_string(path)
		if text.contains("time_points_require_all"):
			wrong_key.append(path)
	check(wrong_key.is_empty(),
		"no card writes the unsupported time_points_require_all key: %s" % str(wrong_key))

	# —— 第二段：行为层。高潮回合才可发动 ——
	var ui=load("res://assets/scenes/game_scene/tactical_board_ui.tscn").instantiate()
	add_child(ui)
	ui.set_process(false)
	var id:int=0
	ui._local_player_id=id
	var d:Dictionary=GameDataManager.get_player_data(id)
	EffectManager.reset_runtime()
	GameLog.reset()
	var curse_free = MapData.active_situation
	MapData.active_situation = null
	d.servant_skills=[]
	d.hand_cards.clear()
	d.play_limit.set_num(BaseNumber.new(2))
	d.regular_play_min.set_num(BaseNumber.new(2))
	d.magic.set_num(BaseNumber.new(20))
	d.play_limit.set_num(BaseNumber.new(2))
	# 誓约胜利之剑：cost 8／power 12，其 combat 效果就是"战斗阶段：高潮回合时，合计威力+4"
	var blade:BaseSkill=null
	for servant in GameData.loaded_servants:
		for template in (servant._specials.get("SKILLS", []) as Array):
			var clone:BaseSkill=CloneObject.new().exec(template)
			if clone != null and clone._cost.number == 8 and clone._attributes.has(Attributes.NOBLE_PHANTASM):
				if blade == null:
					blade=clone
	check(blade != null, "the priciest noble phantasm is loaded from the servant template")
	if blade == null:
		MapData.active_situation = curse_free
		_finish(ui)
		return
	var combat:BaseEffect=null
	for effect in blade._effects:
		if effect._name == "combat":
			combat=effect
	check(combat != null, "the noble phantasm carries its battle-phase effect")
	check(combat != null and combat._time_points_require_all, "the battle-phase effect is loaded as an AND window")
	d.servant_skills=[blade]
	RegisterObjectEffects.new().exec(blade, id)

	var previous_climax:Dictionary=LoadSituation.climax_situations
	# ① 非高潮回合的战斗阶段：不该可发动
	LoadSituation.climax_situations={}
	OpenBattleWindow(id)
	check(not GameProgress.is_climax_round(), "the fixture is on a non-climax round")
	if combat != null:
		blade._is_activating=true
		check(not EffectManager.can_manual_activate(combat, id),
			"the battle-phase ability stays unavailable outside a climax round")
	# ② 高潮回合的战斗阶段：可发动
	LoadSituation.climax_situations={GameProgress.current_round: true}
	OpenBattleWindow(id)
	check(GameProgress.is_climax_round(), "the fixture is on a climax round")
	if combat != null:
		blade._is_activating=true
		check(EffectManager.can_manual_activate(combat, id),
			"the battle-phase ability can be activated in a climax round")
	LoadSituation.climax_situations=previous_climax
	MapData.active_situation = curse_free
	_finish(ui)


#切换高潮/非高潮要重开窗口：dynamic_time_point 按当时的高潮标记派发 self_climax/self_non_climax
func OpenBattleWindow(player_id:int) -> void:
	GameProgress.is_game_over=false
	GameProgress.current_phase_index=3
	GameProgress.current_player_id=player_id
	GameLog.set_context(1,"battle")
	#与真实时点表同口径：阶段内成立的时点 + 高潮/非高潮标记。
	#climax 必须在 phase_time_points 里，effect_manager 重建手动效果窗口时才会挂上 self_climax
	var climax_tp:String = TimePoints.CLIMAX if GameProgress.is_climax_round() else TimePoints.NON_CLIMAX
	TimePointChecker.set_phase_time_points([TimePoints.DAY, TimePoints.PHASE, TimePoints.BATTLE_PHASE, climax_tp])
	TimePointChecker.dynamic_time_point([TimePoints.BATTLE_PHASE, climax_tp], player_id)


func _json_files(path:String) -> Array:
	var files:Array=[]
	var dir:=DirAccess.open(path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry:=dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if !entry.begins_with("."):
				files.append_array(_json_files(path + "/" + entry))
		elif entry.ends_with(".json"):
			files.append(path + "/" + entry)
		entry=dir.get_next()
	dir.list_dir_end()
	return files


func _all_loaded_cards() -> Array:
	var cards:Array=[]
	_collect_cards(GameData.loaded_masters, cards)
	_collect_cards(GameData.loaded_servants, cards)
	_collect_cards(LoadSituation.situations, cards)
	_collect_cards(LoadSituation.climax_situations.values(), cards)
	return cards


#_specials 的值可能是数组也可能是字典，统一递归收集，避免在夹具里写死结构
#卡牌的种类不止一种（从者/御主/局势/攻击…），所以判据是"带 _effects 的对象"，
#不按具体类型判断；_specials 里可能嵌更深一层卡牌（如从者的 SKILLS）
func _collect_cards(value, out:Array) -> void:
	if value is Array:
		for item in value:
			_collect_cards(item, out)
		return
	if value is Dictionary:
		for key in value.keys():
			_collect_cards(value[key], out)
		return
	if value == null:
		return
	if value.get("_effects") is Array:
		out.append(value)
	var specials = value.get("_specials")
	if specials is Dictionary:
		for key in specials.keys():
			_collect_cards(specials[key], out)


func _finish(ui) -> void:
	ui.queue_free()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
