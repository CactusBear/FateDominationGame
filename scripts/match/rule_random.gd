extends RefCounted

## 规则随机只承载已声明的显式流；未知流不伪造种子，也不转接到引擎全局随机。
## Scope 是本次 forecast/拒付恢复的局部流：fork 从父流复制状态，子流的消费与恢复互不回写父流。

const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
const MAX_VERSION:int = 9223372036854775807

class Scope extends RefCounted:
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var _state:Dictionary = {"known":false,"mode":"unknown","seed":"0","state":"0","version":0}
	var _exhausted:bool = false
	var _known:bool:
		get: return _state.known
		set(value): _state.known = value
	var _mode:String:
		get: return _state.mode
		set(value): _state.mode = value

	func _init(seed_value: int = 0, state_value: int = 0, known_value: bool = false, mode_value: String = "unknown") -> void:
		_known = known_value
		_mode = mode_value
		if _known:
			_rng.seed = seed_value
			_rng.state = state_value
			_save_cache()

	## 从当前 scope 复制出一个独立子流；父 scope 不会前进。
	func fork_scope() -> Scope:
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return null
			if not is_same(view, self): return view.fork_scope()
		if _exhausted or not _known:
			return null
		var child := Scope.new()
		if not child.restore(snapshot()):
			return null
		return child

	func fork() -> Scope:
		return fork_scope()

	## 只恢复本 scope 的 RNG 前态，不触碰创建它的父 scope。
	func restore(record: Dictionary) -> bool:
		if Domain.current_frame().status == "COMPLETED": return false
		if not _valid_record(record):
			return false
		if not _advance(): return false
		_rng.seed = record["seed"].to_int()
		_rng.state = record["state"].to_int()
		_save_cache()
		_known = true
		_mode = "known_stream"
		return true

	func restore_scope(record: Dictionary) -> bool:
		return restore(record)

	func snapshot() -> Dictionary:
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return {"known":false,"mode":"unknown"}
			if not is_same(view, self): return view.snapshot()
		if _exhausted or not _known:
			return {"known": false, "mode": _mode}
		return {"known": true, "seed": _state.seed, "state": _state.state}

	func capability() -> Dictionary:
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return {"known":false,"mode":"unknown","ownership":"rule_random"}
			if not is_same(view, self): return view.capability()
		return {"known": not _exhausted and _known, "mode": _mode, "ownership": "scope"}

	func is_known() -> bool:
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return false
			if not is_same(view, self): return view.is_known()
		return not _exhausted and _known

	func int_in_range(first: int, last: int):
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return null
			if not is_same(view, self): return view.int_in_range(first, last)
		if _exhausted or not _known:
			return null
		if not _advance(): return null
		_load_cache()
		var sampled:int = _rng.randi_range(first, last)
		_save_cache()
		return sampled

	func float_in_range(first: float, last: float):
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return null
			if not is_same(view, self): return view.float_in_range(first, last)
		if _exhausted or not _known:
			return null
		if not _advance(): return null
		_load_cache()
		var sampled:float = _rng.randf_range(first, last)
		_save_cache()
		return sampled

	func pick(items: Array):
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return null
			if not is_same(view, self): return view.pick(items)
		if Domain.current_frame().status == "COMPLETED":
			var mapped:Dictionary = Domain.resolve_root(&"atomic_graph_session").value.resolve(items)
			if mapped.status != "COMPLETED" or not mapped.value is Array: return null
			items = mapped.value
		if items.is_empty() or _exhausted or not _known:
			return null
		var sampled = int_in_range(0, items.size() - 1)
		return null if sampled == null else items[sampled]

	func shuffle(items: Array) -> bool:
		if Domain.current_frame().status == "COMPLETED":
			var view = _domain_scope(self)
			if view == null: return false
			if not is_same(view, self): return view.shuffle(items)
			var mapped:Dictionary = Domain.resolve_root(&"atomic_graph_session").value.resolve(items)
			if mapped.status != "COMPLETED" or not mapped.value is Array: return false
			items = mapped.value
		if _exhausted or not _known:
			return false
		for index in range(items.size() - 1, 0, -1):
			var other = int_in_range(0, index)
			if other == null: return false
			var previous = items[index]
			items[index] = items[other]
			items[other] = previous
		return true

	func _valid_record(record: Dictionary) -> bool:
		if not record.get("known") is bool or record.get("known") != true:
			return false
		if not record.get("seed") is String or not record.get("state") is String:
			return false
		for key in ["seed", "state"]:
			var text := str(record[key])
			if text.is_empty() or str(text.to_int()) != text:
				return false
		return true


	static func _domain_scope(scope:Scope):
		var root:Dictionary = Domain.resolve_root(&"atomic_graph_session")
		if root.status != "COMPLETED" or not root.value is RefCounted: return null
		if root.value.get_script() != load("res://scripts/match/graph_session.gd"): return null
		var result:Dictionary = root.value.resolve(scope)
		return result.get("value") if result.status == "COMPLETED" and result.get("value") is Scope else null

	## Raw authoritative E3 state; native cache is private and never an install target.
	func _load_cache() -> void:
		_rng.seed = _state.seed.to_int()
		_rng.state = _state.state.to_int()
	func _save_cache() -> void:
		_state.seed = str(_rng.seed)
		_state.state = str(_rng.state)
	func _advance() -> bool:
		if _exhausted or _state.version == MAX_VERSION:
			_exhausted = true
			return false
		_state.version += 1
		return true
	func stream_version() -> int:
		return _state.version
	func graph_stream_descriptor() -> Dictionary:
		return {"identity":self,"backing":_state,"native_cache":_rng,"version":_state.version,"exhausted":_exhausted}

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _state:Dictionary = {"known":false,"mode":"unknown","seed":"0","state":"0","version":0}
static var _exhausted:bool = false
static var _stream_handle:RefCounted = RefCounted.new()
static var _tracking:bool:
	get: return _state.known
	set(value): _state.known = value
