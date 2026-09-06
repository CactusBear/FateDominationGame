class_name AddSkillToSkillZone
extends RefCounted

#把技能卡加入玩家的技能区(side.skills)，并把技能自带的效果登记为该玩家的效果
func exec(skill, player_id:int = -1):

	var id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(id)
	var skill_obj:BaseSkill = _resolve_skill(skill, player_data)
	if skill_obj == null:
		return
	var zone = player_data["side"]["skills"] as Array
	if zone.has(skill_obj):
		return
	zone.append(skill_obj)

	#技能进入技能区后，它自己的效果才开始参与时点检查
	EffectManager.register_effects(skill_obj._effects, id)
	return skill_obj


func _resolve_skill(skill, player_data:Dictionary) -> BaseSkill:
	if skill is BaseSkill:
		return skill
	if !(skill is String):
		return null
	#先在触发这个效果的卡的来源里找，找不到再退回玩家的御主
	var found = _find_in_source(skill)
	if found != null:
		return found
	return _find_in_master(skill, player_data["master"])


#顺着from链找到效果所属的御主/从者，在它的SKILLS里查找同名技能
func _find_in_source(skill_name:String) -> BaseSkill:
	var eff = EffectManager.activating_eff
	if eff == null:
		return null
	var source = eff.from
	while source is BaseObject:
		var found = _find_in_master(skill_name, source)
		if found != null:
			return found
		source = source.from
	return null


func _find_in_master(skill_name:String, source) -> BaseSkill:
	if source == null:
		return null
	#BaseServant目前还没有_specials字段，所以先检查属性是否存在
	if !("_specials" in source):
		return null
	var specials = source._specials as Dictionary
	if specials == null or !specials.has("SKILLS"):
		return null
	for s in specials["SKILLS"]:
		if s is BaseSkill and s._name == skill_name:
			return s
	return null
