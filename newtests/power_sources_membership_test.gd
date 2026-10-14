extends Node

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func power_facts(id:int) -> Array:
	return GameLog.query({"type":"power_source", "actor":id}, null)

func source_effect(owner, trigger_id:int) -> BaseEffect:
	var effect := BaseEffect.new("S14-member-source", [], 0, true, false)
	effect.from = owner
	effect._trigger_player_id = trigger_id
	return effect

func record_with_source(effect:BaseEffect, target_id:int, expected_tags:Array, expected_target:int, label:String) -> void:
	var before:Array = power_facts(target_id)
	EffectManager.activating_eff = effect
	PowerSources.record(target_id, "power", 1)
	EffectManager.activating_eff = null
	var after:Array = power_facts(target_id)
	check(after.size() == before.size() + 1, label + " fact retained")
	if after.size() == before.size() + 1:
		check(after.back().tags == expected_tags, label + " source tags retained")
		check(after.back().target == expected_target, label + " source target retained")

func run() -> void:
	var lifecycle:Dictionary = EffectManager.reset_runtime()
	GameLog.reset()
	GameData.player_data_library.clear()

	var owner_id:int = AddPlayer.new().exec(-2, [], {"player_name":"S14-owner"}, lifecycle.context)
	var other_id:int = AddPlayer.new().exec(-2, [], {"player_name":"S14-other"}, lifecycle.context)
	var unknown_id:int = 9514001
	while not GameDataManager.find_player_data(unknown_id).is_empty():
		unknown_id += 1
	var member_keys:Array = GameData.player_data_library.keys()
	var unknown_before:Array = power_facts(unknown_id)
	PowerSources.record(unknown_id, "power", 4)
	check(power_facts(unknown_id).size() == unknown_before.size(), "unknown record writes no fact")
	check(GameDataManager.find_player_data(unknown_id).is_empty(), "unknown record does not create member")
	check(GameData.player_data_library.keys() == member_keys, "unknown record leaves member table unchanged")

	var missing_card := BaseAttack.new("S14-missing-card", "", [], BaseNumber.new(0), BaseNumber.new(3))
	var missing_before:Array = power_facts(unknown_id)
	EditCardPower.new().exec(missing_card, BaseNumber.new(2), null, unknown_id)
	check(missing_card._power.number == 5, "real EditCardPower still edits missing card")
	check(power_facts(unknown_id).size() == missing_before.size(), "real EditCardPower writes no missing-member fact")
	check(GameDataManager.find_player_data(unknown_id).is_empty(), "real EditCardPower does not create member")

	var valid_card := BaseAttack.new("S14-valid-card", "", [], BaseNumber.new(0), BaseNumber.new(3))
	var valid_before:Array = power_facts(owner_id)
	EditCardPower.new().exec(valid_card, BaseNumber.new(2), null, owner_id)
	var valid_after:Array = power_facts(owner_id)
	check(valid_after.size() == valid_before.size() + 1, "valid EditCardPower still writes fact")
	if valid_after.size() == valid_before.size() + 1:
		check(valid_after.back().data.delta == 2 and valid_after.back().object == valid_card, "valid EditCardPower keeps delta and card")

	var self_owner := BaseAttack.new("S14-self-source", "", [], BaseNumber.new(0), BaseNumber.new(1))
	record_with_source(source_effect(self_owner, owner_id), owner_id, ["attack", "power", "self"], owner_id, "self source")
	var other_owner := BaseAttack.new("S14-other-source", "", [], BaseNumber.new(0), BaseNumber.new(1))
	record_with_source(source_effect(other_owner, other_id), owner_id, ["attack", "power", "others"], other_id, "other source")
	var event_owner := BaseEvent.new("S14-event-source", "")
	record_with_source(source_effect(event_owner, owner_id), owner_id, ["event", "power"], -1, "event source")

	print("RESULT ", JSON.stringify({"suite":"S14-member", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
