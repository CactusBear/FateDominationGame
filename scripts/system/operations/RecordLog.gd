class_name RecordLog
extends RefCounted

#只记录一条调用方声明的事实；上下文、冻结与观察链由 GameLog 统一负责。
func exec(type:String, actor:int = -1, target:int = -1,
		place:String = "", object = null, tags:Array = [],
		params:Dictionary = {}) -> Dictionary:
	return GameLog.record(type, actor, target, place, object, tags, params)
