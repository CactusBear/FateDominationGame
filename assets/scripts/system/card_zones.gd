class_name CardZones
extends RefCounted

#牌区定位与牌区变化时点。搬运原语（draw_card_by_card 等）只知道两个数组，
#这里负责回答"这个数组是哪名玩家的哪个区"，再按目标区/来源区派发对应时点。
#区路径由 player_data 的容器键拼成（side/skills、out_of_game/attacks、extra_zones/<名字>），不写死玩家数量；
#"哪个区对应哪个时点"是引擎对牌区词汇的约定，放在下面两张表里，新增区只改表


#进入某区时派发的时点：键是区路径的首段或完整路径（完整路径优先匹配）
const ENTER_POINTS := {
	"hand_cards": TimePoints.CARD_TO_HAND,
	"discard": TimePoints.CARD_TO_DISCARD,
	"deck": TimePoints.CARD_TO_DECK,
	"servant_skills": TimePoints.CARD_TO_SKILL_ZONE,
	"master_skills": TimePoints.CARD_TO_SKILL_ZONE,
	"side/skills": TimePoints.CARD_TO_SKILL_ZONE,
	"out_of_game": TimePoints.CARD_REMOVED,
}
#离开某区时派发的时点
const LEAVE_POINTS := {
	"deck": TimePoints.CARD_LEAVE_DECK,
}
#进入这些区之前先派发"即将发生"的时点，效果可以取消这次搬运
const BEFORE_ENTER_POINTS := {
	"out_of_game": TimePoints.BEFORE_CARD_REMOVE,
}


#找出数组属于哪名玩家的哪个区：{player_id, zone}；不属于任何玩家时 player_id 为 -1、zone 为空串
static func locate(arr) -> Dictionary:
	if !(arr is Array):
		return {"player_id": -1, "zone": ""}
	for id in GameData.player_data_library.keys():
		var found := _find(GameData.player_data_library[id], arr, "")
		if found != "":
			return {"player_id": int(id), "zone": found}
	return {"player_id": -1, "zone": ""}


static func _find(value, target:Array, path:String) -> String:
	if value is Array:
		return path if is_same(value, target) else ""
	if value is Dictionary:
		for key in value.keys():
			var sub:String = str(key) if path == "" else path + "/" + str(key)
			var got := _find(value[key], target, sub)
			if got != "":
				return got
	return ""


static func _point_of(table:Dictionary, zone:String) -> String:
	if zone == "":
		return ""
	if table.has(zone):
		return str(table[zone])
	var head:String = zone.split("/")[0]
	return str(table.get(head, ""))


#这张牌此刻在哪名玩家的牌区里；不在任何玩家牌区时返回 -1
static func owner_of(card) -> int:
	if card == null:
		return -1
	for id in GameData.player_data_library.keys():
		if _contains(GameData.player_data_library[id], card):
			return int(id)
	return -1


static func _contains(value, card) -> bool:
	if value is Array:
		return (value as Array).has(card)
	if value is Dictionary:
		for key in value.keys():
			if _contains(value[key], card):
				return true
	return false


#搬运前询问：返回 false 表示这次搬运被效果取消
static func allow_move(card, from:Array, to:Array) -> bool:
	var target := locate(to)
	var point := _point_of(BEFORE_ENTER_POINTS, target.zone)
	if point == "":
		return true
	var owner:int = int(target.player_id)
	var action:Dictionary = EffectManager.begin_pending_action(point, owner,
		{"card": card, "from_zone": locate(from).zone, "to_zone": target.zone}, card)
	return !bool(action.get("cancelled", false))


#搬运完成后派发牌区变化时点。当事人取牌所在区的玩家；两个区都不属于玩家时不派发
static func notify_moved(card, from_info:Dictionary, to_info:Dictionary) -> void:
	var leave := _point_of(LEAVE_POINTS, str(from_info.get("zone", "")))
	if leave != "" and int(from_info.get("player_id", -1)) >= 0:
		TimePointChecker.dynamic_time_point([leave], int(from_info.player_id), card)
	var enter := _point_of(ENTER_POINTS, str(to_info.get("zone", "")))
	if enter != "" and int(to_info.get("player_id", -1)) >= 0:
		TimePointChecker.dynamic_time_point([enter], int(to_info.player_id), card)
