class_name SetPlayerData
extends RefCounted

func exec(key_name:String, value, player_id:int = -1, context:Variant = null):
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context, value):
		return

	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return
	player_id = resolved.id
	# 只修改现存成员；创建由 setup/reset/AddPlayer 等显式入口负责。
	if not GameData.player_data_library.has(player_id):
		return
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	# 先完成字段校验，拒绝时不赋值也不写 assigned 事实；返回仍为 null。
	if not _valid_value(key_name, value):
		return
	player_data[key_name] = value
	# 所属御主的初始/替换历史只作为事实写日志；不为单卡新增快照字段。
	if key_name in ["master", "servant"]:
		var effect_name := ""
		if EffectManager.activating_eff != null:
			effect_name = EffectManager.activating_eff._name
		GameLog.record(key_name + "_assigned", player_id, -1, "", value, [key_name + "_assigned"], {"effect_name": effect_name})


# 正式六类字段的值契约；其它扩展 key/value 仍按原样保存，不作硬白名单。
func _valid_value(key_name:String, value) -> bool:
	match key_name:
		"victory_override", "can_draw_card", "is_magic_immune":
			return typeof(value) == TYPE_BOOL
		"master":
			return value == null or (is_instance_valid(value) and value is BaseMaster)
		"servant":
			return value == null or (is_instance_valid(value) and value is BaseServant)
		"known_info":
			# 保留共享字典及其中 RefCounted 从者的身份；替换后的失效由读取方判定。
			return value is Dictionary
	return true
