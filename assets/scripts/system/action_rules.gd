class_name ActionRules
extends RefCounted

#行动结束的声明式前置条件：结束行动前必须满足的条件写在玩家数据的
#action_requirements（Array[String]）里，由效果用现有数组原语（add_to_array /
#remove_from_array）增减，引擎按条件名判定。
#
#与 PlayRules / DeployRules 同类：条件类型集中在这一个文件，效果数据、界面与各阶段
#流程都不用改；未识别条件名一律视为已满足——缺声明不给行为，不拦老数据。
#
#为什么住在规则层而不是塞进 GameProgress：无界面推进（AI 推演、headless 回归）与界面
#点击必须共用同一判据，否则会出现"引擎拒绝但界面没提示"或相反的静默分裂。

const REQUIREMENT_KEY := "action_requirements"
##本回合必须使用过一枚令咒
const COMMAND_SPELL_USED := "command_spell_used"

const REASONS:Dictionary = {
	COMMAND_SPELL_USED: "本回合必须使用一枚令咒"
}


##此刻还差什么才能结束行动。返回空串表示可以结束。
static func block_reason(player_id:int) -> String:
	for requirement in requirements(player_id):
		if unmet(str(requirement), player_id):
			return str(REASONS.get(str(requirement), "尚未满足行动结束条件"))
	return ""


static func can_end_action(player_id:int) -> bool:
	return block_reason(player_id) == ""


static func requirements(player_id:int) -> Array:
	if !GameData.player_data_library.has(player_id):
		return []
	var value = GameData.player_data_library[player_id].get(REQUIREMENT_KEY, [])
	return value if value is Array else []


##某条要求此刻是否还没被满足
static func unmet(requirement:String, player_id:int) -> bool:
	match requirement:
		COMMAND_SPELL_USED:
			#事实查日志：本回合已经用过令咒就满足，不给玩家加状态字段
			if not GameLog.query({"type": COMMAND_SPELL_USED, "actor": player_id}, 0).is_empty():
				return false
			#例外：手上已经没有能发动的令咒（用光、被移出游戏、被禁令挡住）时，
			#这条要求根本无法履行，不能把玩家永久卡在行动阶段
			return has_usable_command_spell(player_id)
		_:
			return false


##该玩家此刻还留着一枚能发动的令咒。判据与界面的发动入口共用
##EffectManager.can_manual_activate，不在这里另写一套"能不能用"
static func has_usable_command_spell(player_id:int) -> bool:
	for card in GetPlCommandSpellOutGame.new().exec(player_id):
		var effects = card.get("_effects") if card != null else null
		if !(effects is Array):
			continue
		for effect in effects:
			if EffectManager.can_manual_activate(effect, player_id):
				return true
	return false
