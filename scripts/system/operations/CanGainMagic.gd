class_name CanGainMagic
extends RefCounted

# source 是数据声明的收益种类，不是 SessionContext；不硬编码工房/卡牌来源。
# 旧两参 ABI 缺省只继承已验函数帧，显式原来源必须先验再 resolve/读取成员。
func exec(source:String = "", player_id:int = -1, context:Variant = null):
	context = captured_context(context)
	if not source_is_current(context):
		return null
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok or not GameData.player_data_library.has(resolved.id):
		return null
	var id:int = resolved.id
	var checker = PlayerBuffsHaveEffect.new()
	if checker.exec("cannot_gain_magic", id):
		return false
	if source != "" and checker.exec("cannot_gain_magic_from_" + source, id):
		return false
	return true


# 普通资源编辑/收益查询共用公共只读来源门，不持有第二套代际或帧缓存。
static func captured_context(context:Variant) -> Variant:
	return RegisterObjectEffects.captured_context(context)


static func source_is_current(context:Variant) -> bool:
	if not SessionGeneration.validate_context(context).get("ok", false):
		return false
	# 活动帧存在时显式来源也必须是该原帧，不能借另一个合法句柄洗掉失效帧。
	if not EffectManager.execution_runtime_snapshot().get("functions", []).is_empty():
		var frame:Dictionary = EffectManager.execution_context()
		return frame.get("ok", false) and is_same(frame.get("context"), context)
	return true