static var _capability_mode:String:
	get: return _state.mode
	set(value): _state.mode = value

## 声明一个新的已知流。仅初始化本文件拥有的显式 RNG，不改变引擎全局 RNG。
static func start_seed(value: int) -> void:
	# D lifecycle mutation requires the C owner admission; absent seam stays closed.
	if Domain.current_frame().status == "COMPLETED": return
	if not _advance(): return
	_rng.seed = value
	_save_cache()
	_tracking = true
	_capability_mode = "known_stream"

## 缺少流声明时回到 unknown；后续取样返回 null 而不是偷偷走全局随机。
static func stop_tracking() -> void:
	# D lifecycle mutation requires the C owner admission; absent seam stays closed.
	if Domain.current_frame().status == "COMPLETED": return
	if not _advance(): return
	_tracking = false
	_capability_mode = "unknown"

## 公开能力声明适配。known_stream 必须已有 start_seed 或完整 seed/state 记录。
static func declare_capability(declaration: Dictionary) -> Dictionary:
	# D lifecycle mutation requires the C owner admission; absent seam stays closed.
	if Domain.current_frame().status == "COMPLETED": return capability()
	if not _advance(): return capability()
	var mode := str(declaration.get("mode", "unknown"))
	match mode:
		"none":
			_tracking = false
			_capability_mode = "none"
		"known_stream":
			if declaration.has("seed") and declaration.has("state"):
				if not restore({"known": true, "seed": str(declaration["seed"]), "state": str(declaration["state"])}):
					_tracking = false
					_capability_mode = "unknown"
			else:
				_tracking = false
				_capability_mode = "unknown"
		_:
			_tracking = false
			_capability_mode = "unknown"
	return capability()

static func set_capability_mode(mode: String) -> bool:
	# D lifecycle mutation requires the C owner admission; absent seam stays closed.
	if Domain.current_frame().status == "COMPLETED": return false
	if not _advance(): return false
	var requested := str(mode)
	if requested == "known_stream":
		if not _tracking:
			return false
		_capability_mode = requested
		return true
	if requested == "none" or requested == "unknown":
		_tracking = false
		_capability_mode = requested
		return true
	return false

static func capability() -> Dictionary:
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return {"known":false,"mode":"unknown","ownership":"rule_random"}
		return view.capability()
	return {"known": not _exhausted and _tracking, "mode": _capability_mode, "ownership": "rule_random"}

