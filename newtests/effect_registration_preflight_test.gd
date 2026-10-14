extends Node

const UNKNOWN:int = 990024
var checks:int = 0
var failures:Array = []
var cases:int = 0

func _ready() -> void:
	call_deferred("run")

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("CHECK ", label, " ", ok)

# Qualification is read-only, including a missing member and stale registration identity.
func snapshot(effect:BaseEffect) -> Dictionary:
	var members:Dictionary = {}
	for id in GameData.player_data_library:
		members[id] = GameData.player_data_library[id].self_effects.duplicate()
	var metadata:Dictionary = {}
	if effect != null:
		for key in effect.get_meta_list():
			var value = effect.get_meta(key)
			metadata[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	var manager_metadata:Dictionary = {}
	for key in EffectManager.get_meta_list():
		var value = EffectManager.get_meta(key)
		manager_metadata[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return {"ids":GameData.player_data_library.keys(), "members":members,
		"pool":EffectManager.effect_pool.duplicate(), "objects":GameData.objects.duplicate(),
		"effects":GameData.effects.duplicate(), "decision":EffectManager.decision_queue.duplicate(),
		"activation":EffectManager.activation_pool.duplicate(),
		"matched":EffectManager.matched_time_points.duplicate(),
		"resolved":EffectManager.resolved_effects.duplicate(),
		"metadata":metadata, "manager_metadata":manager_metadata,
		"owner":effect._trigger_player_id if effect != null else -1,
		"guard":EffectManager.runtime_guard_status()}

func query(effect:BaseEffect, id:int, expected:bool, label:String) -> void:
	cases += 1
	var before:Dictionary = snapshot(effect)
	check(EffectManager.can_register_effect(effect,id) == expected, label + " qualification")
	check(EffectManager.can_register_effect(effect,id) == expected, label + " repeat")
	check(snapshot(effect) == before, label + " query has no side effects")
	check(not GameData.player_data_library.has(UNKNOWN), label + " does not create member")

func run() -> void:
	check(EffectManager.has_method("can_register_effect"), "public qualification entry exists")
	if not EffectManager.has_method("can_register_effect"):
		print("RESULT ", JSON.stringify({"suite":"effect_registration_preflight","cases":cases,"checks":checks,"failures":failures}))
		get_tree().quit(1)
		return
	check(GameData.reset_game_session([0,1]).get("ok",false), "initial reset")
	# Capture the actual lifecycle return at fixture creation; never refresh an old effect.
	var context:SessionContext = GameProgress.reset_progress(false).get("context")
	var produced:Array = LoadHelper.load_effects([{"effect_name":"preflight",
		"time_points":[TimePoints.GAME_START],"priority":0,"is_pure_passive":false,
		"is_residue":false,"effect_numbers":[],"funcs":[]}],null,context)
	var effect:BaseEffect = produced[0] if produced.size() == 1 else null
	query(null,0,false,"null")
	query(effect,UNKNOWN,false,"missing member")
	query(effect,-1,true,"unowned default")
	query(effect,0,true,"unbound explicit member")
	check(not EffectManager.effect_pool.has(effect), "query did not register effect")
	check(EffectManager.register_effect(effect,0), "real registration succeeds")
	query(effect,0,true,"bound member")
	query(effect,-1,true,"bound default")
	query(effect,1,false,"different binding")
	EffectManager.unregister_effect(effect)
	query(effect,0,true,"unregistered current identity")
	check(GameData.reset_game_session([0,1]).get("ok",false), "second reset")
	query(effect,0,false,"stale explicit identity")
	query(effect,-1,false,"stale default identity")
	query(effect,1,false,"stale other member")
	var before:Dictionary = snapshot(effect)
	check(not EffectManager.register_effect(effect,0), "real single registration rejects stale identity")
	check(not EffectManager.register_effects([effect],0), "real batch registration rejects stale identity")
	check(snapshot(effect) == before, "rejected registration unchanged")
	print("RESULT ", JSON.stringify({"suite":"effect_registration_preflight","cases":cases,"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
