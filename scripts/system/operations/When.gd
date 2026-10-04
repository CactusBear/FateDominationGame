class_name When
extends RefCounted

#判断当前激活的效果是否由所给时点中的任意一个触发，返回bool供后续func的condition使用
#用于让同一个效果在不同时点走不同的分支
func exec(time_points:Array):

	var effect = EffectManager.activating_eff
	if effect == null:
		return false
	for tp in time_points:
		if effect._trigger_time_points.has(tp):
			return true
	return false
