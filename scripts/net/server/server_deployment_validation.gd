extends RefCounted

## 只读部署声明闭包；不持有 CLI、manager、全局 service 或历史房间配置。
## 数据/配额/数据根后续门仍由 CLI 原启动顺序执行，不从旧配置推导授权。
const Bootstrap = preload("res://scripts/net/server/server_bootstrap.gd")
const Paths = preload("res://scripts/net/server/recovery_path_safety.gd")
const CleanupPolicy = preload("res://scripts/net/server/temporary_cleanup_policy.gd")

static func configuration_error(configuration:Dictionary) -> String:
	if not configuration.get("broadcast_confirmation_capable",false) is bool: return "broadcast_confirmation_capable 必须是本机显式布尔声明"
	if heartbeat_config(configuration.get("heartbeat_publication",{})) == null: return "heartbeat_publication 配置无效"
	if cleanup_config(configuration.get("temporary_cleanup",{})) == null: return "temporary_cleanup 配置无效"
	# 仅剔除本机已校验字段；共享字段/角色门保持原次序和完整错误。
	var common:Dictionary = configuration.duplicate(true)
	common.erase("heartbeat_publication")
	common.erase("temporary_cleanup")
	common.erase("broadcast_confirmation_capable")
	return Bootstrap.configuration_error(common)

## 空集合只校验参数形状，不能证明运行中实例全集或授权实际清理。
static func cleanup_config(value:Variant) -> Variant:
	if not value is Dictionary: return null
	if value.is_empty(): return {"enabled":false}
	if not value.get("enabled") is bool: return null
	if not value.enabled: return {"enabled":false} if value.size() == 1 else null
	var fields:Array = ["enabled","ledger_path","interval_seconds","retention_seconds","max_files","max_bytes","approved_roots","protected_paths"]
	if value.size() != fields.size(): return null
	for key in value:
		if key not in fields: return null
	var config:Dictionary = value.duplicate(true)
	for key in ["interval_seconds","retention_seconds","max_files","max_bytes"]:
		var number:Variant = config[key]
		if not (number is int or number is float): return null
		if not is_finite(float(number)) or number < 0 or number > 9007199254740991 or float(number) != floor(float(number)): return null
		config[key] = int(number)
	if config.interval_seconds == 0: return null
	if not config.ledger_path is String or config.ledger_path.is_empty(): return null
	config.ledger_path = Paths.absolute(config.ledger_path)
	if config.ledger_path.is_empty() or not Paths.checked(config.ledger_path.get_base_dir(),config.ledger_path,true): return null
	var policy:Dictionary = config.duplicate(true)
	policy.current_instances = []
	if not CleanupPolicy.configuration_error(policy,0).is_empty(): return null
	return config

static func heartbeat_config(value:Variant) -> Variant:
	if not value is Dictionary: return null
	var config:Dictionary = {}
	for key in value:
		if key not in ["retry_interval_msec","failure_deadline_msec"]: return null
		var number = value[key]
		# JSON 数字仅转换精确可表示的有限整数，不截断或新增时长默认。
		if number is int:
			if number <= 0: return null
			config[key] = number
		elif number is float:
			if not is_finite(number) or number <= 0 or number > 9007199254740991 or floor(number) != number: return null
			config[key] = int(number)
		else: return null
	return config