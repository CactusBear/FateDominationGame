class_name PlayRules
extends RefCounted

#卡面声明的"能不能打出"，PlayAttack / PlaySkill 共用同一套判断。
#条件类型与说明文案都由卡自己的数据给出：新增一种条件只要在这里加一个分支，
#出牌入口与卡的数据结构都不用动。未识别的条件类型一律放行——
#缺声明不给行为，免得以后新增字段悄悄拦住老卡。
#不引用任何 autoload：玩家的数据由调用方传进来，保持纯函数好复用


static func can_play(card, player_data:Dictionary) -> bool:
	if card == null:
		return false
	#"需追加打出"的牌只能靠 add_attack / add_skill 进场，常规出牌一律拒绝
	if card.get("_need_extra_play") == true:
		return false
	var reqs = card.get("_play_requirements")
	if !(reqs is Array) or (reqs as Array).is_empty():
		return true
	if player_data == null or player_data.is_empty():
		return false
	for req in reqs:
		if req is Dictionary and !_meets(req, player_data):
			return false
	return true


#本回合已经常规打出了几张某类牌（card_type 传 "attack"/"skill"）。
#出牌入口与界面提示共用这一个口径——两处各写一份 filter 的话，
#改条件时漏掉一处就会出现"界面显示能点、引擎却拒绝"这种不一致
static func played_count(player_id:int, card_type:String) -> int:
	return GameLog.query({"type": "play", "actor": player_id,
		"data": {"card_type": card_type, "extra": false}}, 0).size()


static func _meets(req:Dictionary, player_data:Dictionary) -> bool:
	match str(req.get("type", "")):
		"min_magic":
			var magic = player_data.get("magic")
			return magic is BaseNumber and magic.number >= int(req.get("value", 0))
		_:
			return true
