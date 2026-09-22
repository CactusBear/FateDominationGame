class_name IsTrueNameReleased
extends RefCounted

# 查询玩家当前真名状态；状态由真名解放/隐藏事实的最后一条日志决定。
# 不在此处写入状态，也不按历史上是否曾解放过来判断。
func exec(player_id:int = -1) -> bool:
	return ReleaseTrueName.is_released(EffectManager.resolve_player_id(player_id))
