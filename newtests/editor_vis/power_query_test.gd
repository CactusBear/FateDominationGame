extends Node

# 威力计算积木串：没有 power_query 的效果能新建；已有的能删除；保存往返正确。
const Codec = preload("res://json_maker/json_codec.gd")
const EVENT_WITH := "res://data/events/origin/sneak_attack/sneak_attack.json"
const ATTACK_WITHOUT := "res://data/attacks/basic/luck/luck.json"
const SCRATCH := "E:/scratch/editor-vis/power_query_roundtrip.json"

var checks := 0
var failures:Array = []


func check(ok:bool, text:String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("CHECK ", text, " ", ok)


func _ready() -> void:
	call_deferred("run")


func _power_button(root:Node) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if str(b.text) == "＋ 加威力计算":
			return b
	return null


func _power_stack_drop(root:Node) -> Control:
	for c in root.find_children("*", "Control", true, false):
		if c.has_meta("drop") and str(c.get_meta("drop").get("context", "")) == "power_query":
			return c
	return null


func run() -> void:
	var ui = load("res://json_maker/json_maker.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame

	# --- 1. 已有 power_query 的局势卡：界面显示「计算合计威力时」，删除后 JSON 也没了 ---
	ui.open_path(EVENT_WITH)
	ui._paint_scripts()
	await get_tree().process_frame
	check(ui.effects_view.size() >= 1 and ui.effects_view[0].lists.has("power_query"), "event card decodes power_query")
	check(ui.script_box.find_child("DeletePowerQuery", true, false) != null, "existing power query shows delete")
	check(_power_button(ui.script_box) == null, "existing power query hides add button")
	ui.script_box.find_child("DeletePowerQuery", true, false).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	ui._commit()
	check(not ui.data.effects[0].has("power_query"), "delete removes power_query from JSON")
	check(not ui.effects_view[0].lists.has("power_query"), "delete removes power_query from model")
	check(_power_button(ui.script_box) != null, "after delete the add button comes back")

	# --- 2. 没有 power_query 的攻击牌效果：新建空数组，再拖一块积木进去 ---
	ui.open_path(ATTACK_WITHOUT)
	ui._paint_scripts()
	await get_tree().process_frame
	var eff_before:Dictionary = ui.data.effects[0]
	check(not eff_before.has("power_query"), "attack effect starts without power_query")
	var add := _power_button(ui.script_box)
	check(add != null, "add button shown for effect without power_query")
	if add != null:
		add.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.effects_view[0].lists.has("power_query") and ui.effects_view[0].lists.power_query.is_empty(), "add creates empty power_query list")
	check(_power_button(ui.script_box) == null, "add button hidden after adding")
	ui._commit()
	check(ui.data.effects[0].get("power_query") is Array and ui.data.effects[0].power_query.is_empty(), "empty power_query written to JSON")
	var zone = _power_stack_drop(ui.script_box)
	check(zone != null, "power query stack shows a drop zone")
	var payload := {"new": {"kind": "op", "func": "get_eff_source_card"}}
	if zone != null:
		ui._drop_on(Vector2.ZERO, payload, zone)
	await get_tree().process_frame
	await get_tree().process_frame
	ui._commit()
	var pq:Array = ui.data.effects[0].get("power_query", [])
	check(pq.size() == 1 and str(pq[0].get("func_name", "")) == "get_eff_source_card", "block dropped into power_query " + JSON.stringify(pq))

	# --- 3. 保存往返：写到暂存文件，读回后与内存一致；且 power_query 位置不丢 ---
	var text:String = ui.maker.export_text(ui.data, ui.style)
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var back = ui.maker.read_json(SCRATCH)
	check(back is Dictionary and Codec.same(back, ui.data), "save round-trip equals in-memory data")
	check(back is Dictionary and back.effects[0].get("power_query") is Array and back.effects[0].power_query.size() == 1, "round-trip keeps power_query block")

	# 删除后保存再读回，不再有 power_query
	ui.open_path(ATTACK_WITHOUT)
	ui._paint_scripts()
	await get_tree().process_frame
	var add2 := _power_button(ui.script_box)
	if add2 != null:
		add2.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	var del:Node = ui.script_box.find_child("DeletePowerQuery", true, false)
	check(del != null, "newly added power query has delete")
	if del != null:
		del.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	ui._commit()
	check(not ui.data.effects[0].has("power_query"), "deleted power query not written back")
	f = FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(ui.maker.export_text(ui.data, ui.style))
	f.close()
	back = ui.maker.read_json(SCRATCH)
	check(back is Dictionary and not back.effects[0].has("power_query") and Codec.same(back, ui.data), "round-trip after delete has no power_query")

	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
