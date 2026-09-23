extends Node

# 积木编辑器编解码回归：全库 JSON 的每一串操作解码成积木再编码回来，必须与原文语义一致；
# 并检查新建积木（嵌套报告、如果、循环）能编成加载器认识的形状。
const Codec = preload("res://json_maker/json_codec.gd")

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
	var maker := JsonMaker.new()
	maker.load_catalog()
	var codec = Codec.new(maker.container_params())
	var lists := 0
	var folded := 0
	var bad:Array = []
	for path in _json_files("res://data"):
		var data = maker.read_json(path)
		for entry in _effect_lists(data):
			lists += 1
			var nodes:Array = codec.decode_list(entry.list, entry.list)
			var back:Array = codec.encode_effect_list(nodes, entry.effect)
			if not Codec.same(back, entry.list):
				bad.append(path + " " + entry.where)
			if _has_folded(nodes):
				folded += 1
	check(lists > 150, "found effect lists " + str(lists))
	check(bad.is_empty(), "all lists round trip " + str(bad.slice(0, 5)))
	check(folded > 20, "reporter folding kicks in " + str(folded))

	# 新建：把「读取魔力」嵌进「改魔力」的增减空位，再放进「如果」里
	var reader := {"t": "op", "func": "get_data_number", "params": [{"s": "lit", "v": "magic"}, {"s": "lit", "v": -1}], "var": -1, "cond": null, "keys": [], "extra": {}}
	var cmp := {"t": "op", "func": "compare_number", "params": [{"s": "block", "b": reader}, {"s": "lit", "v": 3}], "var": -1, "cond": null, "keys": [], "extra": {}}
	var edit := {"t": "op", "func": "edit_magic", "params": [{"s": "lit", "v": null}, {"s": "num", "i": 0}, {"s": "lit", "v": -1}], "var": -1, "cond": null, "keys": [], "extra": {}}
	var group := {"t": "if", "cond": {"s": "block", "b": cmp}, "body": [edit]}
	var effect := {"effect_numbers": [{"number": 1, "can_change": true, "is_pure_number": true}]}
	var out:Array = codec.encode_effect_list([group], effect)
	check(out.size() == 3, "if + nested reporters flatten to 3 steps")
	check(out[0].func_name == "get_data_number" and int(out[0].var_index) == 0, "reader stored first")
	check(out[1].func_name == "compare_number" and out[1].parameters[0].self_var == 0, "compare reads reader var")
	check(out[2].func_name == "edit_magic" and out[2].condition.self_var == int(out[1].var_index), "body step guarded by condition")
	var again:Array = codec.decode_list(out, {"funcs": out})
	check(again.size() == 1 and again[0].t == "if", "re-open folds back into one if block")

	var loop := {"t": "op", "func": "for_func", "params": [{"s": "script", "body": [edit]}, {"s": "num", "i": 0}], "var": -1, "cond": null, "keys": [], "extra": {}}
	var looped:Array = codec.encode_effect_list([loop], effect)
	check(looped[0].parameters[0] is Array and looped[0].parameters[0][0].func_name == "edit_magic", "loop body encodes as op list")

	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _has_folded(nodes:Array) -> bool:
	var text := JSON.stringify(nodes)
	return text.find("\"s\":\"block\"") != -1 or text.find("\"t\":\"if\"") != -1


func _effect_lists(node, where := "") -> Array:
	var out:Array = []
	if node is Dictionary:
		var is_effect:bool = node.has("effect_name") or node.has("time_points")
		if is_effect:
			for key in ["funcs", "power_query"]:
				if node.get(key) is Array:
					out.append({"list": node[key], "effect": node, "where": where + "/" + key})
			for oi in (node.get("options", []) as Array).size():
				var option = node.options[oi]
				if option is Dictionary and option.get("funcs") is Array:
					out.append({"list": option.funcs, "effect": node, "where": where + "/options/" + str(oi)})
				if option is Dictionary and option.get("activation_requirements") is Array:
					for ri in option.activation_requirements.size():
						var req = option.activation_requirements[ri]
						if req is Dictionary and req.get("funcs") is Array:
							out.append({"list": req.funcs, "effect": req, "where": where + "/req/" + str(ri)})
		for key in node:
			if is_effect and key in ["funcs", "power_query", "options"]:
				continue
			out.append_array(_effect_lists(node[key], where + "/" + str(key)))
	elif node is Array:
		for i in node.size():
			out.append_array(_effect_lists(node[i], where + "/" + str(i)))
	return out


func _json_files(folder:String) -> Array:
	var out:Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := folder.path_join(name)
		if dir.current_is_dir():
			out.append_array(_json_files(path))
		elif name.ends_with(".json"):
			out.append(path)
		name = dir.get_next()
	return out
