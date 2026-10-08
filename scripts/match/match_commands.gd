class_name MatchCommands
extends RefCounted

## 本地指令入口。只组合已有引擎操作，不复制合法性规则；查询仍由调用方读取。
func submit_group(player_id: int, cards: Array, hidden: Array) -> bool:
	return RegularPlay.submit_group(player_id, cards, hidden)

func request_manual_activation(effect: BaseEffect, player_id: int) -> bool:
	return EffectManager.request_manual_activation(effect, player_id)

func set_card_concealed(card: BaseCard, concealed: bool, player_id: int) -> void:
	SetCardConcealed.new().exec(card, concealed, player_id)

func deploy(location: BaseLocation, player_id: int) -> bool:
	var before = GameDataManager.get_player_data(player_id).get("location")
	Deploy.new().exec(location, player_id)
	if GameDataManager.get_player_data(player_id).get("location") == before:
		return false
	DeployRules.apply_benefit(location, player_id)
	return true

func move(step: int, player_id: int) -> void:
	Move.new().exec(BaseNumber.new(step), player_id)

func deploy_to_area(area: BaseMapArea, player_id: int) -> bool:
	return DeployRules.deploy_to_area(area, player_id) != null

func submit_option_choice(effect: BaseEffect, selection, quantities: Dictionary = {}) -> bool:
	if effect != null:
		for index in quantities:
			effect.set_option_quantity(int(index), int(quantities[index]))
	return EffectManager.submit_option_choice(effect, selection)

func submit_active_choice(effect: BaseEffect, activate: bool) -> bool:
	return EffectManager.submit_active_choice(effect, activate)

func cancel_pending_choice(effect: BaseEffect) -> bool:
	return EffectManager.cancel_pending_choice(effect)

func submit_card_selection(effect: BaseEffect, cards: Array) -> bool:
	return EffectManager.submit_card_selection(effect, cards)

func submit_player_selection(effect: BaseEffect, players: Array) -> bool:
	return EffectManager.submit_player_selection(effect, players)

func submit_location_selection(effect: BaseEffect, location: BaseLocation) -> bool:
	return EffectManager.submit_location_selection(effect, location)

func confirm_battle_broadcast(player_id: int) -> void:
	GameProgress.confirm_battle_broadcast(player_id)

func end_current_player_action() -> bool:
	return GameProgress.end_current_player_action()
