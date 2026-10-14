extends RefCounted

## 只分类发布结果，不发布文件、不控制进程、不推断保存结果。
## binding 是调用方已验证的完整实例标识，本模块仅做精确相等比较。
var _binding:Dictionary = {}
var _config:Dictionary = {}
var _status:String = "unobserved"
var _now_msec:int = -1
var _last_attempt_msec:int = -1
var _first_failure_msec:int = -1

static func valid_config(value:Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if key not in ["retry_interval_msec","failure_deadline_msec"]: return false
		if not value[key] is int or value[key] <= 0: return false
	return true

func configure(binding:Dictionary, config:Variant) -> bool:
	if binding.is_empty() or not valid_config(config): return false
	_binding = binding.duplicate(true)
	_config = config.duplicate(true)
	_status = "unobserved"
	_now_msec = -1
	_last_attempt_msec = -1
	_first_failure_msec = -1
	return true

func observe(binding:Dictionary, published:Variant, now_msec:int) -> bool:
	if not published is bool or not _accept(binding,now_msec): return false
	_now_msec = now_msec
	_last_attempt_msec = now_msec
	if published:
		_status = "healthy"
		_first_failure_msec = -1
	else:
		if _first_failure_msec < 0: _first_failure_msec = now_msec
		_status = "transient_failure"
	_update_status(now_msec)
	return true

func evaluate(binding:Dictionary, now_msec:int) -> Dictionary:
	if not _accept(binding,now_msec): return {"accepted":false}
	_now_msec = now_msec
	_update_status(now_msec)
	var retry_due:bool = _first_failure_msec >= 0 and _config.has("retry_interval_msec") and now_msec - _last_attempt_msec >= int(_config.retry_interval_msec)
	return {"accepted":true,"binding":_binding.duplicate(true),"status":_status,"retry_due":retry_due,"first_failure_msec":_first_failure_msec,"last_attempt_msec":_last_attempt_msec}

func _update_status(now_msec:int) -> void:
	# 用经过时间而不是 deadline 相加，避免接近 int64 上限时溢出。
	if _first_failure_msec >= 0 and _config.has("failure_deadline_msec") and now_msec - _first_failure_msec >= int(_config.failure_deadline_msec):
		_status = "supervision_failed"

func _accept(binding:Dictionary, now_msec:int) -> bool:
	return not _binding.is_empty() and binding == _binding and now_msec >= 0 and now_msec >= _now_msec