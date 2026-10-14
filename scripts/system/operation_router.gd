extends RefCounted

# P00 冻结：注册键只能选择这里显式预加载的 operation，禁止按类名拼路径。
const _SCRIPTS_BY_CLASS := {
	"AddEventFromDeck": preload("res://scripts/system/operations/AddEventFromDeck.gd"),
	"AddMapAreaEvents": preload("res://scripts/system/operations/AddMapAreaEvents.gd"),
	"AddSkillToSkillZone": preload("res://scripts/system/operations/AddSkillToSkillZone.gd"),
	"ApplyCardKeywords": preload("res://scripts/system/operations/ApplyCardKeywords.gd"),
	"AskPlayerOption": preload("res://scripts/system/operations/AskPlayerOption.gd"),
	"ChangePlOrder": preload("res://scripts/system/operations/ChangePlOrder.gd"),
	"Deploy": preload("res://scripts/system/operations/Deploy.gd"),
	"DiscardPlayedCards": preload("res://scripts/system/operations/DiscardPlayedCards.gd"),
	"DrawCardByCard": preload("res://scripts/system/operations/DrawCardByCard.gd"),
	"DrawCardFromPlDeckToHand": preload("res://scripts/system/operations/DrawCardFromPlDeckToHand.gd"),
	"EditMagic": preload("res://scripts/system/operations/EditMagic.gd"),
	"EditPower": preload("res://scripts/system/operations/EditPower.gd"),
	"EditScore": preload("res://scripts/system/operations/EditScore.gd"),
	"EmitTimePoint": preload("res://scripts/system/operations/EmitTimePoint.gd"),
	"ManageBuff": preload("res://scripts/system/operations/ManageBuff.gd"),
	"Move": preload("res://scripts/system/operations/Move.gd"),
	"MoveLocation": preload("res://scripts/system/operations/MoveLocation.gd"),
	"PlayerBuffsHaveEffect": preload("res://scripts/system/operations/PlayerBuffsHaveEffect.gd"),
	"RefillHand": preload("res://scripts/system/operations/RefillHand.gd"),
	"RegisterObjectEffects": preload("res://scripts/system/operations/RegisterObjectEffects.gd"),
	"ReleaseTrueName": preload("res://scripts/system/operations/ReleaseTrueName.gd"),
	"RemoveFromBoard": preload("res://scripts/system/operations/RemoveFromBoard.gd"),
	"ReshuffleDiscard": preload("res://scripts/system/operations/ReshuffleDiscard.gd"),
	"RestoreLocationBenefits": preload("res://scripts/system/operations/RestoreLocationBenefits.gd"),
	"RestoreLocationPlNumLimits": preload("res://scripts/system/operations/RestoreLocationPlNumLimits.gd"),
	"RestoreMapAreaMoveFlags": preload("res://scripts/system/operations/RestoreMapAreaMoveFlags.gd"),
	"SetCardConcealed": preload("res://scripts/system/operations/SetCardConcealed.gd"),
	"SetLocation": preload("res://scripts/system/operations/SetLocation.gd"),
	"SyncPower": preload("res://scripts/system/operations/SyncPower.gd"),
	"UnregisterObjectEffects": preload("res://scripts/system/operations/UnregisterObjectEffects.gd")
}


# context 是路由资格，不插入/重排 operation 的业务参数。
# 旧二参只继承执行器已验帧；无帧直调必须显式保存并传入原来源。
static func exec_registered(func_name:String, parameters:Array = [], context:Variant = null) -> Variant:
	var source:Variant = context
	if source == null:
		var frame:Dictionary = EffectManager.execution_context()
		if not frame.get("ok", false):
			return null
		source = frame.get("context")
	if not _source_is_current(source):
		return null
	var entry:Dictionary = AllOperations.get_entry(func_name)
	if entry.is_empty():
		push_error("未注册的 operation：%s" % func_name)
		return null
	var class_name_value:String = entry.get("class", "")
	var operation_script = _SCRIPTS_BY_CLASS.get(class_name_value)
	if operation_script == null:
		push_error("首批路由未覆盖注册 operation：%s (%s)" % [func_name, class_name_value])
		return null
	if not _source_is_current(source):
		return null
	var operation = operation_script.new()
	if not operation.has_method("exec"):
		push_error("注册 operation 缺少 exec：%s" % class_name_value)
		return null
	if not _source_is_current(source):
		return null
	return operation.callv("exec", parameters)


static func _source_is_current(context:Variant) -> bool:
	return SessionGeneration.validate_context(context).get("ok", false)
