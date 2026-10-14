class_name CloneContext
extends RefCounted

# 值 ABI 保留；拒绝粘滞，编排方消费 copy_result，不靠 null 猜成功。
var _failure:StringName = &""
var _depth:int = 0
var _action_source:SessionContext = null
var _template_source:SessionContext = null
var _trusted:Array = []

## A4 发布前反向重绑是图协议，不是模板/runtime clone。零登记、零深复制。
## 调用方必须先完成同一计划的 C/G/L seal 复验；此 helper 不授执行或 commit 资格。
static func reverse_rebind(graph:Variant, value:Variant) -> Dictionary:
	if not graph is RefCounted or graph.get_script() != preload("res://scripts/match/graph_session.gd"):
		return {"status":"UNSUPPORTED","reason":"unregistered_graph_session","value":null}
	return graph.reverse(value)

func has_failed() -> bool:
	return _failure != &""

func failure_reason() -> StringName:
	return _failure

func reject(reason:StringName) -> void:
	if not has_failed():
		_failure = reason if reason != &"" else &"clone_rejected"

func is_copying() -> bool:
	return _depth > 0

# 授权只来自显式模板根 identity，不修改模板、不读 current。
func configure_template(source_context:SessionContext, trusted_templates:Array) -> bool:
	if is_copying() or has_failed() or _template_source != null:
		reject(&"invalid_clone_configuration")
		return false
	if not SessionGeneration.validate_context(source_context).ok:
		reject(&"stale_session")
		return false
	_template_source = source_context
	_action_source = source_context
	_collect_templates(trusted_templates, [])
	return not has_failed()

func copy_result(value, source_context:SessionContext = null) -> Dictionary:
	if source_context != null:
		if not SessionGeneration.validate_context(source_context).ok:
			reject(&"stale_session")
		elif _action_source != null and not is_same(_action_source.token(), source_context.token()):
			reject(&"stale_session")
		else:
			_action_source = source_context
	var cloned = copy(value)
	return {"ok":not has_failed(), "object":null if has_failed() else cloned, "reason":_failure if has_failed() else &"current"}

func copy(value):
	if has_failed():
		return _empty(value)
	var root:bool = not is_copying()
	var objects_before:Array = []
	var effects_before:Array = []
	if root:
		if _action_source != null and not SessionGeneration.validate_context(_action_source).ok:
			reject(&"stale_session")
		_preflight(value, [], false)
		if has_failed():
			return _empty(value)
		objects_before = GameData.objects.duplicate()
		effects_before = GameData.effects.duplicate()
	_depth += 1
	var cloned = _copy(value)
	_depth -= 1
	if root and has_failed():
		# 只撤本同步复制新登记的 identity；不触源图/外部效果池。
		for item in GameData.objects.duplicate():
			if not _contains_identity(objects_before, item):
				GameData.objects.erase(item)
		for item in GameData.effects.duplicate():
			if not _contains_identity(effects_before, item):
				GameData.effects.erase(item)
	return _empty(value) if has_failed() else cloned

func _empty(value):
	if value is Array:
		return []
	if value is Dictionary:
		return {}
	return null

func _contains_identity(items:Array, value) -> bool:
	for item in items:
		if is_same(item, value):
			return true
	return false

# 只追实际深复制边，from/参数游戏对象/展示引用均保持引用，不追。
func _children(value) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return value.values()
	if value is BaseCard:
		return [value._effects, value._attached_cards]
	if value is BaseMaster:
		return [value._effects, value._specials, value._upgrade_skill, value._other_things]
	if value is BaseServant:
		return [value._effects, value._specials]
	if value is BaseBuff:
		return [value._effects]
	if value is BaseEffect:
		var children:Array = [value._funcs]
		for option in value._options:
			if option is Dictionary:
				children.append(option.get("funcs", []))
				for requirement in option.get("activation_requirements", []):
					if requirement is Dictionary:
						children.append(requirement.get("funcs", []))
		return children
	return []

func _collect_templates(value, seen:Array) -> void:
	if not (value is Object or value is Array or value is Dictionary) or _contains_identity(seen, value):
		return
	seen.append(value)
	# 所有规则对象（卡/效果/buff/御主/从者，均继承 BaseObject）与函数同属可复制根；
	# 漏收会让 ManageBuff/SetPlayerData 等入口拒绝无来源副本。
	if value is BaseObject or value is BaseFunc:
		var status:Dictionary = SessionGeneration.origin_of(value)
		if status.reason == &"stale_session":
			reject(&"stale_session")
			return
		if not status.ok:
			_trusted.append(value)
	for child in _children(value):
		_collect_templates(child, seen)

