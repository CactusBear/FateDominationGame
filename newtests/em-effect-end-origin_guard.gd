extends "res://newtests/a1_06_regular_origin_test.gd"

# Independent root completion: no RegularPlay/PayMagic execution, no fake function frame.
func new_root(source:SessionContext) -> BaseEffect:
	var funcs:Array = []
	for i in range(5):
		funcs.append({"func_name":"do_nothing", "parameters":[]})
	var created:Array = LoadHelper.load_effects([{"effect_name":"em-effect-end-origin", "priority":0,
		"is_pure_passive":true, "is_residue":false, "effect_numbers":[], "time_points":[], "funcs":funcs}], null, source)
	check("trusted root creation from original lifecycle", created.size() == 1)
	if created.is_empty(): return null
	var root:BaseEffect = created[0]
	held.append(root)
	check("real root registration", EffectManager.register_effect(root, 0))
	return root

func independent_completion(paused:bool) -> void:
	var source:SessionContext = setup()
	if source == null: return
	var root:BaseEffect = new_root(source)
	if root == null: return
	EffectManager.configure_runtime_guard({"enabled":paused, "steps":2, "seconds":0.0})
	check("no ambient function frame before root", not EffectManager.execution_context().ok)
	EffectManager.activate_effect(root)
	if paused:
		check("real root pauses before completion", EffectManager.runtime_guard_status().paused)
		check("paused root publishes no completion fact", GameLog.query({"type":"effect"}, null, -1).is_empty())
		check("natural public resume completes root", complete_guard())
	check("no ambient function frame after completion", not EffectManager.execution_context().ok)
	var facts:Array = GameLog.query({}, null, -1)
	check("independent root records exactly start effect and end", facts.size() == 3)
	check("EFFECT_START retains original root actor and time point", facts.size() == 3 and facts[0].type == "time_point" and facts[0].object == root and facts[0].actor == 0 and facts[0].data.time_points == [TimePoints.EFFECT_START])
	check("effect fact retains original root and actor", facts.size() == 3 and facts[1].type == "effect" and facts[1].object == root and facts[1].actor == 0)
	check("EFFECT_END retains original root actor and time point", facts.size() == 3 and facts[2].type == "time_point" and facts[2].object == root and facts[2].actor == 0 and facts[2].data.time_points == [TimePoints.EFFECT_END])
	check("completion preserves original source validity", Sessions.validate_context(source).ok and root.runtime_source_status().ok)

func stale_completion() -> void:
	var source:SessionContext = setup()
	if source == null: return
	var root:BaseEffect = new_root(source)
	if root == null: return
	EffectManager.configure_runtime_guard({"enabled":true, "steps":2, "seconds":0.0})
	EffectManager.activate_effect(root)
	check("stale case uses a genuine paused root", EffectManager.runtime_guard_status().paused)
	var next:Dictionary = GameProgress.reset_progress()
	check("reset revokes original source without clearing root", next.ok and not Sessions.validate_context(source).ok)
	var before:Array = GameLog.query({}, null, -1).duplicate(true)
	check("old root public resume refuses", not EffectManager.resume_runtime_guard())
	check("old root cannot publish completion or EFFECT_END", GameLog.query({}, null, -1) == before)

func run() -> void:
	print("PATH_PROOF ", JSON.stringify({"pid":OS.get_process_id(), "user":OS.get_user_data_dir()}))
	independent_completion(false)
	independent_completion(true)
	stale_completion()
	print("RESULT ", JSON.stringify({"suite":"em-effect-end-origin", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
