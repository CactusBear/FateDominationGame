extends RefCounted

## 测试夹具共用：把已加载的跨局模板（GameData.loaded_* / LoadXxx 结果）复制成本局 runtime 对象。
## 走与正式工厂相同的 CloneContext 契约（configure_template + copy_result）；不 bind 消费口、不补票。
## 失败返回 null，由调用方断言处理。
static func clone_template(template, context:SessionContext):
	if template == null or context == null:
		return null
	var factory := CloneContext.new()
	if not factory.configure_template(context, [template]):
		return null
	var copied:Dictionary = factory.copy_result(template, context)
	return copied.object if copied.ok else null
