class_name SituationResolver
extends RefCounted


#局势牌流程：每回合开始时抽一张局势牌放激活区(A2)并派魔力，回合结束时弃置。
#抽哪张由回合号决定：1-8随机抽非高潮牌堆(A1)，9/10/11抽固定高潮牌。
#高潮牌的展示回合存在LoadSituation.climax_situations的key里，规则数字不写死。


#每回合开始：抽牌展示 + 所有玩家获得印刷魔力 + 登记效果
func activate():
	var situation = _draw_current()
	MapData.active_situation = situation
	if situation == null:
		return
	#规则：所有玩家获得局势牌上印刷的魔力
	for id in GameDataManager.get_active_player_ids():
		EditMagic.new().exec(null, situation._magic, id)
	#把局势牌效果登记进效果池(挂battle_resolve的属性加成等)
	_register_situation_effects()


#回合结束：弃置激活的局势牌
func clear_all():
	var situation = MapData.active_situation
	if situation == null:
		return
	UnregisterObjectEffects.new().exec(situation)
	situation.del()
	MapData.active_situation = null
	#封区类局势牌(如身处地狱之门)只在本回合有效：弃置时把被改动的
	#战区"能否常规进入"按印刷基线还原，防止一回合的封区永久生效
	RestoreMapAreaMoveFlags.new().exec()
	#限员类局势牌(如"魔术工房仅限一人部署")同理：弃置时还原席位人数基线
	RestoreLocationPlNumLimits.new().exec()


#抽当前回合的局势牌：1-8抽A1非高潮，高潮回合抽对应高潮牌。
#挂到激活区的是克隆体，模板留在池里，重开一局还能重新发牌
func _draw_current():
	var round:int = GameProgress.current_round
	if LoadSituation.climax_situations.has(round):
		var template = LoadSituation.climax_situations[round]
		return CloneObject.new().exec(template) as BaseSituation
	if MapData.situations.is_empty():
		return null
	var template = MapData.situations.pop_front()
	return CloneObject.new().exec(template) as BaseSituation


#把局势牌效果登记进效果池，归属顺位第一的存活玩家作锚点。
#锚点玩家只当触发器，效果作用对象由效果内部的get_map_area_by_name等决定
func _register_situation_effects():
	var anchor:int = -1
	for id in GameDataManager.get_active_player_ids():
		anchor = id
		break
	if anchor == -1:
		return
	for effect in MapData.active_situation._effects:
		if effect._trigger_player_id == -1:
			EffectManager.register_effect(effect, anchor)
