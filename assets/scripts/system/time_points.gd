extends Node
class_name TimePoints


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

const PLAYED_CARD = "played_card"
const SELF_PLAYED_CARD = "self_played_card"
const OTHERS_PLAYED_CARD = "others_played_card"

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

const LIVES_ADD = "lives_add"
const LIVES_DECREASE = "lives_decrease"
const SELF_LIVES_ADD = "self_lives_add"
const SELF_LIVES_DECREASE = "self_lives_decrease"
const OTHERS_LIVES_ADD = "others_lives_add"
const OTHERS_LIVES_DECREASE = "others_lives_decrease"

const LAST_LIFE = "last_life"
const SELF_LAST_LIFE = "self_last_life"
const OTHERS_LAST_LIFE = "others_last_life"

const ELIMINATED = "eliminated"
const SELF_ELIMINATED = "self_eliminated"
const OTHERS_ELIMINATED = "others_eliminated"

const BATTLE_WIN = "battle_win"
const BATTLE = "battle"
const BATTLE_LOSE = "battle_lose"
const SELF_BATTLE_WIN = "self_battle_win"
const SELF_BATTLE = "self_battle"
const SELF_BATTLE_LOSE = "self_battle_lose"
const OTHERS_BATTLE_WIN = "others_battle_win"
const OTHERS_BATTLE = "others_battle"
const OTHERS_BATTLE_LOSE = "others_battle_lose"
const BATTLE_RESOLVE = "battle_resolve"

const CLIMAX_START = "climax_start"
const CLIMAX = "climax"
const CLIMAX_END = "climax_end"
const SELF_CLIMAX_START = "self_climax_start"
const SELF_CLIMAX = "self_climax"
const SELF_CLIMAX_END = "self_climax_end"
const OTHERS_CLIMAX_START = "others_climax_start"
const OTHERS_CLIMAX = "others_climax"
const OTHERS_CLIMAX_END = "others_climax_end"

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

const TRUE_NAME_RELEASE = "true_name_release"
const SELF_TRUE_NAME_RELEASE = "self_true_name_release"
const OTHERS_TRUE_NAME_RELEASE = "others_true_name_release"

const TRUE_NAME_HIDDEN = "true_name_hidden"
const SELF_TRUE_NAME_HIDDEN = "self_true_name_hidden"
const OTHERS_TRUE_NAME_HIDDEN = "others_true_name_hidden"

const CARD_CLOSED = "card_closed"
const SELF_CARD_CLOSED = "self_card_closed"
const OTHERS_CARD_CLOSED = "others_card_closed"

const COMMAND_SPELL_USED = "command_spell_used"
const SELF_COMMAND_SPELL_USED = "self_command_spell_used"
const OTHERS_COMMAND_SPELL_USED = "others_command_spell_used"

const LOCATION_BENEFIT_CHANGED = "location_benefit_changed"
const SELF_LOCATION_BENEFIT_CHANGED = "self_location_benefit_changed"
const OTHERS_LOCATION_BENEFIT_CHANGED = "others_location_benefit_changed"

const CARD_COST_CALCULATED = "card_cost_calculated"
const SELF_CARD_COST_CALCULATED = "self_card_cost_calculated"
const OTHERS_CARD_COST_CALCULATED = "others_card_cost_calculated"

const ROUND_START_RESET = "round_start_reset"



