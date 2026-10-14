class_name RegisterObjectEffects
extends RefCounted

#把对象上的_effects登记给一名玩家；登记不创建成员，也不为旧对象补来源。
func exec(object, player_id:int = -1, context:Variant = null):
	context = captured_context(context)
	if not source_is_current(context, object):
		return
	var resolved:Dictionary = resolved_player_id(player_id, context)
	if not resolved.ok:
		return
	var id:int = resolved.id
	if not can_register_object(object, id, context):
		return
	EffectManager.register_effects(object._effects, id)


#缺省仅继承真实已验函数帧。显式畸形/旧句柄原样交统一服务拒绝。
static func captured_context(context:Variant):
	if context != null:
		return context
	var frame:Dictionary = EffectManager.execution_context()
	return frame.get("context") if frame.get("ok", false) else null


#六个直接入口共用只读来源门，不持有第二套帧/代际/成员缓存。
#事件主体不是执行资格；运行期对象另核自己的原来源，禁止新context洗旧对象。
static func source_is_current(context:Variant, subject:Variant = null) -> bool:
	if not SessionGeneration.validate_context(context).ok:
		return false
	if subject is BaseEffect:
		var runtime:SessionContext = subject.runtime_context()
		return subject.runtime_source_status().ok and is_same(runtime.token(), context.token())
	if subject is BaseObject:
		var origin:Dictionary = SessionGeneration.origin_of(subject)
		return origin.ok and is_same(origin.context.token(), context.token())
	return true


#S-02保原“效果归属优先、缺归属才本地”；旧activating_eff不是默认主体资格。
static func resolved_player_id(player_id:int, context:Variant) -> Dictionary:
	if not source_is_current(context):
		return {"ok":false}
	if player_id == -1 and EffectManager.activating_eff != null and not source_is_current(context, EffectManager.activating_eff):
		return {"ok":false}
	return {"ok":true, "id":EffectManager.resolve_player_id(player_id)}


#整批先验原对象与各effect；查询不bind、不登记、不调用建库getter。
static func can_register_object(object:Variant, player_id:int, context:Variant) -> bool:
	if not source_is_current(context, object):
		return false
	if not (object is Dictionary or (typeof(object) == TYPE_OBJECT and is_instance_valid(object))) or not ("_effects" in object):
		return false
	if GameDataManager.find_player_data(player_id).is_empty():
		return false
	if not object._effects is Array:
		return false
	for item in object._effects:
		if item is BaseEffect and (not source_is_current(context, item) or not EffectManager.can_register_effect(item, player_id)):
			return false
	return true
