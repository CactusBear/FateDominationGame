class_name AwakenSkill
extends RefCounted

#觉醒既有技能：唯一状态变更入口及其生命周期通知；是否加入技能区由解锁效果声明。
#不能创造技能或为其他玩家/模板觉醒；窗口由技能 values 声明，不写死腐蚀等具体卡名。
func exec(skill:BaseSkill, player_id:int = -1) -> bool:
	var id:int = EffectManager.resolve_player_id(player_id)
	if skill == null or skill._is_awakened or not GameData.player_data_library.has(id):
		return false
	var master = GameDataManager.get_player_data(id).get("master")
	if not (master is BaseMaster) or not master._upgrade_skill.has(skill):
		return false
	var last_round:int = int(skill._values.get("awaken_last_round", -1))
	if last_round >= 0 and GameProgress.current_round > last_round:
		return false
	skill._is_awakened = true
	RegisterObjectEffects.new().exec(skill, id)
	GameLog.record("skill_awakened", id, -1, "", skill, ["skill_awakened"], {})
	TimePointChecker.dynamic_time_point([TimePoints.SKILL_AWAKENED], id, skill)
	return true
