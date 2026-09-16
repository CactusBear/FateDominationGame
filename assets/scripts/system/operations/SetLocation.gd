class_name SetLocation
extends RefCounted

#把玩家放到指定位置（部署、效果搬运、常规移动都走这里落地）。
#参数语义：
#  is_move      这一次是不是"一次常规移动"。规则上只有常规移动才受目标区域
#               _can_move_to 的限制；部署与效果造成的落位传 false，不受该限制。
#  ignore_limit 是否忽略落点的人数上限(_pl_num_limit)。需要无视站位上限的效果传 true。
#落点所属战区从 location 自己的 from 取：MapData._init() 与 load_locations() 都已把
#BaseLocation.from 接好，不必遍历 MapData.areas 反查（遍历法在落点不属于
#任何区域时会取到 null 并崩溃）
#返回是否真正落位。调用方（如 Deploy）据此决定要不要记"部署成功"这类后续事实，
#不能无条件记——位置满/不可移入时实际没动，却记一条部署会把失败当成功
func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true, ignore_limit:bool = false) -> bool:

	if setted_location == null:
		return false
	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !ignore_limit and setted_location._pl_num_limit != -1 and setted_location._pl_num_limit <= setted_location._players.size():
		#show("目标位置已满")
		return false
	var area := setted_location.get_from() as BaseMapArea
	if is_move and area != null and area._can_move_to == false:
		#show("无法移动至此区域")
		return false
	#常规移动时双向检查落点与出发地的战区锁(area_locked)。
	#锁由事件牌等按效果名声明在战区上（如固有结界），锁谁由数据决定；
	#部署与效果搬运(is_move=false)不受锁限制，与 _can_move_to 同一套语义
	if is_move and _area_locked(area):
		#show("无法移动至此区域")
		return false
	if is_move:
		var old_loc = player_data.get("location") as BaseLocation
		if old_loc != null and old_loc != setted_location and _area_locked(old_loc.get_from() as BaseMapArea):
			#show("无法离开此区域")
			return false
	#离开旧位置：把玩家从旧位置的_players里摘掉，否则旧位置的人数永远只增不减，
	#部署上限判定(_pl_num_limit)和"该位置有几人"的展示都会失真
	var old_location = player_data.get("location") as BaseLocation
	if old_location != null:
		old_location._players.erase(player_id)
	player_data["location"] = setted_location
	if !setted_location._players.has(player_id):
		setted_location._players.append(player_id)

	#日志：谁去了哪个战区、从哪来、是不是常规移动。
	#SetLocation 是通用落地点（常规移动/部署/效果搬运都走这里），它只知道 is_move，
	#不知道落位到底是"部署"还是"效果搬运"，所以只记中性的"位置变化" + is_move 事实；
	#"部署"这个规则动作由 Deploy 入口自己记，不从"不是移动"反推
	var old_area_name := ""
	if old_location != null:
		var old_area := old_location.get_from() as BaseMapArea
		if old_area != null:
			old_area_name = str(old_area._area_name)
	GameLog.record("move", player_id, -1,
		str(area._area_name) if area != null else "", null,
		["move"], {"is_move": is_move, "from_area": old_area_name})
	return true


#战区是否被锁（如固有结界的"不能移动至此也不能离开"）。
#锁的声明者是挂在战区上的事件牌/buff，效果名固定为 area_locked：
#所有事件牌写同一个效果名，锁哪块战场由牌挂在哪决定，这里不写死任何战区
func _area_locked(area:BaseMapArea) -> bool:
	if area == null:
		return false
	return MapAreaHasEffect.new().exec(area, "area_locked")
