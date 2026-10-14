extends "res://tests/pending_board_power_test.gd"

# 原件只由独占 runner 在工程副本中逐字节冻结，不向生产引入私有读取。

var captured_value:Dictionary = {}
var captured_original:Dictionary = {}
var captured_after_mutation:Dictionary = {}
var captured_before:Dictionary = {}
var captured_after:Dictionary = {}

func announce(text:String, scope:int):
	var effect = BaseEffect.new("projection_fixture", ["projection"])
	effect._shown_name = text
	effect._trigger_player_id = scope
	effect._is_pure_passive = true
	EffectManager.register_effect(effect, scope)
	# 真实公开发动入口产生公告，不直写队列或调用私有入队函数。
	effect.edit_funcs([BaseFunc.new(Callable(EffectManager, "push_message"), ["fixture", -1])])
	EffectManager.activate_effect(effect)

func capture_pending():
	captured_value = EffectManager.pending_announcements_snapshot()
	captured_before = snapshot()
	for i in range(3):
		EffectManager.pending_announcements_snapshot()
	captured_value[0][0] = "仅修改副本"
	captured_value[0].append("副本追加")
	captured_value.erase(1)
	captured_value[99] = ["副本新键"]
	captured_after_mutation = EffectManager.pending_announcements_snapshot()
	captured_after = snapshot()

func announce_batch(rows:Array):
	var batch = BaseEffect.new("", ["projection"], 0, true)
	batch._trigger_player_id = 0
	EffectManager.register_effect(batch, 0)
	var funcs:Array = []
	for row in rows:
		funcs.append(BaseFunc.new(Callable(self, "announce"), [row[0], row[1]]))
	batch.edit_funcs(funcs)
	var capture = BaseEffect.new("", ["projection"], 100, true)
	capture._trigger_player_id = 0
	EffectManager.register_effect(capture, 0)
	capture.edit_funcs([BaseFunc.new(Callable(self, "capture_pending"), [])])
	TimePointChecker.dynamic_time_point(["projection"], 0)

func test_engine():
	# 完整保留原场景的 UI、规则与纯度断言，在同一专项追加快照契约。
	super.test_engine()
	test_announcement_snapshot()

func test_announcement_snapshot():
	EffectManager.reset_runtime()
	print("ACTUAL_USER_PATH ", OS.get_user_data_dir())
	check(EffectManager.has_method("pending_announcements_snapshot"), "public pending announcement snapshot exists")
	if not EffectManager.has_method("pending_announcements_snapshot"):
		return
	var historical_empty:Dictionary = snapshot()
	check(EffectManager.call("pending_announcements_snapshot") == {}, "empty queue snapshot")
	check(snapshot() == historical_empty, "empty full consumer snapshot remains equal to frozen baseline")
	announce_batch([["甲", 0], ["乙", 0], ["丙", 1], ["丁", 1]])
	var expected:Dictionary = {0:["远坂凛：甲", "远坂凛：乙"], 1:["间桐慎二：丙", "间桐慎二：丁"]}
	var historical:Dictionary = captured_before
	var value:Dictionary = historical.announcements.duplicate(true)
	check(value.keys() == expected.keys(), "all scope keys and insertion order preserved")
	for scope in expected:
		check(value.get(scope) == expected[scope], "bucket content and nested array order preserved " + str(scope))
	check(value == historical.announcements, "nonempty projection equals frozen consumer snapshot field for field")
	check(captured_after.keys() == historical.keys(), "full consumer snapshot keys and order equal frozen baseline")
	for field in historical:
		check(captured_after.get(field) == historical[field], "consumer snapshot field equals frozen baseline: " + str(field))
	check(captured_after == historical, "nonempty full consumer snapshot equals frozen baseline")
	check(captured_after_mutation == historical.announcements, "returned outer dictionary and inner arrays do not alias engine queue")
	# 与原场景相同的完整等式；负向只在独占副本中反转公告数组顺序。
	var before:Dictionary = captured_before
	var after:Dictionary = captured_after
	# ISOLATED_MUTATION_ANCHOR
	var other_fields:Dictionary = after.duplicate(true)
	other_fields.announcements = before.announcements
	check(other_fields == before, "controlled observation leaves all non-announcement fields unchanged")
	check(after == before, "repeated engine queries do not mutate cards resources logs or messages")

