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
const OTHERS_PREPARE_PHASE_START = "others_prepare_phase_start"
const OTHERS_PREPARE_PHASE = "others_prepare_phase"
const OTHERS_PREPARE_PHASE_END = "others_prepare_phase_end"

const OUTPOST_PHASE_START = "outpost_phase_start"
const OUTPOST_PHASE = "outpost_phase"
const OUTPOST_PHASE_END = "outpost_phase_end"
const SELF_OUTPOST_PHASE_START = "self_outpost_phase_start"
const SELF_OUTPOST_PHASE = "self_outpost_phase"
const SELF_OUTPOST_PHASE_END = "self_outpost_phase_end"
const OTHERS_OUTPOST_PHASE_START = "others_outpost_phase_start"
const OTHERS_OUTPOST_PHASE = "others_outpost_phase"
const OTHERS_OUTPOST_PHASE_END = "others_outpost_phase_end"

const ACTION_PHASE_START = "action_phase_start"
const ACTION_PHASE = "action_phase"
const ACTION_PHASE_END = "action_phase_end"
const SELF_ACTION_PHASE_START = "self_action_phase_start"
const SELF_ACTION_PHASE = "self_action_phase"
const SELF_ACTION_PHASE_END = "self_action_phase_end"
const OTHERS_ACTION_PHASE_START = "others_action_phase_start"
const OTHERS_ACTION_PHASE = "others_action_phase"
const OTHERS_ACTION_PHASE_END = "others_action_phase_end"

const BATTLE_PHASE_START = "battle_phase_start"
const BATTLE_PHASE = "battle_phase"
const BATTLE_PHASE_END = "battle_phase_end"
const SELF_BATTLE_PHASE_START = "self_battle_phase_start"
const SELF_BATTLE_PHASE = "self_battle_phase"
const SELF_BATTLE_PHASE_END = "self_battle_phase_end"
const OTHERS_BATTLE_PHASE_START = "others_battle_phase_start"
const OTHERS_BATTLE_PHASE = "others_battle_phase"
const OTHERS_BATTLE_PHASE_END = "others_battle_phase_end"

const PHASE_START = "phase_start"
const PHASE = "phase"
const PHASE_END = "phase_end"
const SELF_PHASE_START = "self_phase_start"
const SELF_PHASE = "self_phase"
const SELF_PHASE_END = "self_phase_end"
const OTHERS_PHASE_START = "others_phase_start"
const OTHERS_PHASE = "others_phase"
const OTHERS_PHASE_END = "others_phase_end"

const DAY_START = "day_start"
const DAY = "day"
const DAY_END = "day_end"

const PLAYED_CRAD = "played_card"
const SELF_PLAYED_CRAD = "self_played_card"
const OTHERS_PLAYED_CRAD = "others_played_card"

const MAGIC_ADD = "magic_add"
const MAGIC_DECREASE = "magic_decrease"
const SELF_MAGIC_ADD = "self_magic_add"
const SELF_MAGIC_DECREASE = "self_magic_decrease"
const OTHERS_MAGIC_ADD = "others_magic_add"
const OTHERS_MAGIC_DECREASE = "others_magic_decrease"

const SCORE_ADD = "score_add"
const SCORE_DECREASE = "score_decrease"
const SELF_SCORE_ADD = "self_score_add"
const SELF_SCORE_DECREASE = "self_score_decrease"
const OTHERS_SCORE_ADD = "others_score_add"
const OTHERS_SCORE_DECREASE = "others_score_decrease"

const BATTLE_WIN = "battle_win"
const BATTLE = "battle"
const BATTLE_LOSE = "battle_lose"
const SELF_BATTLE_WIN = "self_battle_win"
const SELF_BATTLE = "self_battle"
const SELF_BATTLE_LOSE = "self_battle_lose"
const OTHERS_BATTLE_WIN = "others_battle_win"
const OTHERS_BATTLE = "others_battle"
const OTHERS_BATTLE_LOSE = "others_battle_lose"

const DEPLOY_START = "deploy_start"
const DEPLOY = "deploy"
const DEPLOY_END = "deploy_end"
const SELF_DEPLOY_START = "self_deploy_start"
const SELF_DEPLOY = "self_deploy"
const SELF_DEPLOY_END = "self_deploy_end"
const OTHERS_DEPLOY_START = "others_deploy_start"
const OTHERS_DEPLOY = "others_deploy"
const OTHERS_DEPLOY_END = "others_deploy_end"

const MOVE_START = "move_start"
const MOVE = "move"
const MOVE_END = "move_end"
const SELF_MOVE_START = "self_move_start"
const SELF_MOVE = "self_move"
const SELF_MOVE_END = "self_move_end"
const OTHERS_MOVE_START = "others_move_start"
const OTHERS_MOVE = "others_move"
const OTHERS_MOVE_END = "others_move_end"

const EFFECT_START = "effect_start"
const EFFECT_END = "effect_end"
const SELF_EFFECT_START = "self_effect_start"
const SELF_EFFECT_END = "self_effect_end"
const OTHERS_EFFECT_START = "others_effect_start"
const OTHERS_EFFECT_END = "others_effect_end"

const BUFF_START = "buff_start"
const BUFF = "buff"
const BUFF_END = "buff_end"
const SELF_BUFF_START = "self_buff_start"
const SELF_BUFF = "self_buff"
const SELF_BUFF_END = "self_buff_end"
const OTHERS_BUFF_START = "others_buff_start"
const OTHERS_BUFF = "others_buff"
const OTHERS_BUFF_END = "others_buff_end"


var global_signals:Dictionary
var current_time_points:Array

func time_point(time_point:String):
	for sig:Signal in global_signals[time_point]:
		emit_signal(sig.get_name())
	
