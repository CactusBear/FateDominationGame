class_name DebugCardAdapter
extends RefCounted

func inspect_card(instance_id:int) -> Dictionary:
	var card = find_card(instance_id)
	if card == null:
		return _fail("卡牌实例不存在")
	var owner := find_card_owner(card)
	return {"ok":true, "changed":false, "object_id":instance_id, "value":{
		"name":card._name,
		"shown_name":card.get_shown_name(),
		"class":card.get_class(),
		"owner":owner.get("player_id", null),
		"zone":owner.get("path", ""),
		"concealed":bool(card.get("_is_concealed")) if "_is_concealed" in card else false,
		"template":is_template(card)
	}}


func find_card(instance_id:int):
	for object in GameData.objects:
		if object is BaseCard and object.get_instance_id() == instance_id:
			return object
	return null


func find_card_owner(card) -> Dictionary:
	for raw_id in GameData.player_data_library.keys():
		var player_id:int = int(raw_id)
		for path in DebugValidate.player_zones(player_id):
			var zone:Array = DebugValidate.player_zones(player_id)[path]
			if zone.has(card):
				return {"player_id":player_id, "path":path, "array":zone}
	return {}


func move_card(instance_id:int, to_path:String, to_player = null, to_index = -1) -> Dictionary:
	var card = find_card(instance_id)
	if card == null:
		return _fail("卡牌实例不存在")
	if is_template(card):
		return _fail("模板卡只读，不能搬运")
	var owner := find_card_owner(card)
	if owner.is_empty():
		return _fail("找不到卡牌来源区")
	var player_id:int = int(owner.player_id) if to_player == null else int(to_player)
	var target = zone_by_path(player_id, to_path)
	if !(target is Array):
		return _fail("目标牌区不存在")
	var index:int = int(to_index)
	if index < -1 or index > target.size():
		return _fail("目标下标越界")
	var source_path:String = str(owner.path)
	var source_player_id:int = int(owner.player_id)
	var source_index:int = (owner.array as Array).find(card)
	var was_registered:bool = _is_registered_for(card, source_player_id)
	var should_register:bool = _zone_registers_effects(to_path)
	# 跨玩家搬运必须先解除旧归属；即使目标区同样登记效果，也不能直接改 trigger id
	# 而把旧玩家 self_effects 里的反查引用留着。
	if was_registered and (source_player_id != player_id or !should_register):
		UnregisterObjectEffects.new().exec(card)
	DrawCardByCard.new().exec(card, owner.array, target, index)
	if card is BaseHandCard:
		(card as BaseHandCard).set_if_activating(to_path == "played_cards")
	if should_register and (!was_registered or source_player_id != player_id):
		RegisterObjectEffects.new().exec(card, player_id)
	if source_path == "played_cards":
		SyncPower.new().exec(source_player_id)
	if to_path == "played_cards" and source_path != "played_cards":
		SyncPower.new().exec(player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":instance_id,
		"before":{"player_id":source_player_id, "path":source_path, "index":source_index},
		"value":{"player_id":player_id, "path":to_path}}


##可整体交换的牌区。名单只有这一份：控制台的操作校验与下拉候选都读它，
##两处各写一份会在改动时漏掉一边，出现"界面能选、引擎拒绝"或反之
const SWAP_ZONE_PATHS:Array = ["deck", "hand_cards", "discard"]


## 仅交换容器内容，不调用带激活/抽牌副作用的 move_card 或 draw。
func swap_zones(player_id:int, other_player_id:int, from_zone:String, to_zone:String) -> Dictionary:
	if !SWAP_ZONE_PATHS.has(from_zone) or !SWAP_ZONE_PATHS.has(to_zone):
		return _fail("交换只支持牌库、手牌与弃牌堆")
	var source = zone_by_path(player_id, from_zone)
	var target = zone_by_path(other_player_id, to_zone)
	if !(source is Array) or !(target is Array):
		return _fail("玩家或牌区不存在")
	if is_same(source, target):
		return _fail("不能交换同一个牌区")
	var first:Array = source.duplicate()
	var second:Array = target.duplicate()
	var seen:Array = []
	# 两边全部验证完成才摘牌，拒绝模板、重复引用或非卡对象。
	for object in first + second:
		if !(object is BaseCard) or is_template(object) or seen.has(object):
			return _fail("牌区含模板、重复实例或非卡对象")
		seen.append(object)
	for object in first:
		_exchange_card(object, source, target, player_id, other_player_id)
	for object in second:
		_exchange_card(object, target, source, other_player_id, player_id)
	return {"ok":true, "changed":!seen.is_empty(), "player_id":player_id,
		"value":{"other_player":other_player_id, "from_zone":from_zone, "to_zone":to_zone,
			"from_count":second.size(), "to_count":first.size()}}


