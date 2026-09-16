class_name ForbidSpecialAttackEffect
extends BaseEffect


#系统效果：局面里有声明此效果的局势牌/事件牌时，特殊属性(special)的攻击牌禁止打出。
#本效果不由时点触发，而是由出牌入口(PlayAttack/PlaySkill)在打出前
#通过 BoardHasEffect 按效果名查询存在性。
#任何局势牌/事件牌把本效果挂进自己的 _effects 即可获得此禁令，
#规则位置无需针对具体牌改动
const EFFECT_NAME:String = "forbid_special_attack"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
