class_name EmitTimePoint
extends RefCounted

#派发一个时点。SetPlayerData只改字段，真名解放/隐藏、自定义时点都要能单独触发。
#player_id为-1时走全局时点，与GameProgress.process_time_point一致。
func exec(time_point:String, player_id:int = -1):

	if time_point == "":
		return
	GameProgress.process_time_point(time_point, player_id)
