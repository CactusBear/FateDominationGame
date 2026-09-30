class_name EditMagic
extends RefCounted

func exec(set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	#is_magic_immune是规则例外开关，由效果打开；本操作只负责尊重它，不解释谁赋予的
	if player_data.get("is_magic_immune", false):
		return
	var magic = player_data["magic"] as BaseNumber
	var before = magic.number
	#就地改写玩家自己的数字，不能把效果自带的数字对象直接挂到玩家身上，否则后续变化会污染卡面数值。
	#与 set_num 对称：缺省/显式传 null 表示这次只设值或不加不减，不能因此报错
	var target = (set_num.number if set_num != null else before) + (vary_num.number if vary_num != null else 0)
	#即将获得魔力：效果可以取消，或改写获得的数量（来源倍率、每回合获得上限）
	if target > before:
		var action:Dictionary = EffectManager.begin_pending_action(TimePoints.BEFORE_MAGIC_ADD, id,
			{"amount": BaseNumber.new(target - before)})
		if action.get("cancelled", false):
			return
		target = before + (action.values.amount as BaseNumber).number
	magic.set_num(BaseNumber.new(target))

	#规则：魔力是 0 到上限之间的资源（上限本身是数据、效果可以改）。
	#夹在这里而不是让各调用方各写一个 min/max：获得魔力的来源有工房充能席、局势牌印刷魔力、
	#令咒、效果等多处，漏掉任何一处都会出现"21 / 12"这种界面与规则对不上的数字
	#上限按玩家取：有玩家级覆盖（间桐脏砚上限 16 这类）用覆盖值，否则用全局规则值
	var limit = GameData.player_magic_limit(id) as BaseNumber
	if limit != null and magic.number > limit.number:
		magic.set_num(limit)
	if magic.number < 0:
		magic.set_num(BaseNumber.new(0))

	#先把这次的差值固定下来并记完日志，再派发时点（理由同 EditScore）
	var delta = magic.number - before
	GameLog.record_resource_change("magic", id, before, magic.number)

	if delta > 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_ADD], id)
	elif delta < 0:
		TimePointChecker.dynamic_time_point([TimePoints.MAGIC_DECREASE], id)
