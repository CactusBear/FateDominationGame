extends "res://scripts/match/rule_checkpoint.gd"

const RandomStream = preload("res://scripts/match/rule_random.gd")
var root:BaseEffect
var random:Dictionary
var statics:Dictionary

func _init(effect:BaseEffect) -> void:
	root = effect
	random = RandomStream.snapshot()
	if not random.get("known", false):
		error = "规则随机状态未知，不能完整回滚"
		return
	statics = {"journal":GameLog._journal, "trace":GameLog._trace,
		"log_context":[GameLog.current_round, GameLog.current_phase, GameLog.max_rounds],
		"restrictions":AbilityRestrictions.entries, "attributes":Attributes.custom_attributes,
		"attacks":LoadAttack._attack_datas, "events":LoadEvent.events,
		"situations":LoadSituation.situations, "climax":LoadSituation.climax_situations,
		"spells":LoadCommandSpell.command_spells, "ai_scope":DummyBot._phase_attempt_scope,
		"ai_attempts":DummyBot._phase_attempted_effect_ids}
	capture([GameData, GameProgress, MapData, TimePointChecker, GameStart, EffectManager, effect, statics],
		{EffectManager:["_guard_transactions", "_transaction_scope", "_continuation_transactions",
		"_batch_transactions", "_runtime_guard", "_guard_run", "_guard_frames", "_resume_frames"]})

func restore() -> bool:
	if not ready or not random.get("known", false) or not super.restore():
		return false
	GameLog._journal = statics.journal
	GameLog._trace = statics.trace
	GameLog.current_round = statics.log_context[0]
	GameLog.current_phase = statics.log_context[1]
	GameLog.max_rounds = statics.log_context[2]
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
