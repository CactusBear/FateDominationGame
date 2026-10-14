class_name PayMagic
extends RefCounted

# 支付与“失去魔力”不同：必须付清；透支只能由本次调用显式许可。
# context 与两个 identity 必须在动作/报价创建处捕获，跨回调保留原引用。
# 只传整数或 token 不足以授权；这里不 bind，也不刷新为同 ID 的新对象。
# available 仅供只读组合报价；实际支付始终重新读取当时余额。
static func can_pay(amount:BaseNumber, player_id:int = -1, available = null, allow_overdraft:bool = false,
		context:Variant = null, expected_player:Variant = null, expected_magic:Variant = null) -> bool:
	var captured:Variant = _captured_context(context)
	var target:Dictionary = _payment_target(captured, player_id, expected_player, expected_magic)
	if target.is_empty():
		return false
	return _can_afford(amount, target.player, target.magic, available, allow_overdraft)

# dispatch_time_points 由调用方保留原有时点语义，不在这里推断支付用途。
func exec(amount:BaseNumber, player_id:int = -1, purpose:String = "", source = null, dispatch_time_points:bool = true, allow_overdraft:bool = false,
		context:Variant = null, expected_player:Variant = null, expected_magic:Variant = null) -> bool:
	var captured:Variant = _captured_context(context)
	var target:Dictionary = _payment_target(captured, player_id, expected_player, expected_magic)
	if target.is_empty():
		return false
	var id:int = target.id
	var d:Dictionary = target.player
	var magic:BaseNumber = target.magic
	if not _can_afford(amount, d, magic, null, allow_overdraft):
		return false
	# 免疫/零费用也必须经过来源与 identity 门，不能给旧意图报成功。
	if not _source_is_current(captured) or not _identity_is_current(id, d, magic):
		return false
	if d.get("is_magic_immune", false) or amount.number == 0:
		return true
	var before:float = magic.number
	magic.minus(amount)
	GameLog.record_resource_payment("magic", id, before, magic.number, purpose, source)
	if dispatch_time_points:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id, null, captured)
	return true

# 缺省只继承已验函数帧，不从 activating_eff/目标对象/current_token 补票。
static func _captured_context(context:Variant) -> Variant:
	if context != null:
		return context
	var frame:Dictionary = EffectManager.execution_context()
	return frame.get("context") if frame.get("ok", false) else null

static func _source_is_current(context:Variant) -> bool:
	if not SessionGeneration.validate_context(context).get("ok", false):
		return false
	# 与 ActivateEffect 的公开帧 ABI 相同；失效帧不能借另一个合法句柄。
	if not EffectManager.execution_runtime_snapshot().get("functions", []).is_empty():
		var frame:Dictionary = EffectManager.execution_context()
		return frame.get("ok", false) and is_same(frame.get("context"), context)
	return true

static func _identity_is_current(id:int, player:Dictionary, magic:BaseNumber) -> bool:
	if not GameData.player_data_library.has(id):
		return false
	return is_same(GameData.player_data_library.get(id), player) and is_same(player.get("magic"), magic)

static func _payment_target(context:Variant, player_id:int, expected_player:Variant, expected_magic:Variant) -> Dictionary:
	# 来源验证必须先于 resolve/find/balance 的任何首读。
	if not _source_is_current(context):
		return {}
	if not expected_player is Dictionary or not expected_magic is BaseNumber:
		return {}
	var id:int = EffectManager.resolve_player_id(player_id)
	if not _identity_is_current(id, expected_player, expected_magic):
		return {}
	return {"id":id, "player":expected_player, "magic":expected_magic}

static func _can_afford(amount:BaseNumber, player:Dictionary, magic:BaseNumber, available:Variant, allow_overdraft:bool) -> bool:
	if amount == null or not is_finite(amount.number) or amount.number < 0:
		return false
	if player.get("is_magic_immune", false) or amount.number == 0:
		return true
	if available != null and typeof(available) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var balance:float = magic.number if available == null else float(available)
	return is_finite(balance) and is_finite(balance - amount.number) and (allow_overdraft or balance >= amount.number)
