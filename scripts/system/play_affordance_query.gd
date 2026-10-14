class_name PlayAffordanceQuery
extends RefCounted

# PlayAttack 的公开只读资格查询。
# 这里只回答“当前这张攻击牌能否从该入口打出”，不支付、不入区、不记日志、不派时点。
# 返回 {ok: bool, reason: StringName, player_id: int}；reason 仅解释拒绝，不能改变资格。
func check(attack:BaseAttack, player_id:int = -1, ignore_limit:bool = false) -> Dictionary:
	# 保持 PlayAttack 的短路顺序：空牌先拒绝，之后才解析玩家或读取任何局面规则。
	if attack == null:
		return _reject(&"attack_missing")
	# 单卡入口仅供显式特殊出牌；常规出牌必须提交整组。
	if not ignore_limit and EffectManager.activating_eff == null:
		return _reject(&"entry_requires_effect")

	var id:int = EffectManager.resolve_player_id(player_id)
	if !GameData.player_data_library.has(id):
		return _reject(&"player_missing", id)
	# 这里使用现有只读查找语义；成员已由上一门确认存在，不按需新建玩家。
	var player_data:Dictionary = GameDataManager.get_player_data_readonly(id)
	if player_data["is_out"]:
		return _reject(&"player_out", id)
	# “无法打出卡牌”是通用效果名查询，不把具体 buff 类型写进入口。
	if PlayerBuffsHaveEffect.new().exec(CannotPlayCardsEffect.EFFECT_NAME, id):
		return _reject(&"cards_forbidden", id)

	# ignore_limit 只有在确实由效果链驱动时才放宽阶段与行动者；
	# 无效果链的调试/外部调用仍受常规阶段和行动者约束。
	var effect_driven:bool = ignore_limit and EffectManager.activating_eff != null
	if !effect_driven:
		if GameProgress.get_current_phase().get("name", "") != "action":
			return _reject(&"wrong_phase", id)
		if GameProgress.current_player_id != id:
			return _reject(&"not_current_player", id)
	if attack._is_activating:
		return _reject(&"card_activating", id)
	# 卡面条件与场面禁令统一交给既有 PlayRules，不在这里复制条件解释器。
	if !PlayRules.can_play(attack, player_data):
		return _reject(&"card_rule", id)

	# 上限仍从玩家数据读取，已打出数量仍复用 PlayRules.played_count。
	var play_limit:BaseNumber = player_data["play_limit"] as BaseNumber
	var played_count:int = PlayRules.played_count(id, "attack")
	if !ignore_limit and EffectManager.activating_eff == null and played_count >= play_limit.number:
		return _reject(&"play_limit", id)
	return {"ok":true, "reason":&"", "player_id":id}


func _reject(reason:StringName, player_id:int = -1) -> Dictionary:
	return {"ok":false, "reason":reason, "player_id":player_id}
