class_name EditDataNumber
extends RefCounted

#通用BaseNumber字段编辑器：player_data里所有BaseNumber类型的字段(play_limit、
#total_power_bonus、attack_cost_discount、move_cost_discount_from_workshop、
#command_spell_count等)都可以用同一个operation改写，不需要为每个字段各写一个
#Set/EditXxx.gd。用法与EditMagic/EditScore/EditLives一致：set_num覆盖，vary_num叠加
func exec(key:String, set_num:BaseNumber = null, vary_num:BaseNumber = BaseNumber.new(0), player_id:int = -1):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	if !(player_data.get(key) is BaseNumber):
		return
	var num = player_data[key] as BaseNumber
	if set_num != null:
		num.set_num(set_num)
	num.add(vary_num)
