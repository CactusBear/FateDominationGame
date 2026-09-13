class_name CloneObject
extends RefCounted

#复制一份游戏对象。Godot的duplicate对RefCounted不可用，同一份specials里的模板
#若直接加入牌库，多张牌会改到同一组数字和效果。
#只复制数据，不登记给玩家、不放进任何区域；from仍指向原所属(御主/从者)，不克隆所属。
#运行时字段(激活中、已关闭、触发快照)按新对象重置，避免把场上状态拷走。
func exec(object):

	if object == null:
		return null
	if object is BaseNumber:
		return _clone_number(object)
	if object is BaseFunc:
		return _clone_func(object)
	if object is BaseEffect:
		return _clone_effect(object)
	if object is BaseAttack:
		return _clone_attack(object)
	if object is BaseSkill:
		return _clone_skill(object)
	if object is BaseBuff:
		return _clone_buff(object)
	if object is BaseEvent:
		return _clone_event(object)
	if object is BaseSituation:
		return _clone_situation(object)
	if object is BaseLocation:
		return _clone_location(object)
	if object is BaseMaster:
		return _clone_master(object)
	if object is BaseServant:
		return _clone_servant(object)
	return null


func _clone_number(num:BaseNumber) -> BaseNumber:
	if num == null:
		return BaseNumber.new(0)
	return BaseNumber.new(num.number, num.can_change, num.is_pure_number)


func _clone_func(src:BaseFunc) -> BaseFunc:
	var paras:Array = _clone_parameters(src._parameters)
	var cloned:BaseFunc
	if src._self_var_index != -1:
		cloned = BaseFunc.new_method_func(src._self_var_index, src._method_name, paras, src._var_index, _clone_value(src._condition))
	else:
		var instance = null
		if src._instance != null:
			var script = src._instance.get_script()
			if script != null:
				instance = script.new()
		var callable = src._func
		if instance != null:
			callable = Callable(instance, "exec")
		cloned = BaseFunc.new(callable, paras, src._var_index, _clone_value(src._condition))
		cloned._instance = instance
	cloned._func_used = false
	cloned._if_affect_power = src._if_affect_power
	cloned._priority = src._priority
	cloned._func_target_player = src._func_target_player
	cloned._func_target_property = src._func_target_property
	return cloned


func _clone_effect(src:BaseEffect) -> BaseEffect:
	var cloned = BaseEffect.new(src._name, src._time_points.duplicate(), src._priority, src._is_pure_passive, src._is_residue)
	cloned._shown_name = src._shown_name
	cloned._need_activate = src._need_activate
	#时点匹配模式跟着效果走，漏复制会让AND模式的克隆体退化成OR(条件被放宽)
	cloned._time_points_require_all = src._time_points_require_all
	cloned._cost = src._cost
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	var nums:Array = []
	for num in src.numbers:
		if num is BaseNumber:
			nums.append(_clone_number(num))
		else:
			nums.append(num)
	cloned.set_numbers(nums)
	cloned._using_numbers = nums
	cloned.register_numbers_to_source()
	for f in src._funcs:
		if f is BaseFunc:
			cloned.add_func(_clone_func(f))
	#选项体系：选项自带的funcs要逐个克隆，上限与重置/消耗声明照搬。
	#用量计数是场上进度不是卡面信息，克隆体从零开始
	cloned._max_choices = src._max_choices
	cloned._max_total_uses = src._max_total_uses
	cloned._reset_counts_each_round = src._reset_counts_each_round
	cloned._consumes_source_resource = src._consumes_source_resource
	var cloned_options:Array = []
	for opt in src._options:
		if not (opt is Dictionary):
			continue
		var new_opt:Dictionary = opt.duplicate()
		var opt_funcs:Array = []
		for f in opt.get("funcs", []):
			if f is BaseFunc:
				opt_funcs.append(_clone_func(f))
		new_opt["funcs"] = opt_funcs
		cloned_options.append(new_opt)
	cloned._options = cloned_options
	cloned._chosen_selection = {}
	cloned._option_use_counts = {}
	cloned._self_vars = []
	cloned._trigger_player_id = -1
	cloned._trigger_time_points = []
	return cloned


func _clone_effects(effects:Array) -> Array:
	var cloned_effects:Array = []
	for effect in effects:
		if effect is BaseEffect:
			cloned_effects.append(_clone_effect(effect))
	return cloned_effects


func _bind_effects(cloned_effects:Array, owner) -> void:
	for effect in cloned_effects:
		if effect is BaseEffect:
			effect.from = owner
			effect.register_numbers_to_source()


func _clone_attack(src:BaseAttack) -> BaseAttack:
	var cloned = BaseAttack.new(src._name, src._card_img, src._attributes.duplicate(), _clone_number(src._cost), _clone_number(src._power), [])
	cloned._category = src._category
	_copy_card_common(src, cloned)
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	return cloned


func _clone_skill(src:BaseSkill) -> BaseSkill:
	var cloned = BaseSkill.new(src._name, src._card_img, src._attributes.duplicate(), _clone_number(src._cost), _clone_number(src._power), src._ignore_limit, [])
	#觉醒状态是卡面信息的一部分，跟着卡走；漏复制会让觉醒的升华技被当成未觉醒
	cloned._is_awakened = src._is_awakened
	_copy_card_common(src, cloned)
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	return cloned