func _exchange_card(object:BaseCard, source:Array, target:Array, old_owner:int, new_owner:int) -> void:
	var rebind:bool = old_owner != new_owner and _is_registered_for(object, old_owner)
	if rebind:
		UnregisterObjectEffects.new().exec(object)
	DrawCardByCard.new().exec(object, source, target)
	if rebind:
		RegisterObjectEffects.new().exec(object, new_owner)


func add_clone(player_id:int, source_name:String, to_path:String) -> Dictionary:
	var template = find_card_template(source_name)
	if template == null:
		return _fail("找不到卡牌模板")
	var target = zone_by_path(player_id, to_path)
	if !(target is Array):
		return _fail("目标牌区不存在")
	var card = CloneObject.new().exec(template)
	if !(card is BaseCard):
		return _fail("模板克隆失败")
	target.append(card)
	if card is BaseHandCard:
		(card as BaseHandCard).set_if_activating(to_path == "played_cards")
	if _zone_registers_effects(to_path):
		RegisterObjectEffects.new().exec(card, player_id)
	if to_path == "played_cards":
		SyncPower.new().exec(player_id)
	return {"ok":true, "changed":true, "player_id":player_id, "object_id":card.get_instance_id(), "value":to_path}


func draw(player_id:int) -> Dictionary:
	var d:Dictionary = GameData.player_data_library.get(player_id, {})
	if d.is_empty():
		return _fail("玩家不存在")
	var before:int = d.get("hand_cards", []).size()
	if d.get("deck", []).is_empty():
		ReshuffleDiscard.new().exec(player_id)
	DrawCardFromPlDeckToHand.new().exec(0, player_id)
	return {"ok":true, "changed":d.hand_cards.size() != before, "player_id":player_id, "value":d.hand_cards.size()}


func refill(player_id:int) -> Dictionary:
	var d:Dictionary = GameData.player_data_library.get(player_id, {})
	if d.is_empty():
		return _fail("玩家不存在")
	var before:int = d.hand_cards.size()
	RefillHand.new().exec(player_id, GameData.hand_limit)
	return {"ok":true, "changed":d.hand_cards.size() != before, "player_id":player_id, "value":d.hand_cards.size()}


func shuffle(player_id:int, path:String) -> Dictionary:
	var zone = zone_by_path(player_id, path)
	if !(zone is Array):
		return _fail("牌区不存在")
	ShuffleArray.new().exec(zone)
	return {"ok":true, "changed":zone.size() > 1, "player_id":player_id, "value":zone.size()}


func edit_cost(instance_id:int, set_value, vary_value) -> Dictionary:
	var card = find_card(instance_id)
	if !(card is BaseHandCard) or is_template(card):
		return _fail("目标不是可编辑的实战手牌")
	var before = card._cost.number
	EditCardCost.new().exec(
		BaseNumber.new(float(vary_value)) if vary_value != null else BaseNumber.new(0),
		BaseNumber.new(float(set_value)) if set_value != null else null,
		card)
	return _edit_result(card, before, card._cost.number)


func edit_power(instance_id:int, set_value, vary_value) -> Dictionary:
	var card = find_card(instance_id)
	if !(card is BaseHandCard) or is_template(card):
		return _fail("目标不是可编辑的实战手牌")
	var before = card._power.number
	var owner := find_card_owner(card)
	var id:int = int(owner.get("player_id", -2))
	if id == -2:
		return _fail("找不到卡牌所属玩家")
	EditCardPower.new().exec(card,
		BaseNumber.new(float(vary_value)) if vary_value != null else BaseNumber.new(0),
		BaseNumber.new(float(set_value)) if set_value != null else null, id)
	return _edit_result(card, before, card._power.number, id)


