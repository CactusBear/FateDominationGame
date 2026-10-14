extends "res://scripts/net/server/server_gateway.gd"

## 诊断只读：返回原方法的布尔值；只在失效出口记录非凭据标量。
func _route_is_current(peer:int,route:Dictionary) -> bool:
	var result:bool = super._route_is_current(peer,route)
	if not result:
		var room:Dictionary = manager.rooms.get(route.get("room",""),{})
		print("SUPERVISOR_ROUTE_INVALID ",JSON.stringify({"peer":peer,"same_route":_same_route(peer,route),"binding_matches":manager.binding_matches(route),"require_ready":manager.binding_matches(route,true),"route_pid":route.get("pid"),"current_pid":room.get("pid"),"route_instance":route.get("instance_id"),"current_instance":room.get("instance_id"),"ready":room.get("ready"),"ever_ready":room.get("ever_ready"),"supervision_unknown":room.get("supervision_unknown",false),"room_error":room.get("error"),"ticks_msec":Time.get_ticks_msec()}))
	return result
