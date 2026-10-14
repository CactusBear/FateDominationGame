extends "res://newtests/battle_result_commit_gate_test.gd"

# 仅复跑原七个非等待案例；不覆写 fixture/check/原 oracle，不能认证整套。
func run() -> void:
	rejection(true)
	rejection(false)
	legal("empty")
	legal("tie")
	legal("no_winner")
	legal("empty",false)
	legacy_projection()
	print("RESULT ", JSON.stringify({"suite":"addplayer-fixture-batch2_battle_ready_subset", "cases":cases, "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
