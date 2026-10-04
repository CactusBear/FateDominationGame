class_name DefeatBuff
extends BaseBuff


#【败北】是一种持续到回合结束的系统buff，其全部效果由挂在_effects里的BaseEffect表达：
#1. ExcludedFromBattleWinEffect：无法赢得战斗，也不能阻止其他玩家获胜。
#2. CannotPlayCardsEffect：无法打出卡牌(不影响已激活的牌和能力的其他使用)。
#规则位置(BattleResolver/PlayAttack/PlaySkill)通过PlayerBuffsHaveEffect按效果名查询，
#不针对DefeatBuff类型做任何专门判断。
#
#规则：你可以同时具有多层【败北】状态，所以apply不做去重，每次调用叠加一层。
#is_battle_lose/is_battle_win等战斗胜负标记由BattleResolver自行管理，本buff不触碰，
#以便特殊效果赋予的【败北】不会被误当成常规战斗失败。

const DEFEAT_BUFF_NAME:String = "defeat"


func _init():
	#BaseBuff._init只需要name和img；败北buff不需要图片
	super(DEFEAT_BUFF_NAME, "")
	var excluded = ExcludedFromBattleWinEffect.new()
	excluded.from = self
	add_buff_effect(excluded)
	var cannot_play = CannotPlayCardsEffect.new()
	cannot_play.from = self
	add_buff_effect(cannot_play)


#给指定玩家附加一层【败北】，可叠加
static func apply(player_id:int = GameData.player_id) -> DefeatBuff:
	var defeat = DefeatBuff.new()
	ManageBuff.new().exec(defeat, player_id, true)
	return defeat


#移除指定玩家的所有【败北】(通常由回合结束清理调用)
static func remove(player_id:int = GameData.player_id):
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var buffs:Array = player_data["buffs"]
	for i in range(buffs.size() - 1, -1, -1):
		if buffs[i] is DefeatBuff:
			var defeat = buffs[i] as DefeatBuff
			#BaseEffect构造时会登记进GameData.effects，随buff一起摘除，避免残留
			for eff in defeat._effects:
				if eff is BaseEffect:
					eff.del()
			ManageBuff.new().exec(defeat, player_id, false)


#清除所有玩家的【败北】
static func clear_all():
	for id in GameData.player_data_library.keys():
		remove(id)


#玩家当前的【败北】层数
static func get_defeat_count(player_id:int = GameData.player_id) -> int:
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var count:int = 0
	for buff in player_data["buffs"]:
		if buff is DefeatBuff and buff._is_active:
			count += 1
	return count


static func is_defeated(player_id:int = GameData.player_id) -> bool:
	return get_defeat_count(player_id) > 0
