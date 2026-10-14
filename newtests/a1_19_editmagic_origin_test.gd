extends Node

var checks:int = 0
var failures:Array = []
var mutation_mode:String = ""
var mutation_trigger:bool = false:
	set(value):
		mutation_trigger = value
		if not value:
			return
		if mutation_mode == "reset":
			var reset:Dictionary = GameData.reset_game_session([0, 1])
			check(reset.get("ok", false), "PRE reset during BEFORE succeeds")
		elif mutation_mode == "replace_player":
			GameData.player_data_library[0] = GameData.new_player_data()
		elif mutation_mode == "replace_magic":
			GameData.player_data_library[0]["magic"] = BaseNumber.new(9)


func check(value:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", value)
	if not value:
		failures.append(label)


func new_session() -> SessionContext:
	var result:Dictionary = GameData.reset_game_session([0, 1])
	check(result.get("ok", false), "PRE new session")
	GameLog.reset()
	return result.get("context")


func make_effect(name:String, funcs:Array, context:SessionContext, points:Array = []) -> BaseEffect:
	var loaded:Array = LoadHelper.load_effects([{"effect_name":name,"time_points":points,"priority":0,"is_pure_passive":true,"is_residue":false,"effect_numbers":[],"funcs":funcs}], null, context)
	check(loaded.size() == 1, "PRE factory creates " + name)
	if loaded.is_empty():
		return null
	var effect:BaseEffect = loaded[0]
	check(EffectManager.register_effect(effect, 0), "PRE registers " + name)
	return effect


func edit_effect(context:SessionContext, name:String, amount:int) -> BaseEffect:
	return make_effect(name, [{"func_name":"edit_magic","parameters":[null,BaseNumber.new(amount),0]}], context)


func direct_without_frame() -> void:
	var context:SessionContext = new_session()
	var magic:BaseNumber = GameData.player_data_library[0]["magic"]
	var result = EditMagic.new().exec(null, BaseNumber.new(1), 0)
	check(result == false, "no-frame EditMagic returns explicit rejection")
	check(is_same(GameData.player_data_library[0]["magic"], magic) and magic.number == 4, "no-frame EditMagic leaves magic unchanged")
	check(SessionGeneration.validate_context(context).get("ok", false), "no-frame rejection does not invalidate session")


func legal_edit() -> void:
	var context:SessionContext = new_session()
	var root:BaseEffect = edit_effect(context, "a1-19-legal-edit", 3)
	EffectManager.activate_effect(root)
	check(GameData.player_data_library[0].magic.number == 7, "same-domain legal edit changes original player")


func legal_cancel() -> void:
	var context:SessionContext = new_session()
	var listener:BaseEffect = make_effect("a1-19-cancel", [{"func_name":"cancel_pending_action","parameters":[]}], context, [TimePoints.SELF_BEFORE_MAGIC_ADD])
	var root:BaseEffect = edit_effect(context, "a1-19-cancel-root", 3)
	EffectManager.activate_effect(root)
	check(listener != null and root != null, "PRE cancellation chain is registered")
	check(GameData.player_data_library[0].magic.number == 4, "same-domain cancellation does not change magic")
	check(GameLog.query({"type":"magic_add"}).is_empty(), "same-domain cancellation has no magic_add fact")


func legal_modify() -> void:
	var context:SessionContext = new_session()
	var listener:BaseEffect = make_effect("a1-19-edit-before", [{"func_name":"edit_pending_action","parameters":["amount",BaseNumber.new(5),null]}], context, [TimePoints.SELF_BEFORE_MAGIC_ADD])
	var root:BaseEffect = edit_effect(context, "a1-19-edit-root", 2)
	EffectManager.activate_effect(root)
	check(listener != null and root != null, "PRE modification chain is registered")
	check(GameData.player_data_library[0].magic.number == 9, "same-domain BEFORE modification commits declared amount")


func stale_after_reset() -> void:
	var context:SessionContext = new_session()
	mutation_mode = "reset"
	var listener:BaseEffect = make_effect("a1-19-reset-before", [{"func_name":"set_property","parameters":[self,"mutation_trigger",true]}], context, [TimePoints.SELF_BEFORE_MAGIC_ADD])
	var root:BaseEffect = edit_effect(context, "a1-19-reset-root", 3)
	var old_magic:BaseNumber = GameData.player_data_library[0].magic
	EffectManager.activate_effect(root)
	check(listener != null and root != null, "PRE reset chain is registered")
	check(not SessionGeneration.validate_context(context).get("ok", false), "reset invalidates original context")
	check(GameData.player_data_library[0].magic.number == 4, "reset old chain does not change new player")
	check(GameLog.query({"type":"magic_add"}).is_empty(), "reset old chain writes no magic_add fact")
	check(not is_same(GameData.player_data_library[0].magic, old_magic), "reset installs a distinct magic object")
	mutation_mode = ""


func stale_after_player_replacement() -> void:
	var context:SessionContext = new_session()
	var original:Dictionary = GameData.player_data_library[0]
	mutation_mode = "replace_player"
	var listener:BaseEffect = make_effect("a1-19-player-replace", [{"func_name":"set_property","parameters":[self,"mutation_trigger",true]}], context, [TimePoints.SELF_BEFORE_MAGIC_ADD])
	var root:BaseEffect = edit_effect(context, "a1-19-player-replace-root", 3)
	EffectManager.activate_effect(root)
	var replacement:Dictionary = GameData.player_data_library[0]
	check(listener != null and root != null, "PRE same-ID player replacement chain is registered")
	check(replacement.magic.number == 4, "same-ID replacement keeps replacement magic unchanged")
	check(not is_same(replacement, original), "same-ID replacement is not accepted as original player")
	mutation_mode = ""


func stale_after_magic_replacement() -> void:
	var context:SessionContext = new_session()
	mutation_mode = "replace_magic"
	var listener:BaseEffect = make_effect("a1-19-magic-replace", [{"func_name":"set_property","parameters":[self,"mutation_trigger",true]}], context, [TimePoints.SELF_BEFORE_MAGIC_ADD])
	var root:BaseEffect = edit_effect(context, "a1-19-magic-replace-root", 3)
	EffectManager.activate_effect(root)
	var current:BaseNumber = GameData.player_data_library[0].magic
	check(listener != null and root != null, "PRE same-ID magic replacement chain is registered")
	check(current.number == 9, "same-ID magic replacement is not overwritten by stale edit")
	mutation_mode = ""


func _ready() -> void:
	print("ENV user_dir=", OS.get_user_data_dir(), " pid=", OS.get_process_id())
	var mode:String = str(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else "all"
	if mode in ["all", "local"]:
		direct_without_frame()
		legal_edit()
		legal_cancel()
		legal_modify()
	if mode in ["all", "stale"]:
		stale_after_reset()
		stale_after_player_replacement()
		stale_after_magic_replacement()
	GameData.release_game_objects()
	print("RESULT ", JSON.stringify({"suite":"a1_19_editmagic_origin","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
