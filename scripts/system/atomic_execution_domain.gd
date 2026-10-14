extends RefCounted
## A4 ABI v1. 仅封闭域基础设施；不自动 fork，不交换任何 live backing。
## owner 对 roots/memo/写集的完整性、无逃逸及外部写者屏障负责。
const ABI_VERSION:int = 1
static var _frames:Array = []
static var _window:RefCounted = null
var _roots:Dictionary = {}
var _bindings:Array = []
var _writes:Array = []
# 新载体启用时采用整写集失败锁；纯旧槽载体仍保留原拒绝/后续 seal 语义。
var _container_writes:Array = []
# seal 期间保留旧槽值：内建赋值也不得因最后引用释放而运行 PREDELETE。
var _slot_keepalive:Array = []
var _container_staging_used:bool = false
var _staging_failure:String = ""
var _sealed:bool = false
var _discarded:bool = false
var _installed:bool = false
var _identity:RefCounted = RefCounted.new()

func identity() -> RefCounted:
	return _identity

## Core E2 internal liveness seam; no owner callbacks or lifecycle issuance.
func _execution_binding_active() -> bool:
	return not _discarded and not _installed

func bind_root(name:StringName, private_state:Variant) -> Dictionary:
	if _sealed or _discarded or name.is_empty() or _roots.has(name):
		return _result("REJECTED", "root_binding_closed_or_duplicate")
	_roots[name] = private_state
	return _result("COMPLETED")

## identity memo，不用内容相等替代身份。完整图遍历/Callable 重绑属于 Graph owner。
func bind_dependency(original:Variant, private_value:Variant) -> Dictionary:
	if _sealed or _discarded or not _is_reference(original) or not _is_reference(private_value):
		return _result("REJECTED", "invalid_dependency_binding")
	if is_same(original, private_value):
		return _result("REJECTED", "live_alias_not_rebound")
	for binding in _bindings:
		if is_same(binding[0], original):
			return _result("REJECTED", "dependency_already_bound")
	_bindings.append([original, private_value])
	return _result("COMPLETED")

func enter_frame(plan_identity:RefCounted, original_context:Variant) -> Dictionary:
	if not Thread.is_main_thread() or _sealed or _discarded or _window != null:
		return _result("REJECTED", "frame_entry_closed")
	var marker:RefCounted = RefCounted.new()
	_frames.append({"marker":marker, "domain":self, "plan_identity":plan_identity,
		"original_context":original_context})
	return {"status":"COMPLETED", "reason":"", "frame_marker":marker}

static func leave_frame(frame_marker:Variant) -> Dictionary:
	if not Thread.is_main_thread() or _frames.is_empty() or not is_same(_frames.back().marker, frame_marker):
		return {"status":"REJECTED", "reason":"frame_not_current"}
	_frames.pop_back()
	return {"status":"COMPLETED", "reason":""}

## 返回只读帧记录（不是服务状态）；域外没有 D。挂起前必须退出帧。
static func current_frame() -> Dictionary:
	if not Thread.is_main_thread() or _frames.is_empty():
		return {"status":"REJECTED", "reason":"no_controlled_frame"}
	var view:Dictionary = _frames.back().duplicate()
	view["status"] = "COMPLETED"
	view["reason"] = ""
	view.make_read_only()
	return view

static func resolve_root(name:StringName) -> Dictionary:
	var frame:Dictionary = current_frame()
	if frame.status != "COMPLETED":
		return frame
	var domain = frame.domain
	if not domain._roots.has(name):
		return {"status":"REJECTED", "reason":"undeclared_root"}
	return {"status":"COMPLETED", "reason":"", "value":domain._roots[name]}

static func rebind_dependency(original:Variant) -> Dictionary:
	var frame:Dictionary = current_frame()
	if frame.status != "COMPLETED":
		return frame
	for binding in frame.domain._bindings:
		if is_same(binding[0], original):
			return {"status":"COMPLETED", "reason":"", "value":binding[1]}
	return {"status":"REJECTED", "reason":"unbound_dependency"}

## 最小无访问器槽载体：原始、无类型、可写 Dictionary/Array 的槽位赋值。
## stage_slot 本身仍不支持删除/扩容；新增整容器载体不得与它同目标混用。
func stage_slot(target:Variant, key:Variant, value:Variant, kind:StringName) -> Dictionary:
	if _sealed or _discarded or kind not in [&"rule", &"journal", &"runtime"]:
		return _staging_rejected("staging_closed_or_unknown_kind")
	if not _slot_valid(target, key):
		return _staging_rejected("unsupported_backing_slot")
	for contents in _container_writes:
		if is_same(contents.target, target):
			return _staging_rejected("overlapping_backing_target")
	for write in _writes:
		if is_same(write.target, target) and is_same(write.key, key):
			return _staging_rejected("duplicate_backing_slot")
	_writes.append({"target":target, "key":key, "value":value, "kind":kind})
	return _result("COMPLETED")

