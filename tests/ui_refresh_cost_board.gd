extends "res://tests/takeoff_refresh_board.gd"

var playable_queries := 0
var confirm_queries := 0

func _held_card_playable(card) -> bool:
	playable_queries += 1
	return super._held_card_playable(card)

func _can_confirm_held_cards() -> bool:
	confirm_queries += 1
	return super._can_confirm_held_cards()
