class_name NeverCountsPowerEffect
extends BaseEffect


#系统效果：携带此效果的卡牌不计入合计威力，即使处于明置状态。
#与CountsPowerWhileConcealedEffect互为另一个方向的例外，两者同时存在时本效果优先。
#不由时点触发，而是由威力判定入口(CardCountsPower)按效果名查询存在性。

const EFFECT_NAME:String = "never_counts_power"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