## 规则写集，不是 outbox。owner 先完成整图反向重绑与资格证明。
## 私有浅槽快照保留 Object/容器 identity；不 deep duplicate，不调用 owner。
func stage_container_contents(target:Variant, prepared_items:Variant, kind:StringName) -> Dictionary:
	if _sealed or _discarded:
		return _result("REJECTED", "staging_closed_or_unknown_kind")
	_container_staging_used = true
	if kind not in [&"rule", &"journal", &"runtime"]:
		return _staging_rejected("staging_closed_or_unknown_kind")
	if not _container_valid(target) or typeof(target) != typeof(prepared_items):
		return _staging_rejected("unsupported_backing_container")
	for write in _writes:
		if is_same(write.target, target):
			return _staging_rejected("overlapping_backing_target")
	for contents in _container_writes:
		if is_same(contents.target, target):
			return _staging_rejected("duplicate_backing_container")
	# 基线持续强持有旧 key/value，防止 assign/clear 释放最后引用而触发 PREDELETE 回调。
	var baseline:Variant = target.duplicate(false)
	var prepared:Variant = prepared_items.duplicate(false)
	baseline.make_read_only()
	prepared.make_read_only()
	_container_writes.append({"target":target, "baseline":baseline, "prepared":prepared, "kind":kind})
	return _result("COMPLETED")

func _staging_rejected(reason:String) -> Dictionary:
	# sealed 后的非法追加不能污染已经冻结的合法安装；旧纯槽拒绝不改变 seal。
	if not _sealed and not _discarded and _staging_failure.is_empty():
		_staging_failure = reason
	return _result("REJECTED", reason)

## 窗口是全进程主线程独占门；所有外部/线程写者仍须 owner 参加同一屏障。
static func acquire_publication_window() -> Dictionary:
	if not Thread.is_main_thread() or _window != null or not _frames.is_empty():
		return {"status":"REJECTED", "reason":"publication_window_busy"}
	_window = RefCounted.new()
	return {"status":"COMPLETED", "reason":"", "window":_window}

static func release_publication_window(window:Variant) -> Dictionary:
	if not Thread.is_main_thread() or _window == null or not is_same(_window, window):
		return {"status":"REJECTED", "reason":"not_publication_owner"}
	_window = null
	return {"status":"COMPLETED", "reason":""}

static func publication_is_open() -> bool:
	return _window != null

func seal(window:Variant) -> Dictionary:
	if _sealed or _discarded or _installed or _window == null or not is_same(_window, window):
		return _result("REJECTED", "domain_not_sealable")
	if _container_staging_used and not _staging_failure.is_empty():
		return _result("REJECTED", "container_write_set_failed:" + _staging_failure)
	for write in _writes:
		if not _slot_valid(write.target, write.key):
			return _result("REJECTED", "backing_slot_changed")
	for i in range(_container_writes.size()):
		var contents:Dictionary = _container_writes[i]
		if not _container_valid(contents.target) or not _container_baseline_matches(contents.target, contents.baseline):
			return _result("REJECTED", "backing_container_changed")
		for write in _writes:
			if is_same(write.target, contents.target):
				return _result("REJECTED", "overlapping_backing_target")
		for j in range(i):
			if is_same(_container_writes[j].target, contents.target):
				return _result("REJECTED", "duplicate_backing_container")
	for write in _writes:
		# 只持有引用；不新增旧槽的读版本拒绝、不改变旧赋值语义。
		_slot_keepalive.append(write.target.get(write.key) if write.target is Dictionary else write.target[write.key])
	_sealed = true
	return _result("COMPLETED")

## 协调器专用；seal 后只有内建原始槽写，无 getter/setter/信号/await/用户回调。
## 业务拒绝只能发生于 seal 前；原生崩溃/OOM 不被伪装成 REJECTED。
func install_sealed(window:Variant) -> Dictionary:
	if not _sealed or _installed or _discarded or _window == null or not is_same(_window, window):
		return _result("FAULT", "invalid_install_boundary")
	for write in _writes:
		write.target[write.key] = write.value
	for contents in _container_writes:
		if contents.target is Array:
			contents.target.assign(contents.prepared)
		else:
			contents.target.clear()
			for key in contents.prepared:
				contents.target[key] = contents.prepared[key]
	_installed = true
	return _result("COMPLETED")

func discard() -> Dictionary:
	if _sealed or _installed:
		return _result("REJECTED", "sealed_domain_not_discardable")
	_discarded = true
	_roots.clear()
	_bindings.clear()
	_writes.clear()
	_container_writes.clear()
	_slot_keepalive.clear()
	return _result("COMPLETED")

static func _container_valid(target:Variant) -> bool:
	return (target is Array or target is Dictionary) and not target.is_typed() and not target.is_read_only()

static func _container_baseline_matches(target:Variant, baseline:Variant) -> bool:
	if typeof(target) != typeof(baseline) or target.size() != baseline.size():
		return false
	if target is Array:
		for i in range(target.size()):
			if not is_same(target[i], baseline[i]):
				return false
	else:
		# key 槽位顺序与 key/value 的精确 identity 均重验；不 deep 比较规则对象。
		var keys:Array = target.keys()
		var old_keys:Array = baseline.keys()
		for i in range(keys.size()):
			if not is_same(keys[i], old_keys[i]) or not is_same(target[keys[i]], baseline[old_keys[i]]):
				return false
	return true

static func _is_reference(value:Variant) -> bool:
	return value is Object or value is Array or value is Dictionary

static func _slot_valid(target:Variant, key:Variant) -> bool:
	if target is Dictionary:
		return not target.is_typed() and not target.is_read_only() and typeof(key) in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]
	if target is Array:
		return not target.is_typed() and not target.is_read_only() and key is int and key >= 0 and key < target.size()
	return false

static func _result(status:String, reason:String = "") -> Dictionary:
	return {"status":status, "reason":reason}
