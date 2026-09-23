extends RefCounted

# 积木模型 ⇄ 游戏 JSON 的无损编解码。只在编辑器里用，不进游戏数据。
#
# 积木（node）三种：
#   {"t":"op", "func":名, "params":[空位], "var":记到哪个变量(-1 不记), "cond":空位或 null, "keys":原键顺序, "extra":其余原样保留的键}
#   {"t":"method", "target":空位, "method":方法名, "params":[空位], 其余同上}   对应 {"self_var", "sub_func"}
#   {"t":"if", "cond":空位, "body":[积木]}   连续几步共用同一个 condition 时合成一块「如果…那么」
# 空位（slot）：
#   {"s":"lit","v":原值}  {"s":"num","i":效果数字下标}  {"s":"var","n":变量号}  {"s":"qty","i":选项下标}
#   {"s":"block","b":积木}   只被用一次、紧挨在使用者前面的那一步，嵌进使用它的空位里
#   {"s":"desc","b":积木}    参数本身就是一段操作描述（由接收它的操作自己去执行），原样嵌套
#   {"s":"script","body":[积木]}  参数是一串操作（循环体等）
#   {"s":"list","items":[空位]}   含占位符的数组
#
# 解码后一律再编码一次与原文比对，不一致就退回不折叠的逐步形态：识别零误判。

var container_params:Dictionary = {}   # func_name -> [参数位]，缺声明时只按数据形状识别


func _init(containers:Dictionary = {}) -> void:
	container_params = containers


# ---------- 解码 ----------

# list：要解码的那一串操作。变量表每次结算都从空开始，按这一串自己的读写次数判断能不能折叠。
func decode_list(raw:Array, scope = null) -> Array:
	var stats := var_stats(raw if scope == null else scope)
	return _decode_list(raw, stats)


func _decode_list(raw:Array, stats:Dictionary) -> Array:
	var plain:Array = []
	for item in raw:
		plain.append(_decode_block(item, stats))
	var folded := _fold(plain, stats)
	if same(encode_list(folded, {"next": 1 << 30}), raw):
		return folded
	return plain