func _clone_buff(src:BaseBuff) -> BaseBuff:
	var cloned = BaseBuff.new(src._name, src._buff_img)
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	cloned._shown_name = src._shown_name
	cloned._zoom_kind = src._zoom_kind
	cloned._is_active = src._is_active
	cloned._buff_level = _clone_number(src._buff_level)
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	return cloned


func _clone_event(src:BaseEvent) -> BaseEvent:
	var cloned = BaseEvent.new(src._name, src._card_img, _clone_number(src._score), [])
	_copy_card_common(src, cloned)
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	return cloned


func _clone_situation(src:BaseSituation) -> BaseSituation:
	var cloned = BaseSituation.new(src._name, src._card_img, _clone_number(src._magic), [])
	_copy_card_common(src, cloned)
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	return cloned


func _clone_location(src:BaseLocation) -> BaseLocation:
	var cloned = BaseLocation.new(_clone_number(src._magic), _clone_number(src._benefit), src._pl_num_limit, src._will_move_to)
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	cloned._shown_name = src._shown_name
	cloned._players = []
	return cloned


func _clone_master(src:BaseMaster) -> BaseMaster:
	var cloned = BaseMaster.new(src._name, src.get_shown_name(), src._header_img, src._master_card_img, src._command_spell_img)
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	cloned._shown_name = src._shown_name
	#卡背与放大分类都属于卡面信息，跟着对象走
	cloned._card_back_img = src._card_back_img
	cloned._zoom_kind = src._zoom_kind
	cloned._zoom_kinds = src._zoom_kinds.duplicate()
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	cloned._specials = _clone_specials(src._specials, cloned)
	cloned._upgrade_skill = _clone_object_array(src._upgrade_skill)
	cloned._other_things = _clone_object_array(src._other_things)
	return cloned


func _clone_servant(src:BaseServant) -> BaseServant:
	var cloned = BaseServant.new(src._name, src.get_shown_name(), src._servant_class, src._header_img, src._servant_card_img)
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	cloned._shown_name = src._shown_name
	cloned._card_back_img = src._card_back_img
	cloned._zoom_kind = src._zoom_kind
	cloned._zoom_kinds = src._zoom_kinds.duplicate()
	cloned._effects = _clone_effects(src._effects)
	_bind_effects(cloned._effects, cloned)
	cloned._specials = _clone_specials(src._specials, cloned)
	return cloned


func _clone_specials(specials:Dictionary, owner) -> Dictionary:
	var cloned:Dictionary = {}
	for key in specials.keys():
		var value = specials[key]
		if value is Array:
			cloned[key] = _clone_object_array(value)
		else:
			cloned[key] = exec(value)
		if cloned[key] is Array:
			for item in cloned[key]:
				if item is BaseObject:
					item.from = owner
	return cloned


func _clone_object_array(arr:Array) -> Array:
	var cloned:Array = []
	for item in arr:
		cloned.append(exec(item))
	return cloned


func _copy_card_common(src:BaseCard, cloned:BaseCard) -> void:
	cloned.from = src.from
	cloned.tags = _clone_tags(src.tags)
	cloned._shown_name = src._shown_name
	cloned._attributes = src._attributes.duplicate()
	#卡背是卡面印刷信息的一部分，跟着卡走。发到玩家手里/技能区的都是克隆体，
	#漏复制会让所有暗置牌拿不到自己的卡背（表现为技能区卡背错乱或空白）
	cloned._card_back_img = src._card_back_img
	#放大分类属于卡面信息，跟着卡走；漏复制会让克隆牌拿不到分类从而不能放大
	cloned._zoom_kind = src._zoom_kind
	cloned._zoom_kinds = src._zoom_kinds.duplicate()
	#明暗是场上状态，克隆体一律从明置开始
	cloned._is_concealed = false
	#物品卡展示的是哪个buff属于卡面信息，跟着卡走；漏复制会让克隆出来的物品卡
	#查不到buff状态，未激活的深红遮罩就不会盖(表现为同一张卡在原位置有遮罩、在克隆位上没有)
	cloned._relate_buff = src._relate_buff
	if cloned is BaseHandCard and src is BaseHandCard:
		cloned._is_activating = false
		cloned._is_closed = false
		cloned._cost_discount = _clone_number(src._cost_discount)


func _clone_tags(tags:Array) -> Array:
	var cloned:Array = []
	for tag in tags:
		if tag is Dictionary:
			cloned.append(tag.duplicate(true))
		else:
			cloned.append(tag)
	return cloned


func _clone_parameters(paras:Array) -> Array:
	var cloned:Array = []
	for para in paras:
		cloned.append(_clone_value(para))
	return cloned


func _clone_value(value):
	if value is BaseNumber:
		return _clone_number(value)
	if value is Array:
		return _clone_parameters(value)
	if value is Dictionary:
		var cloned:Dictionary = {}
		for key in value.keys():
			cloned[key] = _clone_value(value[key])
		return cloned
	return value