static func is_known() -> bool:
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return false
		return view.is_known()
	return not _exhausted and _tracking and _capability_mode == "known_stream"

## 从当前已知父流建立局部 scope；unknown 不被提升为可执行流。
static func fork_scope(parent: Variant = null) -> Scope:
	if parent is Scope: return parent.fork_scope()
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return null
		return view.fork_scope()
	if parent is Scope:
		return parent.fork_scope()
	if not is_known():
		return null
	var child := Scope.new()
	if not child.restore(snapshot()):
		return null
	return child

static func fork(parent: Variant = null) -> Scope:
	return fork_scope(parent)

static func snapshot_scope(scope: Variant) -> Dictionary:
	if scope is Scope:
		return scope.snapshot()
	return {"known": false, "mode": "unknown"}

static func restore_scope(scope: Variant, record: Dictionary) -> bool:
	if scope is Scope:
		return scope.restore(record)
	return false

static func int_in_range(first: int, last: int):
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return null
		return view.int_in_range(first, last)
	if not is_known():
		return null
	if not _advance(): return null
	_load_cache()
	var sampled:int = _rng.randi_range(first, last)
	_save_cache()
	return sampled

static func float_in_range(first: float, last: float):
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return null
		return view.float_in_range(first, last)
	if not is_known():
		return null
	if not _advance(): return null
	_load_cache()
	var sampled:float = _rng.randf_range(first, last)
	_save_cache()
	return sampled

static func pick(items: Array):
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return null
		return view.pick(items)
	if items.is_empty() or not is_known():
		return null
	var sampled = int_in_range(0, items.size() - 1)
	return null if sampled == null else items[sampled]

static func shuffle(items: Array) -> bool:
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return false
		return view.shuffle(items)
	if not is_known():
		return false
	for index in range(items.size() - 1, 0, -1):
		var other = int_in_range(0, index)
		if other == null: return false
		var previous = items[index]
		items[index] = items[other]
		items[other] = previous
	return true

static func snapshot() -> Dictionary:
	if Domain.current_frame().status == "COMPLETED":
		var view = _domain_stream()
		if view == null: return {"known":false,"mode":"unknown"}
		return view.snapshot()
	if not is_known():
		return {"known": false, "mode": _capability_mode}
	# JSON 会把大整数解析成 float，必须保存十进制字符串。
	return {"known": true, "seed": _state.seed, "state": _state.state}

static func restore(record: Dictionary) -> bool:
	# D lifecycle mutation requires the C owner admission; absent seam stays closed.
	if Domain.current_frame().status == "COMPLETED": return false
	if not _valid_record(record):
		return false
	if not _advance(): return false
	_rng.seed = record["seed"].to_int()
	_rng.state = record["state"].to_int()
	_save_cache()
	_tracking = true
	_capability_mode = "known_stream"
	return true

static func _valid_record(record: Dictionary) -> bool:
	if not record.get("known") is bool or record.get("known") != true:
		return false
	if not record.get("seed") is String or not record.get("state") is String:
		return false
	for key in ["seed", "state"]:
		var text := str(record[key])
		if text.is_empty() or str(text.to_int()) != text:
			return false
	return true

## Only an authenticated same-session resolver may supply D service/explicit scope.
static func _domain_stream():
	var root:Dictionary = Domain.resolve_root(&"atomic_graph_session")
	if root.status != "COMPLETED" or not root.value is RefCounted: return null
	if root.value.get_script() != load("res://scripts/match/graph_session.gd"): return null
	return root.value.random_service_view()
static func _load_cache() -> void:
	_rng.seed = _state.seed.to_int()
	_rng.state = _state.state.to_int()
static func _save_cache() -> void:
	_state.seed = str(_rng.seed)
	_state.state = str(_rng.state)
static func _advance() -> bool:
	if _exhausted or _state.version == MAX_VERSION:
		_exhausted = true
		return false
	_state.version += 1
	return true
static func stream_version() -> int:
	return _state.version
static func graph_stream_descriptor() -> Dictionary:
	return {"identity":_stream_handle,"backing":_state,"native_cache":_rng,"version":_state.version,"exhausted":_exhausted}
