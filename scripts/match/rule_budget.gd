extends RefCounted

var enabled: bool = false
var steps: int = 0
var seconds: float = 0.0
var completed: int = 0
var paused: bool = false
var reason: String = ""
var _started: int = 0

static func encode_json_config(config:Dictionary) -> Dictionary:
	var encoded := config.duplicate(true)
	# 内部 JSON 文件采用显式十进制字符串，避免解析浮点后丢失 int64 精度。
	encoded["steps"] = str(config.steps)
	return encoded

static func decode_json_config(encoded:Dictionary) -> Dictionary:
	var text = encoded.get("steps")
	if not text is String or not text.is_valid_int() or text.begins_with("-") or text.begins_with("+"):
		return {}
	if text.length() > 19 or (text.length() == 19 and text > "9223372036854775807"):
		return {}
	var limit:int = text.to_int()
	if str(limit) != text:
		return {}
	var config := encoded.duplicate(true)
	config["steps"] = limit
	return config

func configure(config: Dictionary) -> bool:
	for key in config:
		if key not in ["enabled", "steps", "seconds"]:
			return false
	if not config.get("enabled") is bool or not config.get("steps") is int:
		return false
	if typeof(config.get("seconds")) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var duration := float(config.seconds)
	if config.steps < 0 or not is_finite(duration) or duration < 0:
		return false
	enabled = config.enabled
	steps = config.steps
	seconds = duration
	begin_slice()
	return true

func begin_slice() -> void:
	completed = 0
	paused = false
	reason = ""
	_started = Time.get_ticks_usec() if enabled else 0

func checkpoint() -> bool:
	if not enabled:
		return true
	if paused:
		return false
	if steps > 0 and completed >= steps:
		paused = true
		reason = "step_budget"
	# 时间预算是协作软预算：每次明确续行至少允许一个新安全步骤。
	elif completed > 0 and seconds > 0 and Time.get_ticks_usec() - _started >= seconds * 1000000.0:
		paused = true
		reason = "time_budget"
	if paused:
		return false
	completed += 1
	return true

func status() -> Dictionary:
	return {"enabled": enabled, "paused": paused, "reason": reason, "completed": completed, "steps": steps, "seconds": seconds}
