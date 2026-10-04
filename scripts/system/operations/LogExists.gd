class_name LogExists
extends RefCounted

#历史上有没有发生过满足条件的事，例如"本局那个玩家解放过真名吗""有过被淘汰的人吗"。
#player_id 放在第 0 位：循环体里写 null 就能让当前元素(玩家id)被填进来；
#传 -1 表示"当前效果的触发者"，此时 filter 里若写了 actor 会被它覆盖。
#查询条件本身沿用 QueryLog，本操作只回答"有没有"
func exec(player_id:int = -1, filter:Dictionary = {}, round_offset = 0) -> bool:
	var f:Dictionary = filter.duplicate(true)
	#player_id 优先；传 -1 表示"当前效果的触发者"，与其它 operation 一致。
	#要查不限玩家的历史（如"本局有没有人解放过真名"），自己在 filter 里写 actor
	if player_id >= 0:
		f["actor"] = player_id
	elif !f.has("actor"):
		f["actor"] = -1
	return !QueryLog.new().exec(f, round_offset, 1).is_empty()
