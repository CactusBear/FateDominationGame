class_name FlipCardFace
extends RefCounted

#双面卡切换到另一面（战型、礼装、第X天、原罪↔美德……）。各面的数据由卡牌 JSON 的 faces 声明，
#格式与这类牌单张的 JSON 相同；切换时按那一面的数据重建卡面字段与效果：
#旧面的效果注销，新面的效果按这张牌原来的归属玩家登记。明暗、激活、关闭这些场上状态不变——
#翻面不是离场。face_index 为 -1 时切到下一面（最后一面之后回到第一面）。
#返回切换后的牌；没声明 faces、下标越界或建不出那一面时返回 null 且不做任何改动
func exec(card:BaseCard, face_index = -1):

	if card == null or card._faces.is_empty():
		return null
	var index:int = int(face_index.number if face_index is BaseNumber else face_index)
	if index < 0:
		index = (card._face_index + 1) % card._faces.size()
	if index >= card._faces.size() or !(card._faces[index] is Dictionary):
		return null
	var face = BuildCard.new().exec(card._faces[index], _card_type(card), card.from, card._card_img.get_base_dir())
	if face == null:
		return null
	#新面的效果登记给谁：旧面效果已登记的沿用那名玩家；旧面没有登记的效果时（旧面本来就没有效果），
	#按这张牌此刻在谁的牌区里判定。两者都没有（牌不属于任何玩家）就不登记
	var owner_id:int = -1
	for eff in card._effects:
		if !(eff is BaseEffect):
			continue
		if EffectManager.effect_pool.has(eff) and eff._trigger_player_id != -1:
			owner_id = eff._trigger_player_id
		eff.del()
	if owner_id == -1:
		owner_id = CardZones.owner_of(card)
	var old_name:String = card.get_shown_name()
	_copy_face(face, card)
	card._face_index = index
	face.del()
	if owner_id != -1:
		EffectManager.register_effects(card._effects, owner_id)
	if card.has_method("record_modification"):
		card.record_modification("face", "%s → %s" % [old_name, card.get_shown_name()])
	if owner_id != -1:
		TimePointChecker.dynamic_time_point([TimePoints.CARD_FACE_FLIPPED], owner_id, card)
	else:
		TimePointChecker.global_time_point([TimePoints.CARD_FACE_FLIPPED], card)
	return card


#牌的类型决定用哪一个加载函数建另一面
func _card_type(card:BaseCard) -> String:
	if card is BaseAttack:
		return "attack"
	if card is BaseSkill:
		return "skill"
	if card is BaseEvent:
		return "event"
	if card is BaseSituation:
		return "situation"
	if LoadCommandSpell.get_command_spell(card._name) != null:
		return "command_spell"
	return "thing"


#把新一面的卡面字段与效果搬到原来这张牌上。数值对象就地改值：
#别处（numbers、玩家合计威力的计算）持有的是同一个 BaseNumber 引用
func _copy_face(face:BaseCard, card:BaseCard) -> void:
	card._name = face._name
	card._shown_name = face._shown_name
	card._card_img = face._card_img
	card._zoom_kind = face._zoom_kind
	card._attributes = face._attributes.duplicate()
	card._keywords = face._keywords.duplicate()
	card._alias_names = face._alias_names.duplicate()
	if face._card_back_img != "":
		card._card_back_img = face._card_back_img
	if card is BaseHandCard and face is BaseHandCard:
		var id:int = _player_of(card)
		var counted:bool = id >= 0 and CardCountsPower.new().exec(card, id)
		var old_power:int = card._power.number
		card._cost.set_num(face._cost)
		card._power.set_num(face._power)
		card._play_requirements = face._play_requirements.duplicate(true)
		card._shown_notes = face._shown_notes.duplicate()
		card._need_extra_play = face._need_extra_play
		#场上计入威力的牌换面后威力变了，玩家的合计威力同步差值（与 EditCardPower 同一口径）
		if counted:
			(GameDataManager.get_player_data(id)["power"] as BaseNumber).add(BaseNumber.new(card._power.number - old_power))
	if card is BaseAttack and face is BaseAttack:
		card._category = face._category
	if card is BaseSkill and face is BaseSkill:
		card._ignore_limit = face._ignore_limit
	if card is BaseEvent and face is BaseEvent:
		card._score.set_num(face._score)
	if card is BaseSituation and face is BaseSituation:
		card._magic.set_num(face._magic)
	card.effect_numbers.clear()
	card._effects = face._effects
	face._effects = []
	for eff in card._effects:
		eff.from = card
		eff.register_numbers_to_source()


#这张牌在谁的打出区里（只用于同步合计威力）
func _player_of(card) -> int:
	for id in GameData.player_data_library.keys():
		if (GameData.player_data_library[id]["played_cards"] as Array).has(card):
			return int(id)
	return -1
