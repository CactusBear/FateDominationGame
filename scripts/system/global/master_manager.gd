extends Node

const Registration = preload("res://scripts/system/operations/RegisterObjectEffects.gd")


#只管理御主效果与玩家的御主归属，不负责游戏开始、从者或技能。
#注册为autoload"MasterManager"，不能再带class_name(两者会重名冲突)。
func bind_master_effects(player_id:int, source_context:SessionContext = null) -> bool:
	if not SessionGeneration.validate_context(source_context).ok:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var master = player_data.get("master")
	if master == null:
		return EffectManager.register_effects([], player_id)
	if not master is BaseMaster:
		return false
	var prepared:Dictionary = prepare_role_runtime(master, source_context)
	if not prepared.ok:
		return false
	var runtime:BaseMaster = prepared.object
	var registered:bool = EffectManager.register_effects(runtime._effects, player_id)
	if registered:
		player_data["master"] = runtime
	return registered


# 仅传明确加载模板 identity；子卡/effect/func 的复制与来源由 C0 统一处理。
class RoleRuntimeClone extends CloneContext:
	func _init(context:SessionContext, trusted_templates:Array):
		configure_template(context, trusted_templates)


func _is_loaded_role_template(role:BaseObject) -> bool:
	var templates:Array = GameData.loaded_masters if role is BaseMaster else GameData.loaded_servants
	for template in templates:
		if is_same(template, role):
			return true
	return false


# 已有 runtime 只读检查，保留对象 identity 与效果池登记；消费口不得补票。
# 只遍历实际拥有/复制边，不追 from 或函数参数中的游戏对象引用。
func _runtime_graph_is_current(value, source:SessionContext, path:Array) -> bool:
	if not (value is Object or value is Array or value is Dictionary):
		return true
	for ancestor in path:
		if is_same(ancestor, value):
			return false
	path.append(value)
	var children:Array = []
	if value is BaseCard or value is BaseEffect or value is BaseFunc:
		var status:Dictionary = SessionGeneration.origin_of(value)
		if not status.ok or not is_same(status.context.token(), source.token()):
			return false
		if value is BaseEffect or value is BaseFunc:
			if not value.runtime_source_status().ok:
				return false
	if value is Array:
		children = value
	elif value is Dictionary:
		children = value.values()
	elif value is BaseCard:
		children = [value._effects, value._attached_cards]
	elif value is BaseMaster:
		children = [value._effects, value._specials, value._upgrade_skill, value._other_things]
	elif value is BaseServant:
		children = [value._effects, value._specials]
	elif value is BaseBuff:
		children = [value._effects]
	elif value is BaseEffect:
		children = [value._funcs]
		for option in value._options:
			if option is Dictionary:
				children.append(option.get("funcs", []))
				for requirement in option.get("activation_requirements", []):
					if requirement is Dictionary:
						children.append(requirement.get("funcs", []))
	for child in children:
		if not _runtime_graph_is_current(child, source, path):
			return false
	path.pop_back()
	return true


# 两个 manager 共用创建边界；无直属 effects 的角色也必须处理全部子卡。
func prepare_role_runtime(role:BaseObject, source_context:SessionContext) -> Dictionary:
	if not SessionGeneration.validate_context(source_context).ok or not (role is BaseMaster or role is BaseServant):
		return {"ok":false, "object":null}
	for effect in role._effects:
		if not effect is BaseEffect:
			return {"ok":false, "object":null}
	if not _is_loaded_role_template(role):
		var valid:bool = _runtime_graph_is_current(role, source_context, [])
		return {"ok":valid, "object":role if valid else null}
	var factory := RoleRuntimeClone.new(source_context, [role])
	return factory.copy_result(role, source_context)


#把御主卡牌数据显式声明的开局物件放入对应区域。只接受白名单路径，未知声明不产生行为；
#每一张都是独立克隆体，避免共享费用、激活状态与效果运行状态。
func deal_initial_master_cards(player_id:int, source_context:SessionContext) -> bool:
	if not SessionGeneration.validate_context(source_context).ok:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var master = player_data.get("master")
	if master == null:
		return true
	if not master is BaseMaster:
		return false
	var zones:Dictionary = {
		"out_of_game.attacks": player_data["out_of_game"]["attacks"],
		"out_of_game.skills": player_data["out_of_game"]["skills"],
		"out_of_game.others": player_data["out_of_game"]["others"]
	}
	var originals:Array = []
	for group_name in ["ATTACKS", "SKILLS"]:
		for template in master._specials.get(group_name, []):
			if not (template is BaseCard) or not zones.has(template._initial_zone):
				continue
			for _i in range(template._initial_count):
				originals.append(template)
	# 只有正式加载角色根可授权模板；runtime 子卡直接继承原来源。
	var trusted:Array = [master] if _is_loaded_role_template(master) else []
	var factory := RoleRuntimeClone.new(source_context, trusted)
	var copied:Dictionary = factory.copy_result(originals, source_context)
	if not copied.ok:
		return false
	var cards:Array = copied.object
	for card in cards:
		if not Registration.can_register_object(card, player_id, source_context):
			return false
	for card in cards:
		if not SessionGeneration.validate_context(source_context).ok or not EffectManager.register_effects(card._effects, player_id):
			return false
		(zones[card._initial_zone] as Array).append(card)
	return true


#把玩家的令咒效果挂进效果池。令咒效果（三选一）此前从未被登记，
#JSON 写全了也不会被询问——开局绑定御主/从者效果时一并挂载。
#挂的是令咒模板卡的克隆体上的效果：模板是全体玩家共用的同一份 BaseCard，
#直接登记模板效果会让七个玩家共享同一个 BaseEffect 对象（谁的选项用量都记在一起）；
#克隆体各有一份效果实例，用量计数、消耗判定天然按玩家隔离。克隆出来的效果
#copy_effects 已把 from 指回克隆卡并重登数字，_trigger_player_id 由 register_effect 写入。
#克隆卡本身交给第一个玩家数据持有（out_of_game.command_spell 作登记处），重开一局随对象图释放
func bind_command_spell_effects(player_id:int, source_context:SessionContext = null) -> bool:
	if not SessionGeneration.validate_context(source_context).ok:
		return false
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var template:BaseCard = LoadCommandSpell.resolve_player_command_spell(
		player_data.get("master"), player_data.get("servant"))
	if template == null:
		return EffectManager.register_effects([], player_id)
	var factory := RoleRuntimeClone.new(source_context, [template])
	var copied:Dictionary = factory.copy_result(template, source_context)
	if not copied.ok:
		return false
	var card:BaseCard = copied.object
	var registered:bool = EffectManager.register_effects(card._effects, player_id)
	if registered:
		(player_data["out_of_game"]["command_spell"] as Array).append(card)
	return registered
