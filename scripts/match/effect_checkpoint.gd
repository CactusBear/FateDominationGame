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
# 展示消费者身份影响等待资格，保存引用但不遍历 UI/录制器的文件句柄。
var broadcast_consumer
var transaction_id:int
var members:Dictionary = {}
var settled:bool = false

func audit(event:String, effect:BaseEffect = null, reason:String = "", parent:BaseEffect = null) -> bool:
	if effect == null: effect = root
	var source = GetEffSourceCard.new().exec(effect)
	if source == null and effect != root: source = GetEffSourceCard.new().exec(root)
	var metadata:Dictionary = {"root_id":transaction_id, "effect_id":member_id(effect),
		"parent_id":member_id(parent if parent != null else root) if effect != root else 0,
		"player_id":effect._trigger_player_id if effect != null else -1,
		"card_id":source.get_instance_id() if source != null else 0,
		"reason":reason, "checkpoint_ready":ready}
	return MatchJournal.audit_event(event, metadata)

func member_id(effect:BaseEffect) -> int:
	if effect == null: return 0
	if not members.has(effect): members[effect] = MatchJournal.next_audit_identity()
	return members[effect]

func _init(effect:BaseEffect, capture_enabled:bool = true) -> void:
	root = effect
	transaction_id = MatchJournal.next_audit_identity()
	member_id(root)
	transaction_bindings = EffectManager._guard_transactions.duplicate()
	batch_transactions = EffectManager._batch_transactions.duplicate()
	continuation_queue = EffectManager._guard_continuations.duplicate()
	broadcast_consumer = GameProgress._battle_broadcast_consumer
	continuation_transactions = EffectManager._continuation_transactions.duplicate()
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
		"spells":LoadCommandSpell.command_spells, "ai_scope":DummyBot._phase_attempt_scope,
		"ai_attempts":DummyBot._phase_attempted_effect_ids}
	capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, effect, statics],
		{GameProgress:["_battle_broadcast_consumer"],
		EffectManager:["_guard_continuations", "_guard_transactions", "_transaction_scope", "_continuation_transactions",
		"_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]})

func restore() -> bool:
	if not ready or not random.get("known", false):
		return false
	if broadcast_consumer != null and not is_instance_valid(broadcast_consumer):
		error = "回滚等待消费者已失效"
		return false
	for key in ["seed", "state"]:
		if not random.get(key) is String or str(random[key].to_int()) != random[key]: return false
	if not super.restore():
		return false
	GameProgress._battle_broadcast_consumer = broadcast_consumer
	EffectManager._guard_continuations = continuation_queue.duplicate()
	EffectManager._guard_transactions = transaction_bindings.duplicate()
	EffectManager._batch_transactions = batch_transactions.duplicate()
	EffectManager._continuation_transactions = continuation_transactions.duplicate()
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
	DummyBot._phase_attempt_scope = statics.ai_scope
	DummyBot._phase_attempted_effect_ids = statics.ai_attempts
	return RandomStream.restore(random)
