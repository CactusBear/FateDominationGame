extends Node

# B22 :34：公开 activate() -> 印刷魔力；只查公开玩家余额和结构化资源事实。
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func setup() -> void:
	EffectManager.reset_runtime()
	EffectManager.configure_runtime_guard({"enabled":false,"steps":0,"seconds":0.0})
	GameProgress.is_game_over = false
	GameProgress.current_round = 1
	TimePointChecker.set_phase_time_points([])
	LoadSituation.climax_situations.clear()
	MapData.situations.clear()
	MapData.active_situation = null
	MapData.situation_discard.clear()
	GameData.player_data_library.clear()
	GameData.magic_limit = BaseNumber.new(9)
	var initial:Array = [2, 5, 4, 6]
	for id in initial.size():
		var data:Dictionary = GameDataManager.get_player_data(id)
		data.is_out = id == 3
		data.order = BaseNumber.new(id)
		EditMagic.new().exec(BaseNumber.new(initial[id]), null, id)
	GameDataManager.get_player_data(1).magic_limit = BaseNumber.new(7)
	GameDataManager.get_player_data(2).is_magic_immune = true
	# 清掉造夹具的设值事实；后续只能观察目标 activate 的增量。
	GameLog.reset()
	GameLog.set_context(1, "prepare")

func template(printed_magic:int) -> BaseSituation:
	return LoadSituation.build_situation({
		"card_name":"b22-situation-magic", "shown_name":"B22魔力探针", "card_img":"",
		"magic":{"number":printed_magic,"can_change":true,"is_pure_number":true}, "effects":[]
	}, "res://newtests")

func magic(id:int):
	return GameDataManager.get_player_data(id).magic.number

func balances() -> Array:
	return [magic(0), magic(1), magic(2), magic(3)]

func added(id:int, delta:int, now:int) -> bool:
	var facts:Array = GameLog.query({"type":"magic_add","actor":id}, null)
	if facts.size() != 1: return false
	var fact:Dictionary = facts[0]
	return fact.target == -1 and fact.object == null and fact.data.delta == delta and fact.data.now == now

func run() -> void:
	setup()
	var no_card_before:Array = balances()
	SituationResolver.new().activate()
	check(MapData.active_situation == null and balances() == no_card_before
		and GameLog.query({"type":"magic_add"}, null).is_empty(),
		"B22 空牌堆对照：不走派魔力路径，余额与获得事实均不变")

	setup()
	var card := template(3)
	MapData.situations.assign([card])
	check(GameDataManager.get_active_player_ids() == [0, 1, 2] and balances() == [2, 5, 4, 6],
		"B22 正例前置：三名存活玩家与独立初始余额")
	SituationResolver.new().activate()
	var active = MapData.active_situation
	check(active is BaseSituation and active != card and active.get_shown_name() == "B22魔力探针"
		and active.from == null and MapData.situations.is_empty(),
		"B22 正例：公开激活入口抽出无玩家归属的局势克隆")
	check(magic(0) == 5, "B22 正例：玩家0由2获得印刷3魔力后为5")
	check(magic(1) == GameData.player_magic_limit(1).number and magic(1) == 7,
		"B22 正例：玩家1由5获得印刷3魔力受个人上限截到7")
	check(magic(2) == 4, "B22 免疫对照：存活但声明魔力免疫的玩家2仍为4")
	check(magic(3) == 6, "B22 出局对照：非存活玩家3仍为6")
	check(added(0, 3, 5), "B22 正例事实：玩家0恰有一条归属正确的magic_add，delta=3 now=5")
	check(added(1, 2, 7), "B22 正例事实：玩家1恰有一条归属正确的magic_add，delta=2 now=7")
	check(GameLog.query({"type":"magic_add"}, null).size() == 2,
		"B22 对照事实：全局仅两条获得事实，免疫及出局玩家没有虚假获得")

	setup()
	MapData.situations.assign([template(0)])
	var zero_before:Array = balances()
	SituationResolver.new().activate()
	check(MapData.active_situation is BaseSituation, "B22 零值对照：同一公开入口仍成功激活局势")
	check(balances() == zero_before and GameLog.query({"type":"magic_add"}, null).is_empty(),
		"B22 零值对照：印刷魔力为0时余额不变且没有获得事实")
	EffectManager.reset_runtime()
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
