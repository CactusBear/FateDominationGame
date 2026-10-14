class_name EditMagic
extends RefCounted

# 旧 descriptor 的 self_var 仍只收到普通 null／支付 bool，不泄漏新 Dictionary ABI。
func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, payment_purpose:String = "", payment_source = null, context:Variant = null):
	return exec_result(set_num, vary_num, player_id, payment_purpose, payment_source, context).legacy_value


# 与 exec 共用唯一实际实现；完整回执与控制状态独立于本次实际增量。
func exec_result(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1, payment_purpose:String = "", payment_source = null, context:Variant = null) -> Dictionary:
	context = CanGainMagic.captured_context(context)
	if not CanGainMagic.source_is_current(context):
		return _receipt("REJECTED", 0, false, "source_rejected")
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return _receipt("REJECTED", 0, false, "source_rejected")
	var id:int = resolved.id
	# 本操作不创建玩家；支付拒绝返回 false，普通编辑保留无结果的 no-op。
	if not GameData.player_data_library.has(id):
		return _receipt("REJECTED", 0, false if payment_purpose != "" else null, "unknown_member")
	var player_data:Dictionary = GameData.player_data_library[id]
	var magic:BaseNumber = player_data.get("magic") as BaseNumber
	if magic == null:
		return _receipt("REJECTED", 0, false, "missing_magic")
	# 把实际玩家字典和魔力对象一起锁定；同 ID 不代表仍是同一运行期对象。
	var before:float = magic.number
	# 就地改写自己的数字，不把效果数字挂到玩家身上；显式 null 仍表示不增减。
	var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)
	# 支付由 PayMagic 唯一执行；它在派发前扣固定 amount，回执不读派发后的全局差值。
	if payment_purpose != "" and target < before:
		if not _origin_is_current(context, id, player_data, magic, before):
			return _receipt("REJECTED", 0, false, "identity_changed")
		var immune:bool = player_data.get("is_magic_immune", false)
		var changeable:bool = magic.can_change
		var paid:bool = PayMagic.new().exec(BaseNumber.new(before - target), id, payment_purpose, payment_source, true, false, context, player_data, magic)
		var paid_delta:float = (target - before) if paid and not immune and changeable else 0
		var payment:Dictionary = _receipt("COMPLETED" if paid else "REJECTED", paid_delta, paid, "" if paid else "payment_rejected", paid_delta != 0)
		return _after_dispatch(payment, context)
	# 免疫遵守现有资源例外，不记本次资源变化事实。
	if player_data.get("is_magic_immune", false):
		return _receipt("COMPLETED", 0, null, "immune")
	# 即将获得魔力：BEFORE 可同步取消或改量。
	if target > before:
		# 现有 BEFORE 第四槽是业务主体，不能塞 context。有帧时帧来源必须就是本次 context（不借他源）；
		# 无帧（部署等效果外动作）用开头已验证为当前局的显式 context，监听效果各用自身来源运行。
		var frame:Dictionary = EffectManager.execution_context()
		if frame.get("ok", false) and not is_same(frame.get("context"), context):
			return _receipt("REJECTED", 0, false, "pending_origin_api_unavailable")
		var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD, id,
			{"amount": BaseNumber.new(target - before)})
		if not _origin_is_current(context, id, player_data, magic, before) or action.get("invalidated", false):
			return _receipt("REJECTED", 0, false, "identity_changed")
		if action.get("cancelled", false):
			return _receipt("CANCELLED", 0, null, "cancelled")
		var amount:BaseNumber = action.get("values", {}).get("amount") as BaseNumber
		if amount == null:
			return _receipt("REJECTED", 0, false, "missing_pending_amount")
		target = before + amount.number

	# BEFORE 后到真正写入之间只允许原玩家、原魔力对象继续提交。
	if not _origin_is_current(context, id, player_data, magic, before):
		return _receipt("REJECTED", 0, false, "identity_changed")
	magic.set_num(BaseNumber.new(target))

	#规则：魔力是 0 到上限之间的资源（上限本身是数据、效果可以改）。
	#夹在这里而不是让各调用方各写一个 min/max：获得魔力的来源有工房充能席、局势牌印刷魔力、
	#令咒、效果等多处，漏掉任何一处都会出现"21 / 12"这种界面与规则对不上的数字
	#上限按玩家取：有玩家级覆盖（间桐脏砚上限 16 这类）用覆盖值，否则用全局规则值
	var limit = GameData.player_magic_limit(id) as BaseNumber
	if limit != null and magic.number > limit.number:
		magic.set_num(limit)
	if magic.number < 0:
		magic.set_num(BaseNumber.new(0))

	#先把这次的差值固定下来并记完日志，再派发时点（理由同 EditScore）
	var delta = magic.number - before
	if payment_purpose != "" and delta < 0:
		GameLog.record_resource_payment("magic", id, before, magic.number, payment_purpose, payment_source)
	else:
		GameLog.record_resource_change("magic", id, before, magic.number)

	# 本次增量此刻固定；AFTER 监听再改资源也不会混入本回执。
	var result:Dictionary = _receipt("COMPLETED", delta, null, "", true)
	if delta > 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id, null, context)
	elif delta < 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id, null, context)
	return _after_dispatch(result, context)


static func _receipt(status:String, delta:float, legacy_value:Variant, reason:String = "", wrote:bool = false) -> Dictionary:
	return {"status":status, "actual_delta":delta, "legacy_value":legacy_value, "reason":reason, "wrote":wrote}


# PENDING 是后续效果尚待续，不等于增量为零；拒旧尾部也不伪称本次写入未发生。
func _after_dispatch(result:Dictionary, context:Variant) -> Dictionary:
	if not CanGainMagic.source_is_current(context):
		result.status = "REJECTED"
		result.reason = "source_changed_after_dispatch"
	elif EffectManager.runtime_guard_status().get("paused", false):
		result.status = "PENDING"
		result.reason = "after_dispatch_pending"
	return result


func _origin_is_current(context:SessionContext, id:int, player_data:Dictionary, magic:BaseNumber, before:float) -> bool:
	if not CanGainMagic.source_is_current(context):
		return false
	if not GameData.player_data_library.has(id):
		return false
	if not is_same(GameData.player_data_library.get(id), player_data):
		return false
	if not is_same(player_data.get("magic"), magic):
		return false
	return is_equal_approx(magic.number, before)
