extends "res://newtests/battle_result_commit_gate_test.gd"

# 原 oracle 不变；补充原套件未观察到的创建实参，防默认值碰巧相等而真空绿。
func fixture(name:String, confirm:bool, placed:bool) -> void:
	super.fixture(name,confirm,placed)
	check(TimePointChecker.phase_time_points == [TimePoints.DAY,TimePoints.PHASE,TimePoints.BATTLE_PHASE], "creation fixed phase window retained")
	for id in [0,1]:
		var member:Dictionary = GameDataManager.find_player_data(id)
		check(not member.is_out, "creation explicit active member " + str(id))
		check(member.order.number == id, "creation explicit original order " + str(id))
		if placed:
			check(member.power.number == 10, "creation explicit original power " + str(id))

func check(ok:bool, label:String) -> void:
	super.check(ok,label)
	if label != "real battle-end optional effect registered": return
	var observed:bool = false
	for effect:BaseEffect in EffectManager.effect_pool:
		if not effect.has_name("battle_contract_choice"): continue
		var origin:Dictionary = SessionGeneration.origin_of(effect.get_from())
		observed = origin.ok and is_same(origin.context.token(),context.token()) and is_same(effect.runtime_context().token(),context.token())
	super.check(observed,"creation wait host and effect retain original source")

func run() -> void:
	rejection(true)
	rejection(false)
	wait_then_seal(true)
	wait_then_seal(false)
	legal("empty")
	legal("tie")
	legal("no_winner")
	legal("empty",false)
	legacy_projection()
	print("RESULT ",JSON.stringify({"suite":"addplayer-fixture-batch2_creation_contract", "cases":cases, "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
