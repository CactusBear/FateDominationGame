class_name Move
extends RefCounted

func exec(move_num:BaseNumber, player_id:int = -1, ignore_limit:bool = false, ignore_battle:bool = false):

	player_id = EffectManager.resolve_player_id(player_id)
	var player_data:Dictionary = GameDataManager.get_player_data(player_id)
	#交战状态（与对手同处一处会发生战斗的战场）不能常规移动：判据在查询里，
	#不写死战区名。只判当前所站位置——规则允许常规移动"经过"已发生交战的战场。
	#ignore_engagement_for_move(如言峰监督者中立、以及"以令咒移动")让玩家无视交战状态移动，
	#不需要调用方额外传ignore_battle
	var ignore_engagement = player_data["ignore_engagement_for_move"] as bool
	if !ignore_battle and !ignore_engagement and IsEngaged.new().exec(player_id):
		EffectManager.push_message("处于交战状态，无法移动", player_id)
		return
	var cost = MoveLocation.new().exec(move_num, player_id, ignore_limit)
	#目标落位失败时不扣费；MoveLocation 用 null 表示没有完成移动。
	if cost == null:
		return
	#MoveLocation 返回 BaseNumber，扣费 operation 需要同样的数值对象，不能直接做 int/Object 运算。
	EditMagic.new().exec(null, BaseNumber.new(0 - cost.number), player_id)
