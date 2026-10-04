class_name RestrictAbilities
extends RefCounted

# 只登记禁令；选择目标、获取来源和发动窗口均由调用方组合。
func exec(players:Array, phase_mids:Array, source:BaseHandCard = null, expire_round:bool = true, expire_source:bool = true) -> bool:
	if source == null: source = GetEffSourceCard.new().exec()
	return AbilityRestrictions.register(players, phase_mids, source, expire_round, expire_source)
