class_name CountsPowerWhileConcealedEffect
extends BaseEffect


#系统效果：携带此效果的卡牌即使处于暗置状态也照常计入合计威力。
#默认规则是暗置牌不计合计威力，本效果为该规则的例外。
#不由时点触发，而是由威力判定入口(CardCountsPower)按效果名查询存在性。
#卡牌或赋予它效果的一方把本效果挂进卡的_effects即可，判定位置无需针对具体卡改动。

const EFFECT_NAME:String = "counts_power_while_concealed"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
