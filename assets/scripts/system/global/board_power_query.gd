class_name BoardPowerQuery
extends RefCounted

#Pure evaluation scope for explicitly declared board power expressions.
#Never activates effects, changes global context, writes cards, or records logs.
#Only the audited read-only operations below are accepted; unknown descriptors fail closed.
const READERS := {
	"get_property": preload("res://assets/scripts/system/operations/GetProperty.gd"),
	"get_map_area_by_name": preload("res://assets/scripts/system/operations/GetMapAreaByName.gd"),
	"get_players_in_map_area": preload("res://assets/scripts/system/operations/GetPlayersInMapArea.gd"),
	"merge_arrays": preload("res://assets/scripts/system/operations/MergeArrays.gd"),
	"calculate_number": preload("res://assets/scripts/system/operations/CalculateNumber.gd"),
	"match_func": preload("res://assets/scripts/system/operations/MatchFunc.gd"),
	"if_func": preload("res://assets/scripts/system/operations/IfFunc.gd"),
	"if_else_func": preload("res://assets/scripts/system/operations/IfElseFunc.gd"),
	"is_null": preload("res://assets/scripts/system/operations/IsNull.gd"),
	"not_func": preload("res://assets/scripts/system/operations/NotFunc.gd"),
	"and_func": preload("res://assets/scripts/system/operations/AndFunc.gd"),
	"get_rank_by_data_number": preload("res://assets/scripts/system/operations/GetRankByDataNumber.gd"),
	"get_shared_attack_attribute": preload("res://assets/scripts/system/operations/GetSharedAttackAttribute.gd"),
	"get_player_played_cards": preload("res://assets/scripts/system/operations/GetPlayerPlayedCards.gd"),
	"get_player_location_benefit": preload("res://assets/scripts/system/operations/GetPlayerLocationBenefit.gd"),
	"get_attack_printed_power": preload("res://assets/scripts/system/operations/GetAttackPrintedPower.gd"),
}
var variables:Dictionary = {}
var effect:BaseEffect
var player_id:int
var contribution:int = 0
var card_values:Dictionary = {}
var played_cards_view:Array = []
var concealed_overrides:Dictionary = {}

static func total(id:int, preview_cards:Array = [], preview_hidden:Array = []) -> int:
	if not GameData.player_data_library.has(id): return 0
	#Keep object identity but never append to the real zone or change card concealment.
	var played:Array = []
	for card in GameData.player_data_library[id].played_cards:
		if not played.has(card): played.append(card)
	var hidden:Dictionary = {}
	for index in range(preview_cards.size()):
		var card = preview_cards[index]
		if not card is BaseHandCard or played.has(card): continue
		played.append(card)
		hidden[card] = bool(preview_hidden[index]) if index < preview_hidden.size() else card._is_concealed
	var cards:Array = []
	if MapData.active_situation != null: cards.append(MapData.active_situation)
	for area in MapData.areas: cards.append_array(area._events)
	var result:int = 0
	var values:Dictionary = {}
	for card in cards:
		if card._is_concealed: continue
		for eff in card._effects:
			if eff._power_query.is_empty(): continue
			var query = BoardPowerQuery.new()
			query.effect = eff
			query.player_id = id
			query.card_values = values
			query.played_cards_view = played
			query.concealed_overrides = hidden
			query.evaluate(eff._power_query)
			result += query.contribution
	return result

func counts_power(card) -> bool:
	if not card is BaseHandCard or not played_cards_view.has(card): return false
	return CardCountsPower.new().counts_when_played(card, bool(concealed_overrides.get(card, card._is_concealed)), player_id)

func shared_attack_attribute():
	var attacks:Array = []
	for card in played_cards_view:
		if card is BaseAttack and counts_power(card): attacks.append(card)
	return GetSharedAttackAttribute.from_cards(attacks)

func evaluate(descriptors:Array):
	for desc in descriptors: evaluate_one(desc)

func resolve(value) -> Array:
	if value is Dictionary:
		if value.has("self_var"):
			var index:int = int(value.self_var)
			return [variables.has(index), variables.get(index)]
		if value.has("number_index"):
			var index:int = int(value.number_index)
			return [index >= 0 and index < effect.numbers.size(), effect.numbers[index] if index >= 0 and index < effect.numbers.size() else null]
	return [true, value]