func _preflight(value, path:Array, runtime_required:bool) -> void:
	if has_failed() or not (value is Object or value is Array or value is Dictionary):
		return
	if _contains_identity(path, value):
		reject(&"cyclic_clone_graph")
		return
	path.append(value)
	if value is BaseCard or value is BaseEffect or value is BaseFunc:
		var source:SessionContext = _source_for(value)
		if value is BaseCard or runtime_required or _contains_identity(_trusted, value):
			if source == null:
				reject(SessionGeneration.origin_of(value).reason)
		if value is BaseEffect or value is BaseFunc:
			var inherited:SessionContext = value.runtime_context()
			if inherited != null and not SessionGeneration.validate_context(inherited).ok:
				reject(&"stale_session")
			elif inherited == null and SessionGeneration.origin_of(value).ok:
				reject(&"unbound_origin")
			if source != null and value is BaseFunc and not value.execution_capability_status().ok:
				reject(&"undeclared_interpreter_capability")
	for child in _children(value):
		_preflight(child, path, runtime_required or value is BaseCard)
	path.pop_back()

func _source_for(value) -> SessionContext:
	var status:Dictionary = SessionGeneration.origin_of(value)
	if status.ok:
		var source:SessionContext = status.context
		if _action_source != null and (not SessionGeneration.validate_context(_action_source).ok or not is_same(source.token(), _action_source.token())):
			reject(&"stale_session")
			return null
		return source
	if status.reason != &"unbound_origin":
		reject(status.reason)
		return null
	if _template_source != null and _contains_identity(_trusted, value):
		if SessionGeneration.validate_context(_template_source).ok:
			return _template_source
		reject(&"stale_session")
	return null

# 六种卡只消费这个策略，必须在 new 前获得原来源。
func prepare_card(card:BaseCard) -> SessionContext:
	if has_failed():
		return null
	var source:SessionContext = _source_for(card)
	if source == null:
		reject(SessionGeneration.origin_of(card).reason)
	return source

func finish_card(original:BaseCard, cloned:BaseCard) -> BaseCard:
	if has_failed() or not _bind_copy(original, cloned):
		return null
	cloned.add_object()
	return cloned

func _bind_copy(original:Object, cloned:Object) -> bool:
	var source:SessionContext = _source_for(original)
	if has_failed():
		return false
	if source == null:
		return not original is BaseCard
	var bound:Dictionary = SessionGeneration.bind_origin(cloned, source.token(), source.origin())
	if not bound.ok:
		reject(bound.reason)
		return false
	if cloned is BaseEffect or cloned is BaseFunc:
		# runtime clone_data 保留原句柄，模板才沿新登记句柄绑定。
		if cloned.runtime_context() == null and not cloned.bind_runtime_context(bound.context):
			reject(&"runtime_binding_rejected")
			return false
	return true

func _copy(value):
	if value == null:
		return null
	if value is Array:
		var result:Array = []
		for item in value:
			var cloned = copy(item)
			if has_failed():
				return []
			result.append(cloned)
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			var cloned = copy(value[key])
			if has_failed():
				return {}
			result[key] = cloned
		return result
	if value is Object:
		if value.has_method("clone_data"):
			var cloned = value.clone_data(self)
			if cloned == null and not has_failed():
				reject(&"clone_rejected")
			# 卡在 finish_card 内已绑定；其余规则对象在此绑定原来源
			if not has_failed() and ((value is BaseObject and not value is BaseCard) or value is BaseFunc):
				_bind_copy(value, cloned)
			return null if has_failed() else cloned
		return null
	return value


#参数里的游戏对象是引用，只有显式声明值语义的对象才复制。
func copy_value(value):
	if value is Array:
		var result:Array = []
		for item in value:
			result.append(copy_value(item))
		return result
	if value is Dictionary:
		var result:Dictionary = {}
		for key in value:
			result[key] = copy_value(value[key])
		return result
	if value is Object and value.has_method("clone_value"):
		return value.clone_value(self)
	return value


#只在新拥有者就绪后建立数字索引，绝不写回源对象。
func copy_effects(effects:Array, owner) -> Array:
	var result = copy(effects)
	if has_failed():
		return []
	for effect in result:
		if effect != null:
			effect.from = owner
			effect.register_numbers_to_source()
	return result


func copy_specials(specials:Dictionary, owner) -> Dictionary:
	var result = copy(specials)
	if has_failed():
		return {}
	for value in result.values():
		var items:Array = value if value is Array else [value]
		for item in items:
			if item is Object and item.has_method("set_from"):
				item.set_from(owner)
	return result