func _decode_block(raw, stats:Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {"t": "raw", "v": raw}
	var node := {"keys": raw.keys(), "extra": {}, "var": int(raw.get("var_index", -1)), "cond": null}
	if raw.has("func_name"):
		node.t = "op"
		node.func = str(raw.func_name)
	elif raw.has("self_var") and raw.has("sub_func"):
		node.t = "method"
		node.method = str(raw.sub_func)
		node.target = {"s": "var", "n": int(raw.self_var)}
	else:
		return {"t": "raw", "v": raw}
	var params:Array = []
	var raw_params = raw.get("parameters", [])
	if raw_params is Array:
		for i in raw_params.size():
			params.append(_decode_slot(raw_params[i], stats, node.get("func", ""), i))
	node.params = params
	if raw.has("condition"):
		node.cond = _decode_slot(raw.condition, stats, "", -1)
	for key in raw:
		if not key in ["func_name", "parameters", "var_index", "condition", "self_var", "sub_func"]:
			node.extra[key] = raw[key]
	return node


func _decode_slot(value, stats:Dictionary, func_name:String, index:int) -> Dictionary:
	var declared:bool = container_params.get(func_name, []).has(index)
	if value is Array:
		if (declared and value.is_empty()) or is_block_list(value):
			return {"s": "script", "body": _decode_list(value, stats)}
		if _has_placeholder(value):
			var items:Array = []
			for item in value:
				items.append(_decode_slot(item, stats, "", -1))
			return {"s": "list", "items": items}
		return {"s": "lit", "v": value}
	if value is Dictionary:
		if value.has("number_index") and value.size() == 1:
			return {"s": "num", "i": int(value.number_index)}
		if value.has("option_quantity_index") and value.size() == 1:
			return {"s": "qty", "i": int(value.option_quantity_index)}
		if value.has("self_var") and value.size() == 1:
			return {"s": "var", "n": int(value.self_var)}
		if value.has("func_name") or (value.has("self_var") and value.has("sub_func")):
			var inner := _decode_block(value, stats)
			inner.nested = true
			return {"s": "desc", "b": inner}
	return {"s": "lit", "v": value}


# 把「只被用一次、紧挨在使用者前面」的步骤折进使用者的空位，再把共用条件的连续步骤合成「如果」。
func _fold(plain:Array, stats:Dictionary) -> Array:
	var out:Array = []
	for node in plain:
		if node.t == "op" or node.t == "method":
			var refs:Array = []
			_collect_var_slots(node, refs)
			for k in range(refs.size() - 1, -1, -1):
				var holder:Dictionary = refs[k]
				var n:int = int(holder.slot.n)
				if out.is_empty() or not _foldable(out.back(), n, stats, 1):
					break
				var producer:Dictionary = out.pop_back()
				holder.parent[holder.key] = {"s": "block", "b": producer}
		out.append(node)
	return _group_conditions(out, stats)


func _group_conditions(nodes:Array, stats:Dictionary) -> Array:
	var out:Array = []
	var i := 0
	while i < nodes.size():
		var node:Dictionary = nodes[i]
		var cond = node.get("cond")
		if node.t == "raw" or cond == null or cond.s != "var":
			out.append(node)
			i += 1
			continue
		var n:int = int(cond.n)
		var group := {"t": "if", "cond": {"s": "var", "n": n}, "body": []}
		while i < nodes.size() and nodes[i].t != "raw" and nodes[i].get("cond") is Dictionary and nodes[i].cond.s == "var" and int(nodes[i].cond.n) == n:
			nodes[i].cond = null
			group.body.append(nodes[i])
			i += 1
		if not out.is_empty() and _foldable(out.back(), n, stats, group.body.size()):
			group.cond = {"s": "block", "b": out.pop_back()}
		out.append(group)
	return out


func _foldable(node, n:int, stats:Dictionary, uses:int) -> bool:
	if not node is Dictionary or node.t != "op" and node.t != "method":
		return false
	if int(node.get("var", -1)) != n or node.get("cond") != null:
		return false
	return int(stats.writes.get(n, 0)) == 1 and int(stats.reads.get(n, 0)) == uses


# 按求值顺序收集一个积木自己空位里的变量引用（不进循环体、不进嵌套描述）。
func _collect_var_slots(node:Dictionary, out:Array) -> void:
	if node.t == "method":
		_collect_in_slot(node, "target", out)
	for i in node.params.size():
		_collect_in_slot(node.params, i, out)


func _collect_in_slot(parent, key, out:Array) -> void:
	var slot:Dictionary = parent[key]
	match str(slot.s):
		"var":
			out.append({"parent": parent, "key": key, "slot": slot})
		"list":
			for i in slot.items.size():
				_collect_in_slot(slot.items, i, out)


# ---------- 编码 ----------

func encode_effect_list(nodes:Array, context = null) -> Array:
	return encode_list(nodes, {"next": maxi(max_var(nodes), max_var(context)) + 1})


func encode_list(nodes:Array, alloc:Dictionary, forced_cond = null) -> Array:
	var out:Array = []
	for node in nodes:
		_encode_stmt(node, alloc, out, forced_cond)
	return out


func _encode_stmt(node:Dictionary, alloc:Dictionary, out:Array, forced_cond) -> void:
	match str(node.t):
		"raw":
			out.append(node.v)
		"if":
			var ref = _encode_slot(node.cond, alloc, out)
			if ref == null:
				# 条件还空着：编成「永远不成立」，宁可不做也不要变成无条件执行。界面会把它列为必须修的问题
				ref = false
			if forced_cond != null:
				# 「如果」里再套「如果」：两个条件都成立才做，用已有的 and_func 合起来
				var both:int = _take_var(alloc)
				out.append({"func_name": "and_func", "parameters": [forced_cond, ref], "var_index": both})
				ref = {"self_var": both}
			for child in node.body:
				_encode_stmt(child, alloc, out, ref)
		_:
			out.append(_encode_block(node, alloc, out, forced_cond))


func _encode_block(node:Dictionary, alloc:Dictionary, out, forced_cond = null) -> Dictionary:
	var params:Array = []
	var target = null
	if node.t == "method":
		target = _encode_slot(node.target, alloc, out)
	# 末尾没填的可选参数不写，让操作用自己的默认值；中间没填的写成声明的默认值
	var last:int = node.params.size() - 1
	while last >= 0 and node.params[last] is Dictionary and str(node.params[last].get("s", "")) == "omit":
		last -= 1
	for i in last + 1:
		params.append(_encode_slot(node.params[i], alloc, out))
	var cond = forced_cond
	var has_cond:bool = forced_cond != null
	if not has_cond and node.get("cond") is Dictionary:
		cond = _encode_slot(node.cond, alloc, out)
		has_cond = true
	var fields := {}
	if node.t == "op":
		fields["func_name"] = node.func
	else:
		fields["self_var"] = int(target.self_var) if target is Dictionary and target.has("self_var") else target
		fields["sub_func"] = node.method
	fields["parameters"] = params
	fields["var_index"] = int(node.get("var", -1))
	if has_cond:
		fields["condition"] = cond
	var result := {}
	var keys:Array = node.get("keys", [])
	for key in keys:
		if fields.has(key):
			result[key] = fields[key]
		elif node.extra.has(key):
			result[key] = node.extra[key]
	for key in fields:
		if not result.has(key):
			# 原文省略了、而且值仍是默认的键，不凭空补上
			if not keys.is_empty() and not keys.has(key):
				if key == "var_index" and int(fields[key]) == -1:
					continue
				if key == "parameters" and params.is_empty():
					continue
			result[key] = fields[key]
	for key in node.extra:
		if not result.has(key):
			result[key] = node.extra[key]
	return result


func _encode_slot(slot:Dictionary, alloc:Dictionary, out):
	match str(slot.s):
		"num":
			return {"number_index": int(slot.i)}
		"qty":
			return {"option_quantity_index": int(slot.i)}
		"var":
			return {"self_var": int(slot.n)}
		"block":
			# 先编好它自己的空位（里面的报告积木先占小号），再给它分变量号：读起来与手写 JSON 同序。
			# 不回写模型：同一个模型反复预览、挪动后也不会带着旧编号撞车
			var b:Dictionary = slot.b
			var encoded := _encode_block(b, alloc, out)
			var n:int = int(b.get("var", -1))
			if n < 0:
				n = _take_var(alloc)
			encoded["var_index"] = n
			out.append(encoded)
			return {"self_var": n}
		"desc":
			return _encode_block(slot.b, alloc, [])
		"script":
			return encode_list(slot.body, alloc)
		"omit":
			return slot.get("d")
		"list":
			var items:Array = []
			for item in slot.items:
				items.append(_encode_slot(item, alloc, out))
			return items
	return slot.get("v")


func _take_var(alloc:Dictionary) -> int:
	var n:int = int(alloc.next)
	alloc.next = n + 1
	return n


# ---------- 统计与工具 ----------

func var_stats(effect) -> Dictionary:
	var stats := {"reads": {}, "writes": {}}
	_walk_vars(effect, stats)
	return stats


func _walk_vars(value, stats:Dictionary) -> void:
	if value is Dictionary:
		if value.has("self_var"):
			var n:int = int(value.self_var)
			stats.reads[n] = int(stats.reads.get(n, 0)) + 1
		if value.has("var_index") and (value.has("func_name") or value.has("sub_func")):
			var w:int = int(value.var_index)
			if w >= 0:
				stats.writes[w] = int(stats.writes.get(w, 0)) + 1
		for key in value:
			_walk_vars(value[key], stats)
	elif value is Array:
		for item in value:
			_walk_vars(item, stats)


func max_var(value) -> int:
	var best := -1
	if value is Dictionary:
		for key in ["self_var", "var_index"]:
			if value.has(key) and (value[key] is int or value[key] is float):
				best = maxi(best, int(value[key]))
		if value.has("s") and str(value.get("s")) == "var":
			best = maxi(best, int(value.n))
		if value.has("t") and value.has("var"):
			best = maxi(best, int(value.var))
		for key in value:
			best = maxi(best, max_var(value[key]))
	elif value is Array:
		for item in value:
			best = maxi(best, max_var(item))
	return best


static func is_block_list(items:Array) -> bool:
	if items.is_empty():
		return false
	for item in items:
		if not item is Dictionary:
			return false
		if not item.has("func_name") and not (item.has("self_var") and item.has("sub_func")):
			return false
	return true


func _has_placeholder(value) -> bool:
	if value is Dictionary:
		for key in ["number_index", "self_var", "option_quantity_index", "func_name"]:
			if value.has(key):
				return true
		return false
	if value is Array:
		for item in value:
			if _has_placeholder(item):
				return true
	return false


# JSON 语义相等：整数与等值浮点视为相同（Godot 读 JSON 数字全是 float）。
static func same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	if typeof(a) != typeof(b):
		return false
	return a == b