#dic
const shown_time_points:Dictionary = {
	GAME_START : "游戏开始时",
	GAME : "游戏进行时",
	GAME_END : "游戏结束时",
	PREPARE_PHASE_START : "准备阶段开始时",
	PREPARE_PHASE : "准备阶段中",
	PREPARE_PHASE_END : "准备阶段结束时",
	SELF_PREPARE_PHASE_START : "自己准备阶段开始时",
	SELF_PREPARE_PHASE : "自己准备阶段中",
	SELF_PREPARE_PHASE_END : "自己准备阶段结束时",
	OTHERS_PREPARE_PHASE_START : "他人准备阶段开始时",
	OTHERS_PREPARE_PHASE : "他人准备阶段中",
	OTHERS_PREPARE_PHASE_END : "他人准备阶段结束时",
	OUTPOST_PHASE_START : "前哨阶段开始时",
	OUTPOST_PHASE : "前哨阶段中",
	OUTPOST_PHASE_END : "前哨阶段结束时",
	SELF_OUTPOST_PHASE_START : "自己前哨阶段开始时",
	SELF_OUTPOST_PHASE : "自己前哨阶段中",
	SELF_OUTPOST_PHASE_END : "自己前哨阶段结束时",
	OTHERS_OUTPOST_PHASE_START : "他人前哨阶段开始时",
	OTHERS_OUTPOST_PHASE : "他人前哨阶段中",
	OTHERS_OUTPOST_PHASE_END : "他人前哨阶段结束时",
	ACTION_PHASE_START : "行动阶段开始时",
	ACTION_PHASE : "行动阶段中",
	ACTION_PHASE_END : "行动阶段结束时",
	SELF_ACTION_PHASE_START : "自己行动阶段开始时",
	SELF_ACTION_PHASE : "自己行动阶段中",
	SELF_ACTION_PHASE_END : "自己行动阶段结束时",
	OTHERS_ACTION_PHASE_START : "他人行动阶段开始时",
	OTHERS_ACTION_PHASE : "他人行动阶段中",
	OTHERS_ACTION_PHASE_END : "他人行动阶段结束时",
	BATTLE_PHASE_START: "战斗阶段开始时",
	BATTLE_PHASE : "战斗阶段中",
	BATTLE_PHASE_END : "战斗阶段结束",
	SELF_BATTLE_PHASE_START : "自己战斗阶段开始时",
	SELF_BATTLE_PHASE : "自己战斗阶段中",
	SELF_BATTLE_PHASE_END : "自己战斗阶段结束",
	OTHERS_BATTLE_PHASE_START : "他人战斗阶段开始时",
	OTHERS_BATTLE_PHASE : "他人战斗阶段中",
	OTHERS_BATTLE_PHASE_END : "他人战斗阶段结束",
	PHASE_START : "阶段开始时",
	PHASE : "阶段中",
	PHASE_END : "阶段结束时",
	SELF_PHASE_START : "自己阶段开始时",
	SELF_PHASE : "自己阶段中",
	SELF_PHASE_END : "自己阶段结束时",
	OTHERS_PHASE_START : "他人阶段开始时",
	OTHERS_PHASE : "他人阶段中",
	OTHERS_PHASE_END : "他人阶段结束时",
	DAY_START : "一天开始时",
	DAY : "一天中",
	DAY_END : "一天结束时",
	PLAYED_CARD : "打出卡牌时",
	SELF_PLAYED_CARD : "自己打出卡牌时",
	OTHERS_PLAYED_CARD : "他人打出卡牌时",
	MAGIC_ADD : "魔力增加时",
	MAGIC_DECREASE : "魔力减少时",
	SELF_MAGIC_ADD : "自己魔力增加时",
	SELF_MAGIC_DECREASE : "自己魔力减少时",
	OTHERS_MAGIC_ADD : "他人魔力增加时",
	OTHERS_MAGIC_DECREASE : "他人魔力减少时",
	SCORE_ADD : "战果增加时",
	SCORE_DECREASE : "战果减少时",
	SELF_SCORE_ADD : "自己战果增加时",
	SELF_SCORE_DECREASE : "自己战果减少时",
	OTHERS_SCORE_ADD : "他人战果增加时",
	OTHERS_SCORE_DECREASE : "他人战果减少时",
	LIVES_ADD : "生命增加时",
	LIVES_DECREASE : "生命减少时",
	SELF_LIVES_ADD : "自己生命增加时",
	SELF_LIVES_DECREASE : "自己生命减少时",
	OTHERS_LIVES_ADD : "他人生命增加时",
	OTHERS_LIVES_DECREASE : "他人生命减少时",
	LAST_LIFE : "生命只剩最后一条时",
	SELF_LAST_LIFE : "自己生命只剩最后一条时",
	OTHERS_LAST_LIFE : "他人生命只剩最后一条时",
	ELIMINATED : "被淘汰时",
	SELF_ELIMINATED : "自己被淘汰时",
	OTHERS_ELIMINATED : "他人被淘汰时",
	BATTLE_WIN : "赢得战斗时",
	BATTLE : "交战时",
	BATTLE_LOSE : "败北时",
	SELF_BATTLE_WIN : "自己赢得战斗时",
	SELF_BATTLE : "自己交战时",
	SELF_BATTLE_LOSE : "自己败北时",
	OTHERS_BATTLE_WIN : "他人赢得战斗时",
	OTHERS_BATTLE : "他人交战时",
	OTHERS_BATTLE_LOSE : "他人败北时",
	BATTLE_RESOLVE : "战斗结算时",
	CLIMAX_START : "高潮开始时",
	CLIMAX : "高潮时",
	CLIMAX_END : "高潮结束时",
	SELF_CLIMAX_START : "自己高潮开始时",
	SELF_CLIMAX : "自己高潮时",
	SELF_CLIMAX_END : "自己高潮结束时",
	OTHERS_CLIMAX_START : "他人高潮开始时",
	OTHERS_CLIMAX : "他人高潮时",
	OTHERS_CLIMAX_END : "他人高潮结束时",
	DEPLOY_START : "开始部署时",
	DEPLOY : "部署时",
	DEPLOY_END : "结束部署时",
	SELF_DEPLOY_START : "自己开始部署时",
	SELF_DEPLOY : "自己部署时",
	SELF_DEPLOY_END : "自己结束部署时",
	OTHERS_DEPLOY_START : "他人开始部署时",
	OTHERS_DEPLOY : "他人部署时",
	OTHERS_DEPLOY_END : "他人结束部署时",
	MOVE_START : "开始移动时",
	MOVE : "移动时",
	MOVE_END : "结束移动时",
	SELF_MOVE_START : "自己开始移动时",
	SELF_MOVE : "自己移动时",
	SELF_MOVE_END : "自己结束移动时",
	OTHERS_MOVE_START : "他人开始移动时",
	OTHERS_MOVE : "他人移动时",
	OTHERS_MOVE_END : "他人结束移动时",
	EFFECT_START : "效果处理开始时",
	EFFECT_END : "效果处理结束时",
	SELF_EFFECT_START : "自己效果处理开始时",
	SELF_EFFECT_END : "自己效果处理结束时",
	OTHERS_EFFECT_START : "他人效果处理开始时",
	OTHERS_EFFECT_END : "他人效果处理结束时",
	BUFF_START : "buff开始时",
	BUFF : "buff生效中",
	BUFF_END : "buff结束中",
	SELF_BUFF_START : "自己buff开始时",
	SELF_BUFF : "自己buff生效中",
	SELF_BUFF_END : "自己buff结束中",
	OTHERS_BUFF_START : "他人buff开始时",
	OTHERS_BUFF : "他人buff生效中",
	OTHERS_BUFF_END : "他人buff结束中",
	TRUE_NAME_RELEASE : "真名解放时",
	SELF_TRUE_NAME_RELEASE : "自己真名解放时",
	OTHERS_TRUE_NAME_RELEASE : "他人真名解放时",
	TRUE_NAME_HIDDEN : "真名隐藏时",
	SELF_TRUE_NAME_HIDDEN : "自己真名隐藏时",
	OTHERS_TRUE_NAME_HIDDEN : "他人真名隐藏时",
	CARD_CLOSED : "卡牌关闭时",
	SELF_CARD_CLOSED : "自己卡牌关闭时",
	OTHERS_CARD_CLOSED : "他人卡牌关闭时",
	COMMAND_SPELL_USED : "使用令咒时",
	SELF_COMMAND_SPELL_USED : "自己使用令咒时",
	OTHERS_COMMAND_SPELL_USED : "他人使用令咒时",
	LOCATION_BENEFIT_CHANGED : "地利改变时",
	SELF_LOCATION_BENEFIT_CHANGED : "自己所在地利改变时",
	OTHERS_LOCATION_BENEFIT_CHANGED : "他人所在地利改变时",
	CARD_COST_CALCULATED : "卡牌费用计算完成时",
	SELF_CARD_COST_CALCULATED : "自己卡牌费用计算完成时",
	OTHERS_CARD_COST_CALCULATED : "他人卡牌费用计算完成时",
	ROUND_START_RESET : "回合开始重置时"
}
