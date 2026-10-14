extends Node

# 挑牌字段（select_cards）编辑器测试：打开小次郎 JSON，定位到「一之太刀」第一条效果的选项，
# 检查控件存在、改最多张后 JSON 里 select_cards.max 跟着变，并验证候选积木串的编码往返与原数据等价。
const Codec = preload("res://json_maker/json_codec.gd")
const SASAKI := "res://data/servants/00006_sasaki_kojirou/00006_sasaki_kojirou.json"

var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	# 找到小次郎所在的卡种并打开它
	var found := false
	for k in ui.kind_button.item_count:
		ui._select_kind(k)
		for i in ui.file_list.item_count:
			if str(ui.file_list.get_item_metadata(i)).replace("\\", "/").ends_with("00006_sasaki_kojirou.json"):
				ui.open_path(str(ui.file_list.get_item_metadata(i)))
				found = true
		if found:
			break
	check(found, "sasaki json opened in editor")
	if not found:
		_finish()
		return
	var original = ui.maker.read_json(SASAKI)
	var orig_cands = original.specials.SKILLS[0].effects[1].options[0].select_cards.candidates
	# 定位到「一之太刀」本体（技能页），再切到它的效果
	var entry := -1
	for e in ui._sub_entries().size():
		if ui._sub_entries()[e].path == ["specials", "SKILLS", 0]:
			entry = e
	check(entry >= 0, "一之太刀 skill entry found")
	ui._focus_entry(entry)
	await get_tree().process_frame
	# 第 1 条效果（effects[1]）的选项最少 1 张、最多 1 张；效果 2 的选项最少 0，所以用最少=1 定位
	var min_spin = null
	for s in ui.script_box.find_children("SelectCardsMin", "SpinBox", true, false):
		if s.value == 1.0:
			min_spin = s
			break
	check(min_spin != null, "挑牌控件 SelectCardsMin 存在")
	if min_spin == null:
		_finish()
		return
	var max_spin = min_spin.get_parent().find_child("SelectCardsMax", true, false)
	check(max_spin != null and float(max_spin.value) == 1.0, "最多张控件存在且初值为 1")
	check(ui.script_box.find_children("SelectCardsRemove", "Button", true, false).size() >= 1, "已有挑牌时显示「不挑牌了」按钮")
	check(ui.script_box.find_children("SelectCardsAdd", "Button", true, false).is_empty(), "已有挑牌时不显示「让玩家挑牌」按钮")
	# 改最多张 → JSON 里的 max 要变
	max_spin.value = 3
	await get_tree().process_frame
	ui._commit()
	var sel:Dictionary = ui.data.specials.SKILLS[0].effects[1].options[0].select_cards
	check(int(sel.max) == 3, "改 max 后 JSON select_cards.max == 3 (" + str(sel.max) + ")")
	check(int(sel.min) == 1, "min 未被改动")
	# 不改动时候选牌不变：整串积木解码再编码，与原数据等价
	ui._commit()
	var cands:Array = sel.candidates
	check(Codec.same(cands, orig_cands), "候选牌 candidates 提交后与原数据等价")
	var rt:Array = ui.codec.encode_effect_list(ui.codec.decode_list(orig_cands))
	check(Codec.same(rt, orig_cands), "候选牌编码往返（decode→encode）与原数据等价")
	# 候选积木串就是 field_stack 缓存的那一份：界面能拿到同一数组
	# 注意：积木是折叠后的树，块数不等于原始操作数，所以按编码结果比较
	check(Codec.same(ui.codec.encode_effect_list(ui.field_stack(sel, "candidates")), orig_cands), "field_stack 积木编码后与原候选串等价")
	_finish()


func _finish() -> void:
	print("RESULT checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
