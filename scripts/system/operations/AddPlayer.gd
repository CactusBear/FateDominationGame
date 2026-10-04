class_name AddPlayer
extends RefCounted

#新建一个玩家条目（分身棋子、NPC、代理实体……），返回它的玩家 id。只做"建条目"这一件事：
#放上版图用 deploy / set_location，设威力用 edit_power，登记效果用 register_object_effects，
#移除用 remove_from_board + set_player_data("is_out", true)——都由调用方组合。
#
#controller_id：由谁控制。
#  >= 0  分身棋子：不单独行动、不占顺位、不单独计胜负/淘汰；赢得战斗时战果与胜时点归控制者
#  -2    NPC：不属于任何玩家，同样不行动、不计胜负，但作为独立参战者比威力
#  -1    独立玩家：与普通玩家完全相同（加入顺位与胜负判定）
#shared_keys：直接指向控制者同一份数据的字段（同一个对象，不是复制）。
#  例：共享 played_cards 就是"视为激活了相同的卡牌"；共享 score/magic 就是资源共用。
#  不共享的字段（location、power 等）各自独立，所以两处的威力、地利分别计算。
#overrides：新条目上要改写的字段初值（如 player_name、power、master）。
#  原字段是数字对象而传入裸数字时包成数字对象；其余原样写入。
#新条目不登记任何效果：控制者的能力不会因为多了一个条目而触发两次
func exec(controller_id:int = -2, shared_keys:Array = [], overrides:Dictionary = {}) -> int:

	var data:Dictionary = GameData.new_player_data()
	data["is_out"] = false
	data["controller"] = controller_id
	var source = GameData.player_data_library.get(controller_id) if controller_id >= 0 else null
	if source is Dictionary:
		data["player_name"] = source.get("player_name", data["player_name"])
		for key in shared_keys:
			if (source as Dictionary).has(str(key)):
				data[str(key)] = source[str(key)]
	for key in overrides.keys():
		var value = overrides[key]
		if data.get(key) is BaseNumber and (value is int or value is float):
			value = BaseNumber.new(int(value))
		elif data.get(key) is BaseNumber and value is BaseNumber:
			#不直接挂效果自带的数字对象，避免之后改条目的数值时把卡面数字一起改掉
			value = BaseNumber.new(value.number)
		data[key] = value
	var id:int = _next_id()
	GameData.player_data_library[id] = data
	GameLog.record("player_added", controller_id, id, "", null, ["player_added"],
		{"controller": controller_id, "shared_keys": shared_keys.duplicate()})
	return id


#新 id 取现有最大 id + 1，不复用已出局玩家的 id（历史日志按 id 记，复用会串）
func _next_id() -> int:
	var next:int = 0
	for id in GameData.player_data_library.keys():
		next = maxi(next, int(id) + 1)
	return next
