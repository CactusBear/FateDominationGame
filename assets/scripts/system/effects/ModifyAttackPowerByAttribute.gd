class_name ModifyAttackPowerByAttribute
extends RefCounted

func exec(required_attributes:Array, power_delta:BaseNumber = BaseNumber.new(0), player_id:int = -1, attack:BaseAttack = null):

	if attack != null:
		_try_modify(attack, required_attributes, power_delta)
		return
	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	for card in player_data["played_cards"]:
		if card is BaseAttack:
			_try_modify(card, required_attributes, power_delta, id)


func _try_modify(attack:BaseAttack, required_attributes:Array, power_delta:BaseNumber, player_id:int = -1):
	if !_match(attack, required_attributes):
		return
	attack.edit_power(power_delta)
	#卡已经打出过的话，玩家当前的力量总和也要跟着变
	if player_id != -1 and attack._is_activating:
		var player_data:Dictionary = GameDataManager.get_player_data(player_id)
		var pl_power = player_data["power"] as BaseNumber
		pl_power.add(power_delta)


func _match(attack:BaseAttack, required_attributes:Array) -> bool:
	if required_attributes.is_empty():
		return true
	for attr in required_attributes:
		if attack._attributes.has(attr):
			return true
	return false