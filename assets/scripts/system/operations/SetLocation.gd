class_name SetLocation
extends RefCounted

#把玩家放到指定位置（部署、效果搬运、常规移动都走这里落地）。
#参数语义：
#  is_move      这一次是不是"一次常规移动"。规则上只有常规移动才受目标区域
#               _can_move_to 的限制；部署与效果造成的落位传 false，不受该限制。
#  ignore_limit 是否忽略落点的人数上限(_pl_num_limit)。需要无视站位上限的效果传 true。
#落点所属战区从 location 自己的 from 取：MapData._init() 与 load_locations() 都已把
#BaseLocation.from 接成所属区域，不必遍历 MapData.areas 反查（遍历法在落点不属于
#任何区域时会取到 null 并崩溃）
func exec(setted_location:BaseLocation, player_id:int = -1, is_move:bool = true, ignore_limit:bool = false):

	if setted_location == null:
		return
	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !ignore_limit and setted_location._pl_num_limit != -1 and setted_location._pl_num_limit <= setted_location._players.size():
		#show("目标位置已满")
		return
	var area := setted_location.get_from() as BaseMapArea
	if is_move and area != null and area._can_move_to == false:
		#show("无法移动至此区域")
		return
	#离开旧位置：把玩家从旧位置的_players里摘掉，否则旧位置的人数永远只增不减，
	#部署上限判定(_pl_num_limit)和"该位置有几人"的展示都会失真
	var old_location = player_data.get("location") as BaseLocation
	if old_location != null:
		old_location._players.erase(player_id)
	player_data["location"] = setted_location
	if !setted_location._players.has(player_id):
		setted_location._players.append(player_id)
