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


func exec(card, player_id:int = -1, context:Variant = null) -> bool:
	if card == null or !(card is BaseCard):
		return false
	#没有词条就没有任何写入，属于合法 no-op；来源门只守真正会产生规则动作的分支。
	if (card as BaseCard)._keywords.is_empty():
		return true
	#缺省只继承已验证函数帧；显式来源沿嵌套调用传递，不在消费口补票。
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context, card):
		return false
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	player_id = resolved.id
	if not GameData.player_data_library.has(player_id):
		return false
	for keyword in (card as BaseCard)._keywords:
		if not apply(str(keyword), player_id, context):
			return false
	return true


#每个词条对应一个已有的单一职责 operation，这里只负责选谁。
#新增词条时在这里加一个分支，不改任何已有 operation
func apply(keyword:String, player_id:int = -1, context:Variant = null) -> bool:
	#直接 apply 同样只继承已验帧，不从当前会话或卡牌领取来源。
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	player_id = resolved.id
	if not GameData.player_data_library.has(player_id):
		return false
	match keyword:
		TRUE_NAME_RELEASE:
			#已解放是合法 no-op；不能把它与来源拒绝一并吞掉。
			if ReleaseTrueName.is_released(player_id):
				return true
			var released = preload("res://scripts/system/operation_router.gd").exec_registered("release_true_name", [player_id, ReleaseTrueName.DEFAULT_SHOWN_AREAS, context], context)
			return typeof(released) == TYPE_BOOL and released
	return true
