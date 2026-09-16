class_name NoLocationBenefitEffect
extends BaseEffect


#系统效果：局面里声明此效果的战区（如"归零地"）在战力结算时不提供地利。
#本效果不由时点触发，而是由 BattleResolver 在计算玩家战力前
#通过 MapAreaHasEffect 按效果名查询该战区是否存在此声明。
#挂在哪个战区，哪个战区的地利就被排除——位置由牌挂载决定，不写死战区名
const EFFECT_NAME:String = "no_location_benefit"


func _init():
	#时点表为空：持续型被动，不进效果池的时点结算流程
	super(EFFECT_NAME, [], 0, true, false)
