class_name DefeatBuff
extends BaseBuff

const ROUTER = preload("res://scripts/system/operation_router.gd")


#【败北】是一种持续到回合结束的系统buff，其全部效果由挂在_effects里的BaseEffect表达：
#1. ExcludedFromBattleWinEffect：无法赢得战斗，也不能阻止其他玩家获胜。
#2. CannotPlayCardsEffect：无法打出卡牌(不影响已激活的牌和能力的其他使用)。
#规则位置(BattleResolver/PlayAttack/PlaySkill)通过PlayerBuffsHaveEffect按效果名查询，
#不针对DefeatBuff类型做任何专门判断。
#
#规则：你可以同时具有多层【败北】状态，所以apply不做去重，每次调用叠加一层。
#is_battle_lose/is_battle_win等战斗胜负标记由BattleResolver自行管理，本buff不触碰，
#以便特殊效果赋予的【败北】不会被误当成常规战斗失败。

const DEFEAT_BUFF_NAME:String = "defeat"


func _init():
	#BaseBuff._init只需要name和img；败北buff不需要图片
	super(DEFEAT_BUFF_NAME, "")
	var excluded = ExcludedFromBattleWinEffect.new()
	excluded.from = self
	add_buff_effect(excluded)
	var cannot_play = CannotPlayCardsEffect.new()
	cannot_play.from = self
	add_buff_effect(cannot_play)


# 只由新 runtime 工厂保存原输入；new() 仍是未绑定模板，不捕获全局当前票。
var _creation_context:SessionContext = null


# 可信新建边界复用 LoadHelper 的 bind_origin + bind_runtime_context ABI。
# 缺省仅继承真实已验函数帧；绝不给模板或旧 runtime 对象重签来源。
static func create_runtime(context:Variant = null) -> DefeatBuff:
	context = RegisterObjectEffects.captured_context(context)
	if not RegisterObjectEffects.source_is_current(context):
		return null
	var defeat := DefeatBuff.new()
	var bound:Dictionary = SessionGeneration.bind_origin(defeat, context.token(), context.origin())
	if not bound.ok:
		defeat._discard_uninstalled_graph()
		return null
	for effect:BaseEffect in defeat._effects:
		var child:Dictionary = SessionGeneration.bind_origin(effect, context.token(), context.origin())
		if not child.ok or not effect.bind_runtime_context(child.context):
			defeat._discard_uninstalled_graph()
			return null
	defeat._creation_context = context
	return defeat


# 仅清理本工厂尚未安装的新图；不是撤销已安装 buff 的第二套 undo。
func _discard_uninstalled_graph() -> void:
	for effect:BaseEffect in _effects:
		effect.del()
	del()


# 给指定玩家附加一层【败北】，可叠加；失败绝不返回未安装对象冒充成功。
static func apply(player_id:int = GameData.player_id, context:Variant = null) -> DefeatBuff:
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return null
	player_id = resolved.id
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return null
	var buffs:Array = player_data["buffs"]
	var defeat:DefeatBuff = create_runtime(context)
	if defeat == null:
		return null
	# ManageBuff 不消费登记 bool；先在发布前消费真实登记回执。
	# 同步安装中的重复登记由既有 identity 幂等门处理，不再签发来源/归属。
	if not RegisterObjectEffects.can_register_object(defeat, player_id, context) or not EffectManager.register_effects(defeat._effects, player_id):
		defeat._discard_uninstalled_graph()
		return null
	if not RegisterObjectEffects.source_is_current(context, defeat) or not is_same(player_data, GameDataManager.find_player_data(player_id)) or not is_same(buffs, player_data.get("buffs")):
		defeat._discard_uninstalled_graph()
		return null
	var installed:Variant = ROUTER.exec_registered("manage_buff", [defeat, player_id, true, context], context)
	if installed != true:
		# 消费口同步时点造成的已发布失效须由原恢复门处理，不私造 undo。
		if not buffs.has(defeat):
			defeat._discard_uninstalled_graph()
		return null
	return defeat


# 移除指定玩家的所有层；缺省仅继承已验函数帧，不领取当前票。
static func remove(player_id:int = GameData.player_id, context:Variant = null) -> bool:
	context = RegisterObjectEffects.captured_context(context)
	var resolved:Dictionary = RegisterObjectEffects.resolved_player_id(player_id, context)
	if not resolved.ok:
		return false
	player_id = resolved.id
	var player_data:Dictionary = GameDataManager.find_player_data(player_id)
	if player_data.is_empty():
		return false
	var buffs:Array = player_data["buffs"]
	var layers:Array = []
	# 整个目标先验来源/原所有者；任一层拒绝前都不删除任何效果。
	for buff in buffs:
		if buff is DefeatBuff:
			if not RegisterObjectEffects.can_register_object(buff, player_id, context):
				return false
			layers.append(buff)
	# 保留旧生命周期的后加层先摘除顺序。
	for index in range(layers.size() - 1, -1, -1):
		var defeat:DefeatBuff = layers[index]
		if not is_same(player_data, GameDataManager.find_player_data(player_id)) or not is_same(buffs, player_data.get("buffs")):
			return false
		if ROUTER.exec_registered("manage_buff", [defeat, player_id, false, context], context) != true:
			return false
		# 只有真实摘除回执后才删除原图；失败不留下“buff 在，效果已删”。
		defeat._discard_uninstalled_graph()
	return true


# 回合尾可以没有函数帧：仅消费已安装 buff 自己保存的真实原来源。
# 子效果既有登记门同时校验原玩家 Dictionary identity；不取 current/derive/bind。
# 普通 remove 的无帧调用仍拒绝；此路径不授予创建新对象或运行任意函数的资格。
static func clear_all(context:Variant = null) -> bool:
	var source:Variant = RegisterObjectEffects.captured_context(context)
	if context != null and not RegisterObjectEffects.source_is_current(source):
		return false
	var targets:Array = []
	for id in GameData.player_data_library.keys():
		var player_data:Dictionary = GameDataManager.find_player_data(id)
		var buffs:Array = player_data.get("buffs", [])
		var original:Variant = source
		var has_layers:bool = false
		for buff in buffs:
			if buff is DefeatBuff:
				has_layers = true
				if original == null:
					original = buff._creation_context
				if not RegisterObjectEffects.can_register_object(buff, id, original):
					return false
		if has_layers:
			targets.append({"id":id, "owner":player_data, "buffs":buffs, "context":original})
	# 所有目标先验完才摘除首层；同步时点后仍复验保活的原成员/容器。
	for target:Dictionary in targets:
		if not is_same(target.owner, GameDataManager.find_player_data(target.id)) or not is_same(target.buffs, target.owner.get("buffs")):
			return false
		if not remove(target.id, target.context):
			return false
	return true


#玩家当前的【败北】层数
static func get_defeat_count(player_id:int = GameData.player_id) -> int:
	var player_data = GameDataManager.get_player_data(player_id) as Dictionary
	var count:int = 0
	for buff in player_data["buffs"]:
		if buff is DefeatBuff and buff._is_active:
			count += 1
	return count


static func is_defeated(player_id:int = GameData.player_id) -> bool:
	return get_defeat_count(player_id) > 0
