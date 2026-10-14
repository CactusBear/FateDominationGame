extends "res://newtests/a1_27_battle_origin_test.gd"

#复用原夹具的合法生命周期与三条公开业务判据；额外区分两个 BATTLE_WIN 分支。
var single_winner:bool = false

func fixture(name:String, placed:bool = true) -> void:
	super.fixture(name + ("_single_winner" if single_winner else "_tie_branch"), placed)
	if single_winner:
		SetPlayerData.new().exec("power", BaseNumber.new(99), 0, context)

func run() -> void:
	print("USER_DIR ", OS.get_user_data_dir())
	callback_reset(TimePoints.BATTLE)
	callback_reset(TimePoints.BATTLE_RESOLVE)
	single_winner = true
	callback_reset(TimePoints.BATTLE_WIN)
	single_winner = false
	callback_reset(TimePoints.BATTLE_WIN)
	callback_reset(TimePoints.BATTLE_LOSE)
	print("RESULT ", JSON.stringify({"suite":"battleresolver_timepoints", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
