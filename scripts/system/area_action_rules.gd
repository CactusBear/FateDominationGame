class_name AreaActionRules
extends RefCounted


static func current_area(pl_data: Dictionary) -> BaseMapArea:
	var loc = pl_data.get("location") as BaseLocation
	if loc == null:
		return null
	return loc.get_from() as BaseMapArea


static func estimate_move_cost(pl_data: Dictionary, step_diff: int) -> int:
	var area := current_area(pl_data)
	if area == null:
		return 0
	var total_cost: int = 0
	var step_discount: int = MoveLocation.step_cost_discount(pl_data)
	for n in range(step_diff):
		if area._linked_map_area == null:
			break
		total_cost += maxi(0, (area._move_cost as BaseNumber).number - step_discount)
		area = area._linked_map_area
	if current_area(pl_data) == MapData.magic_workshop:
		var discount: int = (pl_data.get("move_cost_discount_from_workshop", BaseNumber.new(0)) as BaseNumber).number
		total_cost = max(0, total_cost - discount)
	return total_cost


static func magic_enough_for_move(pl_data: Dictionary, cost: int) -> bool:
	if bool(pl_data.get("is_magic_immune", false)):
		return true
	return (pl_data.get("magic", BaseNumber.new(0)) as BaseNumber).number >= cost


static func block_reason(player_id: int, target_area_idx: int, context:Variant = null) -> String:
	var source:SessionContext = _query_context(context)
	if source == null:
		return "位置查询缺少有效来源"
	if target_area_idx < 0 or target_area_idx >= MapData.areas.size():
		return "目标战区不存在"
	var pl_data: Dictionary = GameDataManager.find_player_data(player_id)
	if pl_data.is_empty():
		return "玩家不存在"
	# 选项级位置选择（令咒"从新都或深山町移动至任意位置"等）：
	# 呼吸光晕与点击入口(_on_battlefield_clicked)共用这一条判据。
	# 只要当前正等玩家选位置、且该战区有合法落点，战区就属于"可操作"，必须亮金框；
	# 否则会陷入常规移动的单向/交战判定，导致"能点却不亮框"
	var pending_loc: Dictionary = get_pending_location_selection(source)
	if EffectManager.waiting_location != null and pending_loc.is_empty():
		return "位置选择来源已失效"
	if not pending_loc.is_empty():
		var spec: Dictionary = pending_loc.get("spec", {})
		var eff: BaseEffect = pending_loc.get("effect")
		if eff == null:
			return "位置选择缺少效果来源"
		# 真实等待只认证字面 trigger，不借观察者或本地玩家授权。
		var trigger_id: int = eff._trigger_player_id
		if trigger_id == -1 or GameDataManager.find_player_data(trigger_id).is_empty():
			return "位置选择玩家不存在"
		if trigger_id != player_id:
			return "当前是其他玩家在选择位置"
		var target_area: BaseMapArea = MapData.areas[target_area_idx]
		# 起点战区校验（如令咒只允许从新都/深山町出发）
		var allowed: Array = spec.get("allowed_origin_areas", []) as Array
		if not allowed.is_empty():
			var origin: BaseLocation = GetLocation.new().exec(trigger_id)
			var origin_area: BaseMapArea = origin.get_from() as BaseMapArea if origin != null else null
			var origin_name: String = origin_area._area_name if origin_area != null else ""
			if not allowed.has(origin_name):
				return "当前战区【%s】不是合法的出发地" % origin_name
		var lock_reason: String = move_lock_reason(trigger_id, target_area, source)
		if lock_reason != "":
			return lock_reason
		if first_effect_location_target(target_area, spec, source) == null:
			return "【%s】没有可用的席位" % target_area._area_name
		return ""
	if GameProgress.current_player_id != player_id:
		return "还没轮到你行动"
	var phase_name := str(GameProgress.get_current_phase().get("name", ""))
	if GameProgress.is_phase_for(player_id, "outpost") \
			and pl_data.get("location") == null:
		var target_area: BaseMapArea = MapData.areas[target_area_idx]
		if DeployRules.open_locations(target_area).is_empty():
			return "【%s】没有可用的部署席位" % target_area._area_name
		return ""
	if not GameProgress.is_phase_for(player_id, "action"):
		return "当前是%s，不能部署或移动" % phase_shown_name(phase_name)
	#交战判定与引擎共用同一个查询：与对手同处一处会发生战斗的战场时不能常规移动
	if IsEngaged.new().exec(player_id):
		return "处于交战状态，无法移动"
	var curr_area := current_area(pl_data)
	if curr_area == null:
		return "你还没有部署到任何战区"
	var current_idx: int = MapData.areas.find(curr_area)
	if current_idx == -1:
		return "你当前的位置不在任何战区上"
	var step_diff: int = target_area_idx - current_idx
	if step_diff <= 0:
		return "移动只能沿单方向前进"
	#落点判据与真正的移动(MoveLocation)共用同一份规则：区域不可移入、或常规落点已满，
	#这里就判为不可操作——既不亮金色提示，点击时也能直接给出原因
	var target_area: BaseMapArea = MapData.areas[target_area_idx]
	var move_lock: String = move_lock_reason(player_id, target_area, source)
	if move_lock != "":
		return move_lock
	if target_area == MapData.scout and GetMoveTargetLocation.new().exec(target_area) == null:
		return "侦查先锋位已被占用"
	if target_area._can_move_to == false:
		return "无法移动至【%s】" % target_area._area_name
	if GetMoveTargetLocation.new().exec(target_area) == null:
		return "【%s】的常规落点已满" % target_area._area_name
	if !magic_enough_for_move(pl_data, estimate_move_cost(pl_data, step_diff)):
		return "魔力不足，无法移动至【%s】" % target_area._area_name
	return ""


