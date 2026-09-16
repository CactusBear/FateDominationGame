class_name GetPlayerLocationBenefit
extends RefCounted

#查玩家当前所在位置的印刷地利数。战力结算"位于地利位置获得等同地利数的合计威力"是
#基础规则，数值来自位置自己声明的 _printed_benefit（印刷值），排除例外（如"不提供地利"
#的战场）由调用方先判断再决定要不要用这个结果，本操作只负责取数。
#不取 _benefit 而取印刷值：结算里的地利应遵循地形本身，效果对单个位置地利的临时增减
#由 EditLocationBenefit 改 _benefit，两者语义不同。位置为 null 时返回 0
func exec(player_id:int = -1) -> int:

	var loc = GetLocation.new().exec(player_id)
	if loc == null:
		return 0
	var benefit:BaseNumber = loc._printed_benefit
	if benefit == null:
		return 0
	return benefit.number
