extends Node


#只负责从者归属和从者效果绑定，不负责游戏开始、御主或技能管理。
func bind_servant_effects(player_id:int, source_context:SessionContext = null) -> bool:
	if not SessionGeneration.validate_context(source_context).ok:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var servant = player_data.get("servant")
	if servant == null:
		return EffectManager.register_effects([], player_id)
	if not servant is BaseServant:
		return false
	var prepared:Dictionary = MasterManager.prepare_role_runtime(servant, source_context)
	if not prepared.ok:
		return false
	var runtime:BaseServant = prepared.object
	var registered:bool = EffectManager.register_effects(runtime._effects, player_id)
	if registered:
		player_data["servant"] = runtime
	return registered
