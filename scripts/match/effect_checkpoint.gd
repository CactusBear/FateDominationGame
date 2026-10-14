extends "res://scripts/match/rule_checkpoint.gd"

const RandomStream = preload("res://scripts/match/rule_random.gd")
var root:BaseEffect
var random:Dictionary
var statics:Dictionary
# 不纳入规则对象图，避免票据归属反向遍历检查点自身。
var continuation_transactions:Dictionary
var transaction_bindings:Dictionary
var batch_transactions:Array
var continuation_queue:Array
# 规则等待资格只捕获声明值；展示消费者不属于可回滚对象图。
var broadcast_requires_confirm:bool
var transaction_id:int
var members:Dictionary = {}
var settled:bool = false
# 外壳原来源独立于通用图捕获，重新 capture 不能替换 RNG/日志/事务归属。
var _origin_context:Variant = null

func _source_is_current() -> bool:
	var source:Dictionary = Generation.validate_context(_origin_context)
	if not source.ok:
		error = "效果检查点来源无效: " + str(source.reason)
		return false
	return _effect_origin_is_current(root)

func _effect_origin_is_current(effect:BaseEffect) -> bool:
	if effect == null: return true
	var source:Dictionary = Generation.origin_of(effect)
	if not source.ok:
		error = "效果检查点对象来源无效: " + str(source.reason)
		return false
	if not is_same(source.context.token(), _origin_context.token()):
		error = "效果检查点对象来源无效: stale_session"
		return false
	return true

func audit(event:String, effect:BaseEffect = null, reason:String = "", parent:BaseEffect = null) -> bool:
	if not _source_is_current(): return false
	if effect == null: effect = root
	if not _effect_origin_is_current(effect) or not _effect_origin_is_current(parent): return false
	var source = GetEffSourceCard.new().exec(effect) if effect != null else null
	if source == null and effect != root and root != null: source = GetEffSourceCard.new().exec(root)
	var metadata:Dictionary = {"root_id":transaction_id, "effect_id":member_id(effect),
		"parent_id":member_id(parent if parent != null else root) if effect != root else 0,
		"player_id":effect._trigger_player_id if effect != null else -1,
		"card_id":source.get_instance_id() if source != null else 0,
		"reason":reason, "checkpoint_ready":ready}
	return MatchJournal.audit_event(event, metadata)

func member_id(effect:BaseEffect) -> int:
	if not _source_is_current() or not _effect_origin_is_current(effect): return 0
	if effect == null: return 0
	if not members.has(effect): members[effect] = MatchJournal.next_audit_identity()
	return members[effect]

func _init(effect:BaseEffect, capture_enabled:bool = true, context:Variant = null) -> void:
	root = effect
	_origin_context = context
	# 首个审计编号/运行状态读取前验原来源，缺参不能补当前票。
	if not _source_is_current(): return
	transaction_id = MatchJournal.next_audit_identity()
	member_id(root)
	var transactions:Dictionary = EffectManager.capture_transaction_state()
	transaction_bindings = transactions.transaction_bindings
	batch_transactions = transactions.batch_transactions
	continuation_queue = transactions.continuation_queue
	broadcast_requires_confirm = GameProgress.battle_broadcast_requires_confirm
	continuation_transactions = transactions.continuation_transactions
	random = RandomStream.snapshot()
	if not capture_enabled:
		error = "运行时回滚保护未启用"
		return
	if not random.get("known", false):
		error = "规则随机状态未知，不能完整回滚"
		return
	statics = {"journal":GameLog._journal, "trace":GameLog._trace,
		"log_context":[GameLog.current_round, GameLog.current_phase, GameLog.max_rounds],
		"restrictions":AbilityRestrictions.entries, "attributes":Attributes.custom_attributes,
		"data_root":LoadHelper.session_data_dir,
		"attacks":LoadAttack._attack_datas, "events":LoadEvent.events,
		"situations":LoadSituation.situations, "climax":LoadSituation.climax_situations,
		"spells":LoadCommandSpell.command_spells, "ai_attempts":DummyBot.capture_attempts()}
	capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, effect, statics],
		{GameProgress:["_battle_broadcast_consumer", "battle_broadcast_requires_confirm", "_battle_broadcast_batch_serial"],
		EffectManager:["_message_serial", "_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions",
		"_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]}, context)

func restore() -> bool:
	if not _source_is_current(): return false
	if not ready or not random.get("known", false):
		return false

	for key in ["seed", "state"]:
		if not random.get(key) is String or str(random[key].to_int()) != random[key]: return false
	if not super.restore():
		return false
	GameProgress.battle_broadcast_requires_confirm = broadcast_requires_confirm
	if not EffectManager.restore_transaction_state({"continuation_queue":continuation_queue,
		"transaction_bindings":transaction_bindings, "batch_transactions":batch_transactions,
		"continuation_transactions":continuation_transactions}):
		error = "回滚事务归属令牌无效"
		return false
	GameLog._journal = statics.journal
	GameLog._trace = statics.trace
	GameLog.current_round = statics.log_context[0]
	GameLog.current_phase = statics.log_context[1]
	GameLog.max_rounds = statics.log_context[2]
	LoadHelper.session_data_dir = statics.data_root
	AbilityRestrictions.entries = statics.restrictions
	Attributes.custom_attributes = statics.attributes
	LoadAttack._attack_datas = statics.attacks
	LoadEvent.events = statics.events
	LoadSituation.situations = statics.situations
	LoadSituation.climax_situations = statics.climax
	LoadCommandSpell.command_spells = statics.spells
	DummyBot.restore_attempts(statics.ai_attempts)
	if not RandomStream.restore(random):
		return false
	# 恢复规则等待，但旧输送确认令牌不能重新获得资格。
	GameProgress.renew_battle_broadcast_batch()
	return true
