extends RefCounted

## 只有显式种子的规则会话声明状态已知；普通旧入口保留全局随机行为。
static var _rng := RandomNumberGenerator.new()
static var _tracking: bool = false

static func start_seed(value: int) -> void:
	seed(value)
	_rng.seed = value
	_tracking = true

static func stop_tracking() -> void:
	_tracking = false

static func int_in_range(first: int, last: int) -> int:
	return _rng.randi_range(first, last) if _tracking else randi_range(first, last)

static func float_in_range(first: float, last: float) -> float:
	if not _tracking:
		return randf_range(first, last)
	# Godot 全局函数使用 RandomPCG::randd，RNG 的范围函数使用 randf。
	# 对照 core/math/random_pcg.h 保留双精度取样及原始 PCG 消耗顺序。
	var exponent_sample: int = _rng.randi()
	if exponent_sample == 0:
		return 0.0 * (last - first) + first
	var leading_zeros := 0
	var mask: int = 1 << 31
	while exponent_sample & mask == 0:
		leading_zeros += 1
		mask >>= 1
	var high: int = _rng.randi() | (1 << 31)
	var low: int = _rng.randi() | 1
	var significand: float = float(high) * pow(2.0, 32) + float(low)
	var sample: float = significand * pow(2.0, -64 - leading_zeros)
	return sample * (last - first) + first

static func pick(items: Array):
	if items.is_empty():
		return null
	return items[_rng.randi() % items.size()] if _tracking else items.pick_random()

static func shuffle(items: Array) -> void:
	if not _tracking:
		items.shuffle()
		return
	for index in range(items.size() - 1, 0, -1):
		var other: int = _rng.randi() % (index + 1)
		var previous = items[index]
		items[index] = items[other]
		items[other] = previous

static func snapshot() -> Dictionary:
	if not _tracking:
		return {"known": false}
	# JSON 会把大整数解析成 float，必须保存十进制字符串。
	return {"known": true, "seed": str(_rng.seed), "state": str(_rng.state)}

static func restore(record: Dictionary) -> bool:
	if record.get("known") != true or not record.get("seed") is String or not record.get("state") is String:
		return false
	for key in ["seed", "state"]:
		if str(record[key].to_int()) != record[key]:
			return false
	_rng.seed = record.seed.to_int()
	_rng.state = record.state.to_int()
	_tracking = true
	return true
