class_name CloneObject
extends RefCounted

#JSON 原语只负责发起复制；字段与重置策略由对象自己的 clone_data 维护。
func exec(object, source_context:SessionContext = null):
	# 卡库里的御主/从者模板尚无本局来源，只能经角色可信工厂建本局副本（替换御主/从者用）
	if (object is BaseMaster and GameData.loaded_masters.has(object)) or (object is BaseServant and GameData.loaded_servants.has(object)):
		var context = RegisterObjectEffects.captured_context(source_context)
		var prepared:Dictionary = MasterManager.prepare_role_runtime(object, context)
		return prepared.object if prepared.ok else null
	var result:Dictionary = CloneContext.new().copy_result(object, source_context)
	return result.object if result.ok else null
