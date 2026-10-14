extends "res://tests/takeoff_refresh_board.gd"

var playable_queries := 0
var confirm_queries := 0

func _held_card_playable(card, _actions = null, group = null) -> bool:
	playable_queries += 1
	return super._held_card_playable(card, _actions, group)

func _can_confirm_held_cards() -> bool:
	confirm_queries += 1
	return super._can_confirm_held_cards()
