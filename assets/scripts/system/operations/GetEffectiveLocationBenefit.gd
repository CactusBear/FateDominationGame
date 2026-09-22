class_name GetEffectiveLocationBenefit
extends RefCounted

#查玩家此刻真正享有的地利。基础规则：部署到地利位置、且在结算时仍位于该位置，
#获得等同该位置标注地利数的合计威力。所有例外与修正都由这里统一处理：
#  ① 战区级例外（"此战场的各地利位置不提供地利"）按战区上的 no_location_benefit 效果名查询；
#  ② 只有"部署"到该位置的玩家才算，部署之后移动（或经效果搬运）到同一位置的不算；
#  ③ 效果对该位置地利的临时修正（远隔操作"地利效果翻倍"、占领高地、卫宫"地利变为3倍"）：
#     效果改写席位的 _benefit，印刷值留在 _printed_benefit 作基线，
#     这里取 _benefit 为当前值 —— 只读 _printed_benefit 会让所有地利修正效果全部失效
#     （历史上正是如此：effect 改 _benefit、查询读 _printed_benefit，两个字段互不相干，
#      表现为"地利翻倍完全没有结算"）。
#部署事实查本回合的部署日志，不给玩家加"是否部署"的状态字段。
#界面显示合计威力与战力结算共用它，避免两边各判一套导致"界面显示有地利、结算却不给"。
func exec(player_id:int = -1) -> int:

	var id = EffectManager.resolve_player_id(player_id)
	var loc = GetLocation.new().exec(id)
	if loc == null:
		return 0
	var area := loc.get_from() as BaseMapArea
	if area != null and MapAreaHasEffect.new().exec(area, NoLocationBenefitEffect.EFFECT_NAME):
		return 0
	if !_deployed_here(id, loc):
		return 0
	return current_benefit(loc)


#某席位此刻的地利数：效果改过就用改后的值，没改过就是印刷值。
#单独抽出来供界面与其它查询复用，避免各处自己判断该读哪个字段
static func current_benefit(loc) -> int:
	if loc == null:
		return 0
	var current = loc._benefit
	if current is BaseNumber:
		return int(current.number)
	var printed = loc._printed_benefit
	if printed is BaseNumber:
		return int(printed.number)
	return 0


#本回合该玩家是否就是"部署"到了这个位置
func _deployed_here(player_id:int, loc) -> bool:
	if loc == null:
		return false
	for entry in GameLog.query({"type": "deploy", "actor": player_id}, 0):
		if entry.get("object") == loc:
			return true
	return false
