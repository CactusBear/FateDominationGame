extends Node





var global_signals:Dictionary
var current_time_points:Array

func time_point(time_point:String):
	for sig:Signal in global_signals[time_point]:
		emit_signal(sig.get_name())
	
