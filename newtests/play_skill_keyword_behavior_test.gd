extends Node

# B20 行为探针：只经 PlaySkill 触发词条，不直接调用词条/真名 operation。
# JSON 公开加载入口声明词条；断言只查公开玩家数据与真名业务事实。
var failures:Array = []
var checks:int = 0

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("CHECK ", label, " ", ok)

func _ready() -> void:
	call_deferred("run")

func reset_fixture() -> void:
	EffectManager.reset_runtime()
	GameLog.reset()
	GameData.effects.clear()
	GameData.player_data_library.clear()
	GameProgress.reset_progress()
	GameLog.set_context(1, "action")
	for id in range(2):
		var data:Dictionary = GameData.new_player_data()
		data["is_out"] = false
		(data["magic"] as BaseNumber).set_num(BaseNumber.new(30))
		GameData.player_data_library[id] = data

func load_skill(name:String, keywords:Array) -> BaseSkill:
	var zero:Dictionary = {"number":0, "can_change":true, "is_pure_number":true}
	var cards:Array = LoadGame.load_skills([{
		"skill_name":name, "skill_card_img":"", "attributes":[],
		"cost":zero.duplicate(), "power":zero.duplicate(),
		"ignore_limit":false, "effects":[], "keywords":keywords
	}], "", null)
	return cards[0] as BaseSkill

func run_case(with_keyword:bool) -> void:
	reset_fixture()
	var label:String = "keyword" if with_keyword else "plain control"
	var keywords:Array = [ApplyCardKeywords.TRUE_NAME_RELEASE] if with_keyword else []
	var card:BaseSkill = load_skill("b20_played_skill", keywords)
	var held:BaseSkill = load_skill("b20_held_skill", [])
	card.set_concealed(true)
	held.set_concealed(true)
	var owner:Dictionary = GameDataManager.get_player_data(1)
	owner["servant_skills"] = [card, held]
	check(card.has_keyword(ApplyCardKeywords.TRUE_NAME_RELEASE) == with_keyword,
		label + " fixture declares exactly the intended keyword")
	check(not ReleaseTrueName.is_released(1)
		and GameLog.query({"type":"true_name_release", "actor":1}, null).is_empty(),
		label + " does not release before PlaySkill")
	# ignore_limit 只解除主动效果上下文门槛；不跳过真实付款/入场/词条站点。
	var accepted:bool = bool(PlaySkill.new().exec(card, 1, true))
	check(accepted, label + " PlaySkill returns true")
	check((owner["played_cards"] as Array).size() == 1
		and owner["played_cards"][0] == card,
		label + " PlaySkill places the original skill object")
	var releases:Array = GameLog.query({"type":"true_name_release", "actor":1}, null)
	var shown_count:int = int(releases[0].get("data", {}).get("shown_count", -1)) if releases.size() == 1 else -1
	if with_keyword:
		check(ReleaseTrueName.is_released(1) and releases.size() == 1 and shown_count == 2,
			"PlaySkill keyword releases the owner and reveals both held skills")
	else:
		check(not ReleaseTrueName.is_released(1) and releases.is_empty(),
			"PlaySkill without the keyword leaves the owner unreleased")
	check(not ReleaseTrueName.is_released(0)
		and GameLog.query({"type":"true_name_release", "actor":0}, null).is_empty(),
		label + " does not release a different player")
	print("OBSERVATION ", JSON.stringify({"case":label, "accepted":accepted,
		"released":ReleaseTrueName.is_released(1), "release_count":releases.size(),
		"shown_count":shown_count, "played_count":owner["played_cards"].size()}))

func run() -> void:
	run_case(true)
	run_case(false)
	print("RESULT play_skill_keyword_behavior checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
