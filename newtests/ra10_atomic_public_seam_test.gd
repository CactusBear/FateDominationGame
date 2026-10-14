extends "res://newtests/a1_23_location_origin_test.gd"

# 诊断守卫：复用原始落位 oracle；不改 SetLocation，不回滚，不抑制真实 LEAVE。
var observed:Dictionary = {}
var prepare_marker:bool = false:
	set(value):
		prepare_marker = value
		if not value:
			return
		callback_calls += 1
		observed = {"location_is_target":GameData.player_data_library[0].location == MapData.miyama0,
			"origin_seats":MapData.magic_workshop0._players.duplicate(),
			"target_seats":MapData.miyama0._players.duplicate(),
			"move_facts":GameLog.query({"type":"move"}).size(),
			"leave_facts":count_point(TimePoints.LEAVE_LOCATION),
			"enter_facts":count_point(TimePoints.ENTER_LOCATION),
			"transaction":GameLog.fact_transaction_status(7010)}
		check(GameProgress.reset_progress().ok,"PRE real LEAVE resets progress")

func _ready() -> void:
	var env:Dictionary = {"user":OS.get_user_data_dir(),"global_user":ProjectSettings.globalize_path("user://")}
	for key in ["TMPDIR","TEMP","TMP","APPDATA","LOCALAPPDATA"]:
		env[key] = OS.get_environment(key)
	print("ENV_DETAIL ",JSON.stringify(env))
	for display_transaction:bool in [false,true]:
		var source:SessionContext = start()
		callback_calls = 0
		effect(source,[{"func_name":"set_property","parameters":[self,"prepare_marker",true]}],["self_"+TimePoints.LEAVE_LOCATION])
		if display_transaction:
			GameLog.begin_fact_transaction(7010)
			check(GameLog.fact_transaction_status(7010).status == GameLog.FactTransactionStatus.PENDING,"PRE real public fact transaction pending")
		var before:Dictionary = snapshot()
		check(invoke(SET,[MapData.miyama0,0,false,false,true],source) == false,"atomic source rejection observed")
		check(callback_calls == 1,"PRE atomic real LEAVE reset")
		unchanged(before,"A4 full no half placement including seats and facts")
		print("SEAM_DETAIL ",JSON.stringify({"display_transaction":display_transaction,"inside_callback":observed,
			"after":{"at_origin":GameData.player_data_library[0].location == MapData.magic_workshop0,
			"leave":count_point(TimePoints.LEAVE_LOCATION),"enter":count_point(TimePoints.ENTER_LOCATION)}}))
		GameLog.abort_fact_transaction(7010)
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"suite":"ra10_public_fact_seam"}))
	get_tree().quit(0 if failures.is_empty() else 1)