func evaluate_one(desc:Dictionary):
	var condition = resolve(desc.get("condition", true))
	if not condition[0] or not bool(number(condition[1]) if condition[1] is BaseNumber else condition[1]): return
	var name:String = str(desc.get("func_name", ""))
	var params:Array = []
	for raw in desc.get("parameters", []):
		var resolved = resolve(raw)
		if not resolved[0]: return
		params.append(resolved[1])
	var result = null
	if name == "foreach_func":
		if params.size() < 2 or not params[1] is Array: return
		var slot:int = int(params[2]) if params.size() > 2 else 0
		var body:Array = params[0] if params[0] is Array else [params[0]]
		for item in params[1]:
			for entry in body:
				var nested:Dictionary = entry.duplicate(true)
				var args:Array = nested.get("parameters", [])
				while args.size() <= slot: args.append(null)
				if args[slot] == null: args[slot] = item
				nested["parameters"] = args
				evaluate_one(nested)
	elif name == "store_value":
		result = params[0] if not params.is_empty() else null
	elif name == "get_eff_source_card":
		result = effect.from.get_ref() if effect.from is WeakRef else effect.from
	elif name == "log_exists":
		if params.is_empty() or params[0] == null: return
		var filter:Dictionary = params[1].duplicate(true) if params.size() > 1 else {}
		filter["actor"] = int(params[0])
		result = not GameLog.query(filter, params[2] if params.size() > 2 else 0, 1).is_empty()
	elif name == "power_contribution":
		if params.size() > 2 and params[2] != null and int(params[2]) == player_id:
			contribution += int(number(params[1]))
	elif name == "attack_power_contribution":
		if params.size() < 3 or params[2] == null or int(params[2]) != player_id: return
		for card in played_cards_view:
			if not card is BaseHandCard or not counts_power(card): continue
			if params.size() > 3 and params[3] != null and params[3] != card: continue
			if params.size() > 4 and params[4] == card: continue
			var required_category: String = str(params[5]) if params.size() > 5 else ""
			var min_power: int = int(params[6]) if params.size() > 6 else -1
			if required_category != "" and str(card.get("_category")) != required_category: continue
			if min_power >= 0 and (card._power as BaseNumber).number < min_power: continue
			var attrs: Array = params[0] if params[0] is Array else []
			if not attrs.is_empty():
				var matched: bool = false
				for attr in attrs:
					if card._attributes.has(attr):
						matched = true
						break
				if not matched: continue
			contribution += int(number(params[1]))
	elif name == "card_power_contribution":
		if params.size() < 4 or params[3] == null or int(params[3]) != player_id: return
		var card = params[0]
		if not card is BaseAttack or not counts_power(card): return
		if not card._power.can_change: return
		var old:int = int(card_values.get(card, card._power.number))
		var current:int = int(number(params[2])) if params[2] != null else old
		current += int(number(params[1]))
		card_values[card] = current
		contribution += current - old
	elif READERS.has(name):
		#Malformed legacy foreach slots stay malformed rather than silently changing targets.
		#Do not call player readers with null/-1: those can create fallback player state.
		var player_slot:int = 1 if name == "get_rank_by_data_number" else 0
		if name in ["get_rank_by_data_number", "get_shared_attack_attribute", "get_player_played_cards", "get_player_location_benefit"]:
			if params.size() <= player_slot or params[player_slot] == null or int(params[player_slot]) < 0: return
			if not GameData.player_data_library.has(int(params[player_slot])): return
		if name == "get_player_played_cards" and int(params[0]) == player_id:
			result = played_cards_view.duplicate()
		elif name == "get_shared_attack_attribute" and int(params[0]) == player_id:
			result = shared_attack_attribute()
		else:
			var reader = READERS[name].new()
			var count:int = 0
			for method in reader.get_method_list():
				if method.name == "exec": count = method.args.size(); break
			#Foreach pads every descriptor, while native Callable ignores no surplus arguments.
			params.resize(mini(params.size(), count))
			result = reader.exec.callv(params)
	else:
		return
	var target:int = int(desc.get("var_index", -1))
	if target >= 0: variables[target] = result

static func number(value):
	return value.number if value is BaseNumber else value
