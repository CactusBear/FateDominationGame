extends "res://newtests/waiting-fifo-origin_contract.gd"
# 仅在 owned queue 容量/拒绝注入环境中运行；裸跑应红，不作普通回归。
func run() -> void:
	Observer.reset()
	var c:Dictionary = open_case(true)
	stage(TimePoints.DAY_END)
	var before:Array = MatchJournal.audit_records.duplicate(true)
	var transaction = EffectManager.capture_transaction_state(fixture_context).transaction_bindings.get(c.root)
	check(not TimePointChecker.global_time_point([TimePoints.DAY_START], null, fixture_context), "queue refusal propagates false through TPC")
	check(GameDataManager.find_player_data(0).dynamic_time_points == [TimePoints.DAY_END, TimePoints.DAY_START], "queue refusal does not consume transients already written by TPC")
	check(EffectManager.waiting_effect == c.root and EffectManager.capture_transaction_state(fixture_context).batch_transactions.is_empty(), "queue refusal keeps real waiting and creates no batch")
	check(is_same(transaction, EffectManager.capture_transaction_state(fixture_context).transaction_bindings.get(c.root)) and MatchJournal.audit_records == before, "queue refusal consumes no original transaction/control audit")
	end_audit()
	Observer.finish(get_tree())
