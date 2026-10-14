class_name EmitTimePoint
extends RefCounted

#派发一个时点。SetPlayerData只改字段，真名解放/隐藏、自定义时点都要能单独触发。
#player_id为-1时走全局时点；显式来源只传递，不在消费口签发或刷新。
func exec(time_point:String, player_id:int = -1, context:Variant = null):
	if time_point == "":
		return
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context):
		return
	#直接复用时点基础设施，避免经无来源参数的进度/UI转发入口丢失原句柄。
	if player_id == -1:
		TimePointChecker.global_time_point([time_point], null, context)
		return
	TimePointChecker.dynamic_time_point([time_point], player_id, null, context)
