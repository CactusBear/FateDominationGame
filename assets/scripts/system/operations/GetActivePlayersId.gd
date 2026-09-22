class_name GetActivePlayersId
extends RefCounted

#按当前行动顺位返回仍未出局的玩家；顺位来源而非字典键保证结果可用于规则比较。
func exec() -> Array:
	return GameDataManager.get_active_player_ids()
