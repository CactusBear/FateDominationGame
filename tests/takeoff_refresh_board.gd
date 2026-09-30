extends "res://assets/scripts/game_scene/battle_board_v2.gd"

var refresh_calls := 0

func refresh_all_ui() -> void:
	refresh_calls += 1
	super.refresh_all_ui()

# 测试只驱动动画与界面，隔离 AI 和效果推进对牌区数据的改动。
func _check_and_step_ai(_delta: float) -> void:
	pass

func _process_waiting_inputs(_delta: float) -> void:
	pass
