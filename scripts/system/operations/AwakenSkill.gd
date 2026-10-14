class_name AwakenSkill
extends RefCounted

const operation_router = preload("res://scripts/system/operation_router.gd")

#觉醒既有技能：唯一状态变更入口及其生命周期通知；是否加入技能区由解锁效果声明。
#不能创造技能或为其他玩家/模板觉醒；窗口由技能 values 声明，不写死腐蚀等具体卡名。
#context：本局来源，缺省取当前已验执行帧；技能须属本局，登记与解锁时点都沿用同一来源。
func exec(skill:BaseSkill, player_id:int = -1, context:Variant = null) -> bool:
	context = RegisterObjectEffects.captured_context(context)
	if skill == null or not RegisterObjectEffects.source_is_current(context, skill):
		return false
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	var id:int = resolved.id
	if skill._is_awakened or not GameData.player_data_library.has(id):
		return false
	var master = GameDataManager.get_player_data(id).get("master")
	if not (master is BaseMaster) or not master._upgrade_skill.has(skill):
		return false
	var last_round:int = int(skill._values.get("awaken_last_round", -1))
	if last_round >= 0 and GameProgress.current_round > last_round:
		return false
	#先验能否登记，避免留下「已觉醒但效果未生效」的半状态
	if not RegisterObjectEffects.can_register_object(skill, id, context):
		return false
	skill._is_awakened = true
	operation_router.exec_registered("register_object_effects", [skill, id, context], context)
	GameLog.record("skill_awakened", id, -1, "", skill, ["skill_awakened"], {})
	TimePointChecker.dynamic_time_point([TimePoints.SKILL_AWAKENED], id, skill, context)
	return true
