class_name ExcludedFromBattleWinEffect
extends BaseEffect


#系统效果：战力结算判定胜者时忽略携带此效果buff的归属玩家——
#该玩家既无法赢得战斗，也不能作为最高合计威力者阻止其他玩家获胜。
#本效果不由时点触发，而是由BattleResolver在判定胜者前
#通过PlayerBuffsHaveEffect按效果名查询存在性。
#任何buff把本效果挂进自己的_effects即可获得此限制，规则位置无需针对具体buff改动。

const EFFECT_NAME:String = "excluded_from_battle_win_determination"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
