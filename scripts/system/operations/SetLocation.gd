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
func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true, ignore_limit:bool = false, check_area_lock:bool = true) -> bool:

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
	#area_locked 约束普通、令咒和效果移动；部署调用方显式 check_area_lock=false。
	#人数上限与常规禁入仍是独立开关，不能靠 is_move=false 偷渡移动锁。
	if check_area_lock and area_locked(area):
		return false
	if check_area_lock:
		var old_loc = player_data.get("location") as BaseLocation
		if old_loc != null and old_loc != setted_location and area_locked(old_loc.get_from() as BaseMapArea):
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
	#进入/离开地点是比常规移动更宽的事实（部署、效果搬运都算），带落点/旧位置作来源派发
	if old_location != setted_location:
		if old_location != null:
			TimePointChecker.dynamic_time_point([TimePoints.LEAVE_LOCATION], player_id, old_location)
		TimePointChecker.dynamic_time_point([TimePoints.ENTER_LOCATION], player_id, setted_location)
	return true


#战区锁的效果名（如固有结界的"不能移动至此也不能离开"）。
#所有事件牌写同一个效果名，锁哪块战场由牌挂在哪决定，这里不写死任何战区
const AREA_LOCKED := "area_locked"


#战区是否被锁。静态查询：落位、移动、效果的位置选择、界面金框与 AI 选点共用这一处判据
static func area_locked(area:BaseMapArea) -> bool:
	if area == null:
		return false
	return MapAreaHasEffect.new().exec(area, AREA_LOCKED)


#玩家从当前位置移动到目标战区时挡住他的那块被锁战区：出发战区优先，其次目标战区；没有被挡返回 null。
#与 exec 的锁判定同一口径（目标被锁不能进入，出发地被锁不能离开）。部署不是移动，不走这里
static func locked_area_for_move(player_id:int, target_area:BaseMapArea) -> BaseMapArea:
	var loc = GameDataManager.get_player_data(player_id).get("location")
	var origin:BaseMapArea = loc.get_from() as BaseMapArea if loc is BaseLocation else null
	if area_locked(origin):
		return origin
	if area_locked(target_area):
		return target_area
	return null
