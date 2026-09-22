class_name IsEngaged
extends RefCounted

#交战状态（基础规则）："若你与至少一名对手（包括玩家和NPC）一起位于一处会发生战斗的战场，
#则你处于交战状态，此时你无法进行常规移动。"
#判据分两层，都不写死战区名：
#  ① 战场要"会发生战斗"——取战区自己声明的 _score_need_win（魔术工房与侦察声明为 false）；
#  ② 与至少一名对手同处同一个战区即可。同一战场里的不同席位同样算"一起"
#     （规则里地利那段写明"摆放时会将其摆放于该位置一旁"，即同战场不同席位仍是一处）。
#已出局的玩家不再是"对手"，不计入。
#只判"此刻所站的位置"：规则明确"常规移动时可以经过不可发生战斗的地点或已发生交战的战场"，
#所以移动路径经过交战战场不算交战，只有起点在交战战场上才禁止移动。
#令咒等效果通过给玩家 ignore_engagement_for_move 来绕过本判定，那是效果自己的声明
func exec(player_id:int = -1) -> bool:

	var id = EffectManager.resolve_player_id(player_id)
	var loc = GetLocation.new().exec(id)
	if loc == null:
		return false
	var area := loc.get_from() as BaseMapArea
	if area == null or !area._score_need_win:
		return false
	for other in GameDataManager.get_active_player_ids():
		var other_id:int = int(other)
		if other_id == id:
			continue
		var other_data:Dictionary = GameDataManager.get_player_data(other_id)
		if bool(other_data.get("is_out", false)):
			continue
		var other_loc = GetLocation.new().exec(other_id)
		if other_loc != null and other_loc.get_from() == area:
			return true
	return false
