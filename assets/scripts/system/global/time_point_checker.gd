extends Node


const GAME_START = "game_start"
const GAME = "game"
const GAME_END = "game_end"

const PREPARE_PHASE_START = "prepare_phase_start"
const PREPARE_PHASE = "prepare_phase"
const PREPARE_PHASE_END = "prepare_phase_end"
const SELF_PREPARE_PHASE_START = "self_prepare_phase_start"
const SELF_PREPARE_PHASE = "self_prepare_phase"
const SELF_PREPARE_PHASE_END = "self_prepare_phase_end"

const OUTPOST_PHASE_START = "outpost_phase_start"
const OUTPOST_PHASE = "outpost_phase"
const OUTPOST_PHASE_END = "outpost_phase_end"
const SELF_OUTPOST_PHASE_START = "self_outpost_phase_start"
const SELF_OUTPOST_PHASE = "self_outpost_phase"
const SELF_OUTPOST_PHASE_END = "self_outpost_phase_end"

const ACTION_PHASE_START = "action_phase_start"
const ACTION_PHASE = "action_phase"
const ACTION_PHASE_END = "action_phase_end"
const SELF_ACTION_PHASE_START = "self_action_phase_start"
const SELF_ACTION_PHASE = "self_action_phase"
const SELF_ACTION_PHASE_END = "self_action_phase_end"

const BATTLE_PHASE_START = "battle_phase_start"
const BATTLE_PHASE = "battle_phase"
const BATTLE_PHASE_END = "battle_phase_end"
const SELF_BATTLE_PHASE_START = "self_battle_phase_start"
const SELF_BATTLE_PHASE = "self_battle_phase"
const SELF_BATTLE_PHASE_END = "self_battle_phase_end"

const PHASE_START = "phase_start"
const PHASE = "phase"
const PHASE_END = "phase_end"
const SELF_PHASE_START = "self_phase_start"
const SELF_PHASE = "self_phase"
const SELF_PHASE_END = "self_phase_end"

const DAY_START = "day_start"
const DAY = "day"
const DAY_END = "day_end"

const PLAYED_CRAD = "played_card"
const SELF_PLAYED_CRAD = "self_played_card"

const MAGIC_ADD = "magic_add"
const MAGIC_DECREASE = "magic_decrease"
const SELF_MAGIC_ADD = "self_magic_add"
const SELF_MAGIC_DECREASE = "self_magic_decrease"

const SCORE_ADD = "score_add"
const SCORE_DECREASE = "score_decrease"
const SELF_SCORE_ADD = "self_score_add"
const SELF_SCORE_DECREASE = "self_score_decrease"

const BATTLE_WIN = "battle_win"
const BATTLE = "battle"
const BATTLE_LOSE = "battle_lose"
const SELF_BATTLE_WIN = "self_battle_win"
const SELF_BATTLE = "self_battle"
const SELF_BATTLE_LOSE = "self_battle_lose"


var global_signals:Dictionary
var current_time_points:Array

func time_point(time_point:String):
	for sig:Signal in global_signals[time_point]:
		emit_signal(sig.get_name())
	