static func move_lock_reason(player_id: int, target_area: BaseMapArea, context:Variant = null) -> String:
	var source:SessionContext = _query_context(context)
	if source == null:
		return "位置查询缺少有效来源"
	if EffectManager.waiting_location != null and get_pending_location_selection(source).is_empty():
		return "位置选择来源已失效"
	if target_area == null or not MapData.areas.has(target_area):
		return "目标战区不存在"
	# 无锁不等于主体有效；公开查询入口必须独立做非创建认证。
	if GameDataManager.find_player_data(player_id).is_empty():
		return "玩家不存在"
	var locked: BaseMapArea = SetLocation.locked_area_for_move(player_id, target_area)
	if locked == null:
		return ""
	if locked == target_area:
		return "无法移动至【%s】" % locked._area_name
	return "无法离开【%s】" % locked._area_name


# 来源只读解析：显式句柄优先；旧/缺帧不得借当前局或等待补票。
static func _query_context(context:Variant) -> SessionContext:
	if context == null:
		var frame:Dictionary = EffectManager.execution_context()
		if not frame.get("ok", false):
			return null
		context = frame.get("context")
	return context as SessionContext if SessionGeneration.validate_context(context).ok else null


# 等待本身携带原来源；EM 负责原成员、地图和席位容器身份，本层不重建记录。
static func get_pending_location_selection(context:Variant = null) -> Dictionary:
	if context != null and _query_context(context) == null:
		return {}
	var pending:Dictionary = EffectManager.get_pending_location_selection()
	if pending.is_empty():
		return {}
	var effect:BaseEffect = pending.get("effect")
	if effect == null or not SessionGeneration.origin_of(effect).ok:
		return {}
	var trigger_id:int = effect._trigger_player_id
	if trigger_id == -1 or GameDataManager.find_player_data(trigger_id).is_empty():
		return {}
	return pending


static func phase_shown_name(phase_key: String) -> String:
	match phase_key:
		"prepare": return "准备阶段"
		"outpost": return "前哨阶段"
		"action": return "行动阶段"
		"battle": return "战斗阶段"
	return phase_key


# 仅检查 move_target 落点的当前地图身份、移动落点声明与实时容量。
# 与 GetMoveTargetLocation.exec(area, false) 使用相同属性/容量口径，但可逐点验证，
# 不要求所选位等于首个候选；-1 仍表示无限容量。
# 这是只读落点谓词，不认证来源/成员/原等待容器，不检查起点、两端锁或范围声明，
# 也不授予部署收益、常规移动方向/费用/交战豁免；调用方须保留完整选择准入门。
static func is_move_target_location(location:BaseLocation) -> bool:
	if not SetLocation.current_map_location(location) or not location._will_move_to:
		return false
	return location._pl_num_limit == -1 or location._players.size() < location._pl_num_limit


static func first_effect_location_target(area:BaseMapArea, spec:Dictionary = {}, context:Variant = null) -> BaseLocation:
	var source:SessionContext = _query_context(context)
	if source == null:
		return null
	if EffectManager.waiting_location != null and get_pending_location_selection(source).is_empty():
		return null
	if area == null or not MapData.areas.has(area):
		return null
	#效果移动同样不能进入被锁战区（固有结界等）：没有合法落点，点击、金框与 AI 选点一并排除
	if SetLocation.area_locked(area):
		return null
	var target_slot:String = str(spec.get("target_slot", ""))
	# 显式新枚举先于旧分区规则消费；其他值仍走原分支，不改变 unlimited 含义。
	if target_slot == "move_target":
		for location:BaseLocation in area._locations:
			if location.get_from() == area and is_move_target_location(location):
				return location
		return null
	for loc:BaseLocation in area._locations:
		if SetLocation.current_map_location(loc) and loc.get_from() == area and effect_slot_accepts(loc, spec):
			return loc
	return null


## 效果移动的席位口径，候选（first_effect_location_target）与提交校验（EffectManager）共用这一份。
## 非战场区域（区域数据 _score_need_win=false，如魔术工房/侦察）严禁移入无限格，只收有空位的限人数席位，
## 不论 target_slot；全满即无法移动。效果移动不是部署，不结算席位魔力（魔力只在部署收益里发）。
## 战场：target_slot="unlimited" 只收无限格；未声明时按容量。
static func effect_slot_accepts(location:BaseLocation, spec:Dictionary = {}) -> bool:
	var area := location.get_from() as BaseMapArea
	if area != null and not area._score_need_win:
		return location._pl_num_limit != -1 and location._players.size() < location._pl_num_limit
	if str(spec.get("target_slot", "")) == "unlimited":
		return location._pl_num_limit == -1
	return location._pl_num_limit == -1 or location._players.size() < location._pl_num_limit
