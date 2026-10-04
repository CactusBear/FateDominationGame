class_name ApplyCardKeywords
extends RefCounted

#结算一张牌进场时其词条带来的规则行为。
#词条是"一类牌共有的规则"（如【真名解放】：使用带此词条的牌后立即真名解放），
#由卡在 JSON 的 keywords 里显式声明，规则本体只写在这里一份——
#不去扫卡面文案里的【xx】字样（文案是给人看的，措辞一改行为就跟着错），
#也不必在每张带词条的牌里把同一段规则复制一遍。
#
#单一职责：只做"词条 -> 规则动作"的派发，不管牌怎么进场、也不判断能不能打出。
#未识别的词条不做任何事（那类词条只是卡面说明），所以数据里加新词条不会报错，
#引擎支持之后自动生效。

#词条名。声明在这里而不是散落在各处字符串，避免数据与代码拼写不一致
const TRUE_NAME_RELEASE := "true_name_release"


func exec(card, player_id:int = -1) -> void:
	if card == null or !(card is BaseCard):
		return
	player_id = EffectManager.resolve_player_id(player_id)
	if player_id == -1:
		return
	for keyword in (card as BaseCard)._keywords:
		apply(str(keyword), player_id)


#每个词条对应一个已有的单一职责 operation，这里只负责选谁。
#新增词条时在这里加一个分支，不改任何已有 operation
func apply(keyword:String, player_id:int = -1) -> void:
	player_id = EffectManager.resolve_player_id(player_id)
	if player_id == -1:
		return
	match keyword:
		TRUE_NAME_RELEASE:
			#规则：使用带【真名解放】词条的牌后，立即展示从者概览卡与所有技能牌，
			#并处于【真名解放】状态。已解放时 ReleaseTrueName 自己会跳过，这里不重复判断
			ReleaseTrueName.new().exec(player_id)
