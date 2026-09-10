class_name AllOperations
extends RefCounted

#JSON里的func_name(下划线) -> 本表的键。加载时由LoadGame.func_name_to_class_name转成类名。
#分类只用于查阅，不参与运行。效果结算仍按文件名动态load。

const QUERY_PLAYER := "query_player"
const QUERY_ZONE := "query_zone"
const QUERY_CARD := "query_card"
const QUERY_MAP := "query_map"
const QUERY_EFFECT := "query_effect"
const QUERY_COLLECTION := "query_collection"
const QUERY_COMPARE := "query_compare"
const EDIT_PLAYER := "edit_player"
const EDIT_CARD := "edit_card"
const EDIT_MAP := "edit_map"
const TRANSFER := "transfer"
const ACTION := "action"
const BUFF := "buff"
const EFFECT := "effect"
const CONSTRUCT := "construct"
const CONTROL := "control"
const MATH := "math"

const CATEGORY_SHOWN := {
	QUERY_PLAYER : "查询/玩家字段",
	QUERY_ZONE : "查询/玩家区域",
	QUERY_CARD : "查询/卡牌对象",
	QUERY_MAP : "查询/地图",
	QUERY_EFFECT : "查询/效果与时点",
	QUERY_COLLECTION : "查询/集合",
	QUERY_COMPARE : "查询/判断",
	EDIT_PLAYER : "改写/玩家数值",
	EDIT_CARD : "改写/卡牌",
	EDIT_MAP : "改写/地图",
	TRANSFER : "转移/区域",
	ACTION : "行动/出牌部署移动",
	BUFF : "状态/Buff败北",
	EFFECT : "效果/登记反制时点",
	CONSTRUCT : "构造",
	CONTROL : "控制流",
	MATH : "数值运算"
}

