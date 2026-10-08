extends RefCounted

var max_effects: int = 10000
var max_edges: int = 100000
var max_visits: int = 100000
var max_depth: int = 128
var high_iteration_threshold: int = 10000
var _report: Dictionary = {}
var _visits: int = 0

func inspect(documents: Array) -> Dictionary:
	_report = {"nodes": [], "cycles": [], "unknowns": [], "warnings": [], "errors": [], "truncated": false}
	_visits = 0
	if max_effects <= 0 or max_edges <= 0 or max_visits <= 0 or max_depth <= 0 or high_iteration_threshold <= 0:
		_fail("静态分析预算无效")
		return _report
	for document in documents:
		if not document is Dictionary or not document.get("path") is String or not document.get("provider", "") is String:
			_fail("静态分析来源元数据无效")
			break
		_collect(document.get("data"), document, "$", 0)
		if _report.truncated:
			break
	if not _report.truncated:
		_build_graph()
	return _report

func _fail(reason: String) -> void:
	if not _report.truncated:
		_report.errors.append(reason)
	_report.truncated = true

func _visit(depth: int) -> bool:
	_visits += 1
	if _report.truncated:
		return false
	if depth > max_depth or _visits > max_visits:
		_fail("静态分析深度或遍历预算不足")
		return false
	return true

func _collect(value, source: Dictionary, pointer: String, depth: int) -> void:
	if not _visit(depth):
		return
	if value is Dictionary:
		if value.get("effects") is Array:
			for index in range(value.effects.size()):
				var data = value.effects[index]
				if not data is Dictionary:
					continue
				if _report.nodes.size() >= max_effects:
					_fail("静态分析效果预算不足")
					return
				var node := {"id": _report.nodes.size(), "name": str(data.get("effect_name", "")), "provider": source.get("provider", ""), "path": source.path, "pointer": pointer + ".effects[%s]" % index, "listen": [], "emits": [], "limited": data.get("once_per_game") == true or data.get("options") is Array and _finite_limit(data.get("max_total_uses"))}
				for point in data.get("time_points", []) if data.get("time_points", []) is Array else []:
					if point is String:
						node.listen.append(point)
					else:
						_unknown(node, "监听时点不是静态字符串")
				if not data.has("options"):
					_walk(data.get("funcs", []), node, depth + 1)
				for option in data.get("options", []) if data.get("options", []) is Array else []:
					if option is Dictionary:
						_walk(option.get("funcs", []), node, depth + 1)
				_report.nodes.append(node)
		for key in value:
			_collect(value[key], source, pointer + "." + str(key), depth + 1)
	elif value is Array:
		for index in range(value.size()):
			_collect(value[index], source, pointer + "[%s]" % index, depth + 1)

func _finite_limit(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(float(value))

func _unknown(node: Dictionary, reason: String) -> void:
	_report.unknowns.append({"path": node.path, "provider": node.provider, "pointer": node.pointer, "reason": reason})

func _walk(value, node: Dictionary, depth: int) -> void:
	if not _visit(depth):
		return
	if value is Dictionary:
		var parameters = value.get("parameters", [])
		if parameters is Array:
			match value.get("func_name"):
				"emit_time_point":
					if not parameters.is_empty() and parameters[0] is String:
						if not node.emits.has(parameters[0]):
							node.emits.append(parameters[0])
					else:
						_unknown(node, "派发时点由变量求值")
				"while_func":
					if parameters.size() >= 2 and parameters[1] is bool and parameters[1]:
						_report.warnings.append({"kind": "constant_while", "node": node.id, "path": node.path, "pointer": node.pointer})
					if parameters.size() >= 3 and _finite_limit(parameters[2]) and parameters[2] >= high_iteration_threshold:
						_report.warnings.append({"kind": "large_while", "node": node.id, "iterations": parameters[2], "path": node.path, "pointer": node.pointer})
				"schedule_effect_on_time_point":
					_unknown(node, "延迟效果会创建新实例，需运行时或聚焦模拟验证")
					return
				"build_effect", "queue_optional_effect_for_players":
					_unknown(node, "运行时创建效果，静态图不是完整触发图")
					return
		if value.has("dynamic_time_point"):
			_unknown(node, "动态时点不能静态证明")
		for key in value:
			_walk(value[key], node, depth + 1)
	elif value is Array:
		for item in value:
			_walk(item, node, depth + 1)

func _build_graph() -> void:
	var listeners: Dictionary = {}
	var edges: Array = []
	var reverse_edges: Array = []
	for node in _report.nodes:
		edges.append([])
		reverse_edges.append([])
		for point in node.listen:
			if not listeners.has(point):
				listeners[point] = []
			listeners[point].append(node.id)
	var count := 0
	for node in _report.nodes:
		for point in node.emits:
			for target in listeners.get(point, []):
				if edges[node.id].has(target):
					continue
				count += 1
				if count > max_edges:
					_fail("静态触发图边数预算不足")
					return
				edges[node.id].append(target)
				reverse_edges[target].append(node.id)
	var visited: Dictionary = {}
	var order: Array = []
	for start in range(edges.size()):
		var stack: Array = [[start, false]]
		while not stack.is_empty():
			var frame: Array = stack.pop_back()
			if frame[1]:
				order.append(frame[0])
			elif not visited.has(frame[0]):
				visited[frame[0]] = true
				stack.append([frame[0], true])
				for target in edges[frame[0]]:
					if not visited.has(target):
						stack.append([target, false])
	visited.clear()
	order.reverse()
	for start in order:
		if visited.has(start):
			continue
		var group: Array = []
		var stack: Array = [start]
		while not stack.is_empty():
			var id: int = stack.pop_back()
			if visited.has(id):
				continue
			visited[id] = true
			group.append(id)
			stack.append_array(reverse_edges[id])
		if group.size() > 1 or edges[group[0]].has(group[0]):
			_report.cycles.append({"nodes": group, "risk": "high" if _unlimited_cycle(group, edges) else "low"})

func _unlimited_cycle(group: Array, edges: Array) -> bool:
	var indegree: Dictionary = {}
	for id in group:
		if not _report.nodes[id].limited:
			indegree[id] = 0
	for id in indegree:
		for target in edges[id]:
			if indegree.has(target):
				indegree[target] += 1
	var queue: Array = []
	for id in indegree:
		if indegree[id] == 0:
			queue.append(id)
	var removed := 0
	while not queue.is_empty():
		var id = queue.pop_back()
		removed += 1
		for target in edges[id]:
			if indegree.has(target):
				indegree[target] -= 1
				if indegree[target] == 0:
					queue.append(target)
	return removed < indegree.size()
