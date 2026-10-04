class_name CannotPlayCardsEffect
extends BaseEffect


#系统效果：携带此效果的buff会令其归属玩家无法打出卡牌
#(不影响已激活的牌和能力的其他使用)。
#本效果不由时点触发，而是由出牌入口(PlayAttack/PlaySkill)在打出前
#通过PlayerBuffsHaveEffect按效果名查询存在性。
#任何buff把本效果挂进自己的_effects即可获得此限制，规则位置无需针对具体buff改动。

const EFFECT_NAME:String = "cannot_play_cards"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
