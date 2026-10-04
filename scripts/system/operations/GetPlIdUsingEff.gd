class_name GetPlIdUsingEff
extends RefCounted

#取当前激活效果的归属玩家。效果入池时就记下了归属，所以直接读；
#归属缺失时退回到反查各玩家的self_effects
func exec():

	var eff = EffectManager.activating_eff
	if eff == null:
		return -1
	if eff._trigger_player_id != -1:
		return eff._trigger_player_id

	var pl_ids = GetAllPlayersId.new().exec() as Array
	for id in pl_ids:
		var pl_data = GameDataManager.get_player_data(id) as Dictionary
		var arr = pl_data["self_effects"] as Array
		if arr.has(eff):
			return id
	return -1
