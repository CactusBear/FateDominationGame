class_name QueryLog
extends RefCounted

#查游戏日志：筛出过去发生过的条目，供效果取历史信息——
#如"上回合我在战斗阶段是否与被淘汰的玩家同场""本回合我打出了几张迅捷攻击"。
#历史事实统一存在 GameLog 里，各种效果就不必各自维护快照字段。
#filter: 匹配 type / actor / target / place / tags / data 里的键值。
#        actor 传 -1 时按当前效果的触发者查（与其它 operation 的玩家参数一致）
#round_offset: 0=本回合、-1=上一回合…；传 null 表示不限回合
#limit: >0 时只取最近这么多条
func exec(filter:Dictionary = {}, round_offset = 0, limit:int = -1) -> Array:
	var f:Dictionary = filter.duplicate(true)
	#actor 传 -1 表示"当前效果的触发者"；省略或传 null 表示不限玩家
	if f.has("actor"):
		if f["actor"] == null:
			#显式写 null 是"不限玩家"，要从条件里去掉；
			#留着会被当成"actor 必须等于 null"从而一条都匹配不到
			f.erase("actor")
		elif int(f["actor"]) == -1:
			f["actor"] = EffectManager.resolve_player_id(-1)
	return GameLog.query(f, round_offset, limit)