#键为JSON func_name。value: category, class, summary
const TABLE := {
	"get_all_players_id" : { "category": QUERY_PLAYER, "class": "GetAllPlayersId", "summary": "全部玩家id" },
	"get_pl_id_using_eff" : { "category": QUERY_PLAYER, "class": "GetPlIdUsingEff", "summary": "当前效果归属玩家" },
	"get_player_name" : { "category": QUERY_PLAYER, "class": "GetPlayerName", "summary": "玩家名" },
	"get_player_master" : { "category": QUERY_PLAYER, "class": "GetPlayerMaster", "summary": "当前御主" },
	"get_player_servant" : { "category": QUERY_PLAYER, "class": "GetPlayerServant", "summary": "当前从者" },
	"get_player_lives" : { "category": QUERY_PLAYER, "class": "GetPlayerLives", "summary": "生命" },
	"get_data_number" : { "category": QUERY_PLAYER, "class": "GetDataNumber", "summary": "player_data数值或容器长度" },
	"get_player_data_value" : { "category": QUERY_PLAYER, "class": "GetPlayerDataValue", "summary": "player_data任意键原值" },
	"get_player_ids_by_data_value" : { "category": QUERY_PLAYER, "class": "GetPlayerIdsByDataValue", "summary": "按字段值找玩家" },
	"get_players_field" : { "category": QUERY_PLAYER, "class": "GetPlayersField", "summary": "收集各玩家同一字段" },
	"get_rank_by_data_number" : { "category": QUERY_PLAYER, "class": "GetRankByDataNumber", "summary": "按某数值字段排名" },
	"get_phase_order" : { "category": QUERY_PLAYER, "class": "GetPhaseOrder", "summary": "阶段顺位字段" },
	"get_current_round" : { "category": QUERY_PLAYER, "class": "GetCurrentRound", "summary": "当前回合" },
	"get_game_data_value" : { "category": QUERY_PLAYER, "class": "GetGameDataValue", "summary": "GameData任意字段" },

	"get_player_deck" : { "category": QUERY_ZONE, "class": "GetPlayerDeck", "summary": "牌库" },
	"get_player_discard" : { "category": QUERY_ZONE, "class": "GetPlayerDiscard", "summary": "弃牌堆" },
	"get_player_hand_cards" : { "category": QUERY_ZONE, "class": "GetPlayerHandCards", "summary": "手牌" },
	"get_player_played_cards" : { "category": QUERY_ZONE, "class": "GetPlayerPlayedCards", "summary": "场上已打出" },
	"get_player_master_skills" : { "category": QUERY_ZONE, "class": "GetPlayerMasterSkills", "summary": "御主技能区" },
	"get_player_servant_skills" : { "category": QUERY_ZONE, "class": "GetPlayerServantSkills", "summary": "从者技能列表" },
	"get_player_buffs" : { "category": QUERY_ZONE, "class": "GetPlayerBuffs", "summary": "玩家buff" },
	"get_player_commmand_spell" : { "category": QUERY_ZONE, "class": "GetPlayerCommmandSpell", "summary": "令咒数组" },
	"get_pl_skills_side" : { "category": QUERY_ZONE, "class": "GetPlSkillsSide", "summary": "side.skills" },
	"get_pl_buffs_side" : { "category": QUERY_ZONE, "class": "GetPlBuffsSide", "summary": "side.buffs" },
	"get_pl_deck_side" : { "category": QUERY_ZONE, "class": "GetPlDeckSide", "summary": "side.deck" },
	"get_pl_discard_side" : { "category": QUERY_ZONE, "class": "GetPlDiscardSide", "summary": "side.discard" },
	"get_pl_command_spell_side" : { "category": QUERY_ZONE, "class": "GetPlCommandSpellSide", "summary": "side.command_spell" },
	"get_pl_master_side" : { "category": QUERY_ZONE, "class": "GetPlMasterSide", "summary": "side.master" },
	"get_pl_servant_side" : { "category": QUERY_ZONE, "class": "GetPlServantSide", "summary": "side.servant" },
	"get_pl_others_side" : { "category": QUERY_ZONE, "class": "GetPlOthersSide", "summary": "side.others" },
	"get_pl_attacks_out_game" : { "category": QUERY_ZONE, "class": "GetPlAttacksOutGame", "summary": "移出游戏的攻击" },
	"get_pl_skills_out_game" : { "category": QUERY_ZONE, "class": "GetPlSkillsOutGame", "summary": "移出游戏的技能" },
	"get_pl_buffs_out_game" : { "category": QUERY_ZONE, "class": "GetPlBuffsOutGame", "summary": "移出游戏的buff" },
	"get_pl_command_spell_out_game" : { "category": QUERY_ZONE, "class": "GetPlCommandSpellOutGame", "summary": "移出游戏的令咒" },
	"get_pl_master_out_game" : { "category": QUERY_ZONE, "class": "GetPlMasterOutGame", "summary": "移出游戏的御主" },
	"get_pl_servant_out_game" : { "category": QUERY_ZONE, "class": "GetPlServantOutGame", "summary": "移出游戏的从者" },
	"get_pl_others_out_game" : { "category": QUERY_ZONE, "class": "GetPlOthersOutGame", "summary": "移出游戏的其他" },
	"find_player_array_containing" : { "category": QUERY_ZONE, "class": "FindPlayerArrayContaining", "summary": "对象所在玩家区域数组" },

	"get_card_attributes" : { "category": QUERY_CARD, "class": "GetCardAttributes", "summary": "卡牌属性" },
	"get_attack_printed_cost" : { "category": QUERY_CARD, "class": "GetAttackPrintedCost", "summary": "攻击印刷费用" },
	"get_attack_printed_power" : { "category": QUERY_CARD, "class": "GetAttackPrintedPower", "summary": "攻击印刷威力" },
	"get_skill_printed_cost" : { "category": QUERY_CARD, "class": "GetSkillPrintedCost", "summary": "技能印刷费用" },
	"get_skill_printed_power" : { "category": QUERY_CARD, "class": "GetSkillPrintedPower", "summary": "技能印刷威力" },
	"get_printed_num" : { "category": QUERY_CARD, "class": "GetPrintedNum", "summary": "对象numbers指定下标" },
	"get_printed_nums" : { "category": QUERY_CARD, "class": "GetPrintedNums", "summary": "对象全部numbers" },
	"get_eff_source_card" : { "category": QUERY_CARD, "class": "GetEffSourceCard", "summary": "当前效果所属卡" },
	"card_counts_power" : { "category": QUERY_CARD, "class": "CardCountsPower", "summary": "此牌是否计入合计威力" },
	"card_has_effect" : { "category": QUERY_CARD, "class": "CardHasEffect", "summary": "卡上是否有指定效果名" },
	"has_attribute" : { "category": QUERY_CARD, "class": "HasAttribute", "summary": "卡是否含给定属性" },
	"get_cards_by_name_fr_arr" : { "category": QUERY_CARD, "class": "GetCardsByNameFrArr", "summary": "数组中按卡名取卡" },
	"get_cards_by_attributes_fr_arr" : { "category": QUERY_CARD, "class": "GetCardsByAttributesFrArr", "summary": "数组中按属性筛卡" },
	"get_cards_by_tag_fr_arr" : { "category": QUERY_CARD, "class": "GetCardsByTagFrArr", "summary": "数组中按tag_name筛对象" },
	"get_card_by_index_fr_arr" : { "category": QUERY_CARD, "class": "GetCardByIndexFrArr", "summary": "数组按下标取卡" },
	"get_objects_by_name_fr_arr" : { "category": QUERY_CARD, "class": "GetObjectsByNameFrArr", "summary": "数组中按_name取任意对象" },
	"get_buff_by_name_fr_arr" : { "category": QUERY_CARD, "class": "GetBuffByNameFrArr", "summary": "数组中按名取buff" },
	"get_by_tag" : { "category": QUERY_CARD, "class": "GetByTag", "summary": "全局objects按整份tag字典匹配" },
	"get_extreme_by_property" : { "category": QUERY_CARD, "class": "GetExtremeByProperty", "summary": "数组中某属性最大或最小的对象" },
	"filter_by_property" : { "category": QUERY_CARD, "class": "FilterByProperty", "summary": "数组中属性等于某值的对象" },
	"get_property" : { "category": QUERY_CARD, "class": "GetProperty", "summary": "读任意对象属性" },

	"get_location" : { "category": QUERY_MAP, "class": "GetLocation", "summary": "玩家地点" },
	"get_location_magic" : { "category": QUERY_MAP, "class": "GetLocationMagic", "summary": "地点魔力" },
	"get_location_benefit" : { "category": QUERY_MAP, "class": "GetLocationBenefit", "summary": "地点地利" },
	"get_location_map_area" : { "category": QUERY_MAP, "class": "GetLocationMapArea", "summary": "地点所属区域" },
	"get_map_area_by_name" : { "category": QUERY_MAP, "class": "GetMapAreaByName", "summary": "按名取区域" },
	"get_map_area_score" : { "category": QUERY_MAP, "class": "GetMapAreaScore", "summary": "区域竞争战果" },
	"get_map_area_score_need_win" : { "category": QUERY_MAP, "class": "GetMapAreaScoreNeedWin", "summary": "区域是否需战斗获胜" },
	"get_map_area_buffs" : { "category": QUERY_MAP, "class": "GetMapAreaBuffs", "summary": "区域buff" },
	"get_move_cost" : { "category": QUERY_MAP, "class": "GetMoveCost", "summary": "区域移动费用" },
	"get_events" : { "category": QUERY_MAP, "class": "GetEvents", "summary": "区域事件" },
	"get_event_printed_score" : { "category": QUERY_MAP, "class": "GetEventPrintedScore", "summary": "事件印刷战果" },
	"get_situations" : { "category": QUERY_MAP, "class": "GetSituations", "summary": "当前局势" },
	"get_situation_printed_magic" : { "category": QUERY_MAP, "class": "GetSituationPrintedMagic", "summary": "局势印刷魔力" },
	"get_pls_in_location" : { "category": QUERY_MAP, "class": "GetPlsInLocation", "summary": "地点上的玩家列表" },
	"get_num_of_pl_in_map_area" : { "category": QUERY_MAP, "class": "GetNumOfPlInMapArea", "summary": "区域人数(读location._players)" },
	"get_players_in_same_area" : { "category": QUERY_MAP, "class": "GetPlayersInSameArea", "summary": "与某玩家同区域的玩家" },
	"get_players_in_map_area" : { "category": QUERY_MAP, "class": "GetPlayersInMapArea", "summary": "指定区域内的玩家" },

	"get_activating_eff" : { "category": QUERY_EFFECT, "class": "GetActivatingEff", "summary": "当前结算效果" },
	"get_effect_number" : { "category": QUERY_EFFECT, "class": "GetEffectNumber", "summary": "对象上某效果的数字" },
	"get_effect_using_nums" : { "category": QUERY_EFFECT, "class": "GetEffectUsingNums", "summary": "效果当前使用的数字" },
	"get_player_time_points" : { "category": QUERY_EFFECT, "class": "GetPlayerTimePoints", "summary": "玩家当前时点" },
	"player_buffs_have_effect" : { "category": QUERY_EFFECT, "class": "PlayerBuffsHaveEffect", "summary": "玩家激活buff是否含效果名" },
	"can_gain_magic" : { "category": QUERY_EFFECT, "class": "CanGainMagic", "summary": "能否从某来源获得魔力" },
	"when" : { "category": QUERY_EFFECT, "class": "When", "summary": "当前效果是否由指定时点触发" },

	"array_length" : { "category": QUERY_COLLECTION, "class": "ArrayLength", "summary": "数组或字典长度" },
	"is_in_array" : { "category": QUERY_COLLECTION, "class": "IsInArray", "summary": "元素是否在数组中" },
	"has" : { "category": QUERY_COLLECTION, "class": "Has", "summary": "数组/字典是否包含" },
	"get_dictionary_value" : { "category": QUERY_COLLECTION, "class": "GetDictionaryValue", "summary": "字典按键取值" },
	"array_difference" : { "category": QUERY_COLLECTION, "class": "ArrayDifference", "summary": "差集" },
	"merge_arrays" : { "category": QUERY_COLLECTION, "class": "MergeArrays", "summary": "合并最多四个数组" },
	"add_to_array" : { "category": QUERY_COLLECTION, "class": "AddToArray", "summary": "插入或追加元素" },
	"remove_from_array" : { "category": QUERY_COLLECTION, "class": "RemoveFromArray", "summary": "删除一个匹配元素" },

	"if_func" : { "category": QUERY_COMPARE, "class": "IfFunc", "summary": "两值是否相等" },
	"if_else_func" : { "category": QUERY_COMPARE, "class": "IfElseFunc", "summary": "按条件二选一返回值" },
	"compare_number" : { "category": QUERY_COMPARE, "class": "CompareNumber", "summary": "数值比较 -1/0/1" },
	"and_func" : { "category": QUERY_COMPARE, "class": "AndFunc", "summary": "逻辑与" },
	"or_func" : { "category": QUERY_COMPARE, "class": "OrFunc", "summary": "逻辑或" },
	"not_func" : { "category": QUERY_COMPARE, "class": "NotFunc", "summary": "逻辑非" },
	"match_func" : { "category": QUERY_COMPARE, "class": "MatchFunc", "summary": "值是否落在cases里" },
	"is_null" : { "category": QUERY_COMPARE, "class": "IsNull", "summary": "是否为null" },

	"edit_magic" : { "category": EDIT_PLAYER, "class": "EditMagic", "summary": "改魔力并派发时点" },
	"edit_score" : { "category": EDIT_PLAYER, "class": "EditScore", "summary": "改战果并派发时点" },
	"edit_lives" : { "category": EDIT_PLAYER, "class": "EditLives", "summary": "改生命" },
	"edit_power" : { "category": EDIT_PLAYER, "class": "EditPower", "summary": "改合计威力" },
	"edit_data_number" : { "category": EDIT_PLAYER, "class": "EditDataNumber", "summary": "改player_data里的BaseNumber字段" },
	"set_player_data" : { "category": EDIT_PLAYER, "class": "SetPlayerData", "summary": "覆盖player_data任意键" },
	"change_pl_order" : { "category": EDIT_PLAYER, "class": "ChangePlOrder", "summary": "轮转顺位" },
	"sync_power" : { "category": EDIT_PLAYER, "class": "SyncPower", "summary": "按场上牌重建合计威力" },
	"modify_attack_power_by_attribute" : { "category": EDIT_PLAYER, "class": "ModifyAttackPowerByAttribute", "summary": "按属性给合计威力加减" },
	"zero_attribute_power" : { "category": EDIT_PLAYER, "class": "ZeroAttributePower", "summary": "目标玩家某属性攻击威力按0计" },

	"edit_card_power" : { "category": EDIT_CARD, "class": "EditCardPower", "summary": "改卡威力并同步合计威力" },
	"edit_card_cost" : { "category": EDIT_CARD, "class": "EditCardCost", "summary": "改卡费用" },
	"edit_card_attributes" : { "category": EDIT_CARD, "class": "EditCardAttributes", "summary": "增删替换卡属性" },
	"set_card_concealed" : { "category": EDIT_CARD, "class": "SetCardConcealed", "summary": "明暗置并同步威力" },
	"close_card" : { "category": EDIT_CARD, "class": "CloseCard", "summary": "关闭已打出的牌" },
	"set_property" : { "category": EDIT_CARD, "class": "SetProperty", "summary": "写任意对象属性" },

	"edit_location_magic" : { "category": EDIT_MAP, "class": "EditLocationMagic", "summary": "改地点魔力" },
	"edit_location_benefit" : { "category": EDIT_MAP, "class": "EditLocationBenefit", "summary": "改地点地利" },
	"edit_map_area_score" : { "category": EDIT_MAP, "class": "EditMapAreaScore", "summary": "改区域战果" },
	"edit_map_area_move_cost" : { "category": EDIT_MAP, "class": "EditMapAreaMoveCost", "summary": "改区域移动费用" },
	"add_map_area_events" : { "category": EDIT_MAP, "class": "AddMapAreaEvents", "summary": "给区域加事件" },
	"add_map_area_buff" : { "category": EDIT_MAP, "class": "AddMapAreaBuff", "summary": "给区域加buff" },
	"add_situatiuons" : { "category": EDIT_MAP, "class": "AddSituatiuons", "summary": "加入局势" },
	"set_location" : { "category": EDIT_MAP, "class": "SetLocation", "summary": "设置玩家地点" },

	"draw_card_from_pl_deck_to_hand" : { "category": TRANSFER, "class": "DrawCardFromPlDeckToHand", "summary": "从牌库抽到手数" },
	"draw_card_by_card" : { "category": TRANSFER, "class": "DrawCardByCard", "summary": "指定卡在两数组间移动" },
	"draw_card_by_index" : { "category": TRANSFER, "class": "DrawCardByIndex", "summary": "按下标在两数组间移动" },
	"add_skill_to_skill_zone" : { "category": TRANSFER, "class": "AddSkillToSkillZone", "summary": "技能进技能区并登记效果" },
	"discard_played_cards" : { "category": TRANSFER, "class": "DiscardPlayedCards", "summary": "回合结束清理场上牌" },

	"play_attack" : { "category": ACTION, "class": "PlayAttack", "summary": "打出攻击" },
	"play_skill" : { "category": ACTION, "class": "PlaySkill", "summary": "打出技能" },
	"add_attack" : { "category": ACTION, "class": "AddAttack", "summary": "把攻击加入场上(不计费用上限)" },
	"add_skill" : { "category": ACTION, "class": "AddSkill", "summary": "把技能加入场上(不计常规出牌上限)" },
	"deploy" : { "category": ACTION, "class": "Deploy", "summary": "部署到地点" },
	"move" : { "category": ACTION, "class": "Move", "summary": "常规移动并扣魔力" },
	"move_location" : { "category": ACTION, "class": "MoveLocation", "summary": "只改位置并返回费用" },
	"played_cards" : { "category": ACTION, "class": "PlayedCards", "summary": "派发出牌时点" },

	"manage_buff" : { "category": BUFF, "class": "ManageBuff", "summary": "给玩家加或删buff" },
	"defeat" : { "category": BUFF, "class": "Defeat", "summary": "赋予败北" },

	"register_object_effects" : { "category": EFFECT, "class": "RegisterObjectEffects", "summary": "登记对象上的效果" },
	"unregister_object_effects" : { "category": EFFECT, "class": "UnregisterObjectEffects", "summary": "取消登记对象上的效果" },
	"counter" : { "category": EFFECT, "class": "Counter", "summary": "反制效果或其中一个func" },
	"close_time_point" : { "category": EFFECT, "class": "CloseTimePoint", "summary": "关闭时点" },
	"emit_time_point" : { "category": EFFECT, "class": "EmitTimePoint", "summary": "派发时点" },

	"create_buff" : { "category": CONSTRUCT, "class": "CreateBuff", "summary": "新建buff" },
	"create_base_number" : { "category": CONSTRUCT, "class": "CreateBaseNumber", "summary": "新建数字" },
	"create_func" : { "category": CONSTRUCT, "class": "CreateFunc", "summary": "新建BaseFunc" },
	"clone_object" : { "category": CONSTRUCT, "class": "CloneObject", "summary": "复制对象，不放进区域" },
	"location" : { "category": CONSTRUCT, "class": "Location", "summary": "新建地点" },
	"tag" : { "category": CONSTRUCT, "class": "Tag", "summary": "新建tag字典" },
	"shuffle_array" : { "category": QUERY_COLLECTION, "class": "ShuffleArray", "summary": "就地洗乱数组" },

	"for_func" : { "category": CONTROL, "class": "ForFunc", "summary": "按次数执行" },
	"foreach_func" : { "category": CONTROL, "class": "ForeachFunc", "summary": "遍历数组执行" },
	"while_func" : { "category": CONTROL, "class": "WhileFunc", "summary": "条件循环" },
	"do_nothing" : { "category": CONTROL, "class": "DoNothing", "summary": "空操作" },

	"edit_num_and_return" : { "category": MATH, "class": "EditNumAndReturn", "summary": "就地加减乘并返回原对象" },
	"calculate_number" : { "category": MATH, "class": "CalculateNumber", "summary": "运算后返回新数字，不改原值" },
	"random_int" : { "category": MATH, "class": "RandomInt", "summary": "随机整数" },
	"random_float" : { "category": MATH, "class": "RandomFloat", "summary": "随机浮点" }
}


static func get_entry(func_name:String) -> Dictionary:
	return TABLE.get(func_name, {})


static func get_class_name_of(func_name:String) -> String:
	var entry = get_entry(func_name)
	return entry.get("class", "")


static func get_category(func_name:String) -> String:
	var entry = get_entry(func_name)
	return entry.get("category", "")


static func get_by_category(category:String) -> Dictionary:
	var result:Dictionary = {}
	for func_name in TABLE.keys():
		var entry:Dictionary = TABLE[func_name]
		if entry.get("category", "") == category:
			result[func_name] = entry
	return result


static func get_all_func_names() -> Array:
	return TABLE.keys()