func edit_attributes(instance_id:int, add:Array, remove:Array, set_values = null) -> Dictionary:
	var card = find_card(instance_id)
	if card == null or is_template(card):
		return _fail("目标卡不存在或是模板")
	var before:Array = card._attributes.duplicate()
	EditCardAttributes.new().exec(add, remove, set_values if set_values is Array else [""], card)
	return {"ok":true, "changed":before != card._attributes, "object_id":instance_id, "before":before, "value":card._attributes.duplicate()}


func conceal(instance_id:int, concealed:bool) -> Dictionary:
	var card = find_card(instance_id)
	if card == null or is_template(card):
		return _fail("目标卡不存在或是模板")
	var before:bool = bool(card.get("_is_concealed"))
	SetCardConcealed.new().exec(card, concealed)
	return {"ok":true, "changed":before != bool(card.get("_is_concealed")), "object_id":instance_id,
		"before":before, "value":bool(card.get("_is_concealed"))}


func close(instance_id:int) -> Dictionary:
	var card = find_card(instance_id)
	if !(card is BaseHandCard) or is_template(card):
		return _fail("目标不是可关闭的实战牌")
	var owner := find_card_owner(card)
	if str(owner.get("path", "")) != "played_cards":
		return _fail("CloseCard 只接受已打出牌")
	CloseCard.new().exec(card, int(owner.player_id))
	return {"ok":true, "changed":true, "player_id":int(owner.player_id), "object_id":instance_id}


func zone_by_path(player_id:int, path:String):
	if !GameData.player_data_library.has(player_id):
		return null
	var current = GameData.player_data_library[player_id]
	for part in path.split("."):
		if !(current is Dictionary) or !current.has(part):
			return null
		current = current[part]
	return current if current is Array else null


func _zone_registers_effects(path:String) -> bool:
	# 开局发到牌堆、技能区的克隆体本来就全部登记；移出游戏后才停用，
	# 令咒是唯一明确仍在游戏外发动的卡牌区。
	return !path.begins_with("out_of_game.") or path == "out_of_game.command_spell"


func _is_registered_for(card:BaseCard, player_id:int) -> bool:
	if !GameData.player_data_library.has(player_id):
		return false
	var registered:Array = GameData.player_data_library[player_id].get("self_effects", [])
	for effect in card._effects:
		if registered.has(effect):
			return true
	return false


func find_card_template(source_name:String):
	var pools:Array = []
	pools.append_array(LoadEvent.events)
	pools.append_array(LoadSituation.situations)
	pools.append_array(LoadSituation.climax_situations.values())
	pools.append_array(LoadCommandSpell.command_spells.values())
	for holder in GameData.loaded_masters + GameData.loaded_servants:
		if holder == null:
			continue
		for value in holder._specials.values():
			if value is Array:
				pools.append_array(value)
		if "_other_things" in holder:
			pools.append_array(holder._other_things)
		if "_upgrade_skill" in holder:
			pools.append_array(holder._upgrade_skill)
	for object in pools:
		if object is BaseCard and object._name == source_name:
			return object
	return null


func is_template(card) -> bool:
	if LoadEvent.events.has(card) or LoadSituation.situations.has(card) or LoadSituation.climax_situations.values().has(card) or LoadCommandSpell.command_spells.values().has(card):
		return true
	for holder in GameData.loaded_masters + GameData.loaded_servants:
		if holder == null:
			continue
		for value in holder._specials.values():
			if value is Array and value.has(card):
				return true
		if "_other_things" in holder and holder._other_things.has(card):
			return true
		if "_upgrade_skill" in holder and holder._upgrade_skill.has(card):
			return true
	return false


func _edit_result(card, before, after, player_id = null) -> Dictionary:
	var result := {"ok":true, "changed":before != after, "object_id":card.get_instance_id(), "before":before, "value":after}
	if player_id != null:
		result["player_id"] = player_id
	return result


func _fail(reason:String) -> Dictionary:
	return {"ok":false, "changed":false, "error":reason}
