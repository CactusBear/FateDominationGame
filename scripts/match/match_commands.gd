class_name MatchCommands
extends RefCounted

const operation_router = preload("res://scripts/system/operation_router.gd")

## 本地指令入口。只组合已有引擎操作，不复制合法性规则；查询仍由调用方读取。
## context 必须来自可信动作创建处，或当前已经验证的函数帧；本类不向当前会话补票。
func _action_context(requested: Variant) -> SessionContext:
	var candidate: Variant = requested
	if candidate == null:
		var frame: Dictionary = EffectManager.execution_context()
		if frame.get("ok", false):
			candidate = frame.get("context")
	if not SessionGeneration.validate_context(candidate).get("ok", false):
		return null
	return candidate as SessionContext


## 选择/等待对象必须继续使用对象保存的原来源，不能由送达时的 current 替换。
func _effect_context(effect: BaseEffect, requested: Variant) -> SessionContext:
	if effect == null:
		return null
	var candidate: Variant = requested
	if candidate == null:
		candidate = effect.runtime_context()
	if not SessionGeneration.validate_context(candidate).get("ok", false):
		return null
	var runtime: SessionContext = effect.runtime_context()
	var origin: Dictionary = SessionGeneration.origin_of(effect)
	if runtime == null or not origin.get("ok", false):
		return null
	var registered: SessionContext = origin.get("context")
	# runtime clone 保留原执行句柄、登记时另发同 token 句柄；只接受对象自己的这两个句柄之一，
	# 外来同 token 句柄仍拒绝。两句柄必须同属一局。
	if not is_same(runtime.token(), registered.token()) or not (is_same(runtime, candidate) or is_same(registered, candidate)):
		return null
	return candidate as SessionContext


## 对象身份与来源句柄是两道独立门；同 token 的另一 context 也不能代替原对象来源。
func _subject_context(subject: Object, requested: Variant) -> SessionContext:
	var candidate: SessionContext = _action_context(requested)
	if candidate == null or subject == null:
		return null
	var origin: Dictionary = SessionGeneration.origin_of(subject)
	if not origin.get("ok", false) or not is_same(origin.get("context"), candidate):
		return null
	return candidate


func submit_group(player_id: int, cards: Array, hidden: Array, context: Variant = null) -> bool:
	var source: SessionContext = _action_context(context)
	if source == null:
		return false
	return RegularPlay.submit_group(player_id, cards, hidden, false, source)


func request_manual_activation(effect: BaseEffect, player_id: int, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.request_manual_activation(effect, player_id)


func set_card_concealed(card: BaseCard, concealed: bool, player_id: int, context: Variant = null) -> Variant:
	var source: SessionContext = _subject_context(card, context)
	if source == null:
		return false
	return operation_router.exec_registered("set_card_concealed", [card, concealed, player_id, source], source)


func deploy(location: BaseLocation, player_id: int, context: Variant = null) -> Variant:
	var result:Dictionary = deploy_result(location, player_id, context)
	return _legacy_deploy_value(result)


# 补充结果入口不替换既有 bool 协议；PARTIAL 明示位置已提交但收益拒绝。
func deploy_result(location: BaseLocation, player_id: int, context: Variant = null) -> Dictionary:
	var source: SessionContext = _action_context(context)
	if source == null or location == null or not CanGainMagic.source_is_current(source):
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	var settled: Variant = operation_router.exec_registered("deploy", [location, player_id, false, source], source)
	if settled != true:
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	var benefit:Dictionary = DeployRules.apply_benefit_result(location, player_id, source)
	var status:String = "COMPLETED" if benefit.status in ["COMPLETED", "CANCELLED"] else ("PENDING" if benefit.status == "PENDING" else "PARTIAL")
	return {"status":status, "placed":true, "location":location, "benefit":benefit}


func _legacy_deploy_value(result:Dictionary) -> Variant:
	if result.status == "PENDING":
		return null
	return result.status == "COMPLETED"


func move(step: int, player_id: int, context: Variant = null) -> Variant:
	var source: SessionContext = _action_context(context)
	if source == null:
		return null
	return operation_router.exec_registered("move", [BaseNumber.new(step), player_id, false, false, source], source)


func deploy_to_area(area: BaseMapArea, player_id: int, context: Variant = null) -> Variant:
	return _legacy_deploy_value(deploy_to_area_result(area, player_id, context))


func deploy_to_area_result(area: BaseMapArea, player_id: int, context: Variant = null) -> Dictionary:
	var source: SessionContext = _action_context(context)
	if source == null or area == null or not CanGainMagic.source_is_current(source):
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	var location: BaseLocation = DeployRules.pick_location(area)
	if location == null:
		return {"status":"REJECTED", "placed":false, "location":null, "benefit":{}}
	return deploy_result(location, player_id, source)


func submit_option_choice(effect: BaseEffect, selection, quantities: Dictionary = {}, context: Variant = null) -> bool:
	var source: SessionContext = _effect_context(effect, context)
	if source == null:
		return false
	for index in quantities:
		effect.set_option_quantity(int(index), int(quantities[index]))
	return EffectManager.submit_option_choice(effect, selection)


func submit_active_choice(effect: BaseEffect, activate: bool, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.submit_active_choice(effect, activate)


func cancel_pending_choice(effect: BaseEffect, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.cancel_pending_choice(effect)


func submit_card_selection(effect: BaseEffect, cards: Array, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.submit_card_selection(effect, cards)


func submit_player_selection(effect: BaseEffect, players: Array, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.submit_player_selection(effect, players)


func submit_location_selection(effect: BaseEffect, location: BaseLocation, context: Variant = null) -> bool:
	if _effect_context(effect, context) == null:
		return false
	return EffectManager.submit_location_selection(effect, location)


func confirm_battle_broadcast(player_id: int) -> void:
	GameProgress.confirm_battle_broadcast(player_id)


func end_current_player_action() -> bool:
	return GameProgress.end_current_player_action()
