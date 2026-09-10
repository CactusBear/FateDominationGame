class_name GetPlayerDataValue
extends RefCounted

#取出player_data里任意键的原始值(对象、数组、bool、BaseNumber本身)。
#GetDataNumber只返回数字或容器长度，不能用来读true_name_released、location这类非数值字段。
func exec(key:String, player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !player_data.has(key):
		return null
	return player_data[key]
