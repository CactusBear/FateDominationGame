extends RefCounted

## 服务端策略的单一声明入口。新增枚举必须先接好管理器和权威工作进程。
const DEFAULTS:Dictionary = {
	"authority_host_mode":"dedicated",
	"transaction_log":true,
	"recovery_key_mismatch":"reject",
	"recovery_inheritance":"host_select",
}

static func validate(configuration:Dictionary, message_budget:int) -> Dictionary:
	var policy:Dictionary = DEFAULTS.duplicate(true)
	for key in DEFAULTS:
		if configuration.has(key): policy[key] = configuration[key]
	if not policy.authority_host_mode is String or policy.authority_host_mode != "dedicated":
		return {"ok":false,"error":"authority_host_mode 目前只支持 dedicated 权威子进程"}
	if not policy.transaction_log is bool:
		return {"ok":false,"error":"transaction_log 必须是显式布尔开关"}
	if not policy.recovery_key_mismatch is String or policy.recovery_key_mismatch != "reject":
		return {"ok":false,"error":"recovery_key_mismatch 目前只支持 reject；密钥不匹配不能自动认领"}
	if not policy.recovery_inheritance is String or policy.recovery_inheritance != "host_select":
		return {"ok":false,"error":"recovery_inheritance 目前只支持 host_select，由房主选择已认证新成员继承"}
	if message_budget <= 0 or var_to_bytes(policy).size() > message_budget:
		return {"ok":false,"error":"服务端策略超过内部单消息预算"}
	return {"ok":true,"policy":policy}
