extends RefCounted

# 仅供夹具创建阶段：调用者显式给出新模板 identity 与原生命周期来源。
# runtime 对象仍由 C0 沿原来源复制；此处不在消费入口 bind 或重新 derive。
static func runtime(template:Variant, context:SessionContext) -> Variant:
	var factory := CloneContext.new()
	if not factory.configure_template(context,[template]):
		print("S1_FACTORY_REJECT_CONFIG ",factory.failure_reason())
		return null
	var result:Dictionary = factory.copy_result(template,context)
	if not result.ok: print("S1_FACTORY_REJECT_COPY ",result.reason)
	return result.object if result.ok else null
