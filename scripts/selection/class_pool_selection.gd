extends "res://scripts/selection/selection_mode.gd"

var _masters: Array = []
var _draw_groups: Array = []
var _shuffle := ShuffleArray.new()
var _randomize_order := false

func _unique_templates(source: Array) -> Array:
	var result: Array = []
	var names: Array = []
	for candidate in source:
		if candidate != null and not names.has(candidate._name):
			names.append(candidate._name)
			result.append(candidate)
	return result

## 特殊职阶是一组，不是每个特殊职阶分别入池。
func _groups(servants: Array, config: Dictionary) -> Array:
	error = ""
	var regular: Array = config.get("regular_classes", [])
	var per_class: int = int(config.get("per_class_count", 0))
	var special_count: int = int(config.get("special_count", 0))
	if regular.is_empty() or per_class <= 0 or special_count < 0:
		error = "选人模式配置无效"
		return []
	var groups: Array = []
	var used: Array = []
	var unique := _unique_templates(servants)
	for class_id in regular:
		if used.has(class_id):
			error = "常规职阶声明重复"
			return []
		used.append(class_id)
		var candidates: Array = []
		for servant in unique:
			if servant._servant_class == class_id:
				candidates.append(servant)
		if candidates.size() < per_class:
			error = "常规职阶候选不足：" + str(class_id)
			return []
		groups.append({"candidates": candidates, "count": per_class})
	var special: Array = []
	for servant in unique:
		if not regular.has(servant._servant_class):
			special.append(servant)
	if not special.is_empty() and special_count > 0:
		if special.size() < special_count:
			error = "特殊职阶候选不足"
			return []
		groups.append({"candidates": special, "count": special_count})
	return groups

func capacity(masters: Array, servants: Array, config: Dictionary) -> int:
	var groups := _groups(servants, config)
	if not error.is_empty():
		return 0
	var total := 0
	for group in groups:
		total += int(group.count)
	return mini(_unique_templates(masters).size(), total)

func setup(ids: Array, masters: Array, servants: Array, config: Dictionary) -> bool:
	player_ids.clear()
	initial_order.clear()
	_randomize_order = config.get("randomize_initial_order", false) == true
	assignments.clear()
	_draw_groups.clear()
	_masters = _unique_templates(masters)
	var maximum := capacity(masters, servants, config)
	if not error.is_empty():
		return false
	if ids.is_empty() or ids.size() > maximum:
		error = "人数超出御主或从者池容量"
		return false
	for id in ids:
		if not id is int or player_ids.has(id):
			player_ids.clear()
			error = "玩家 ID 无效或重复"
			return false
		player_ids.append(id)
	_draw_groups = _groups(servants, config)
	return true

func _draw_servants() -> Array:
	var pool: Array = []
	for group in _draw_groups:
		var candidates: Array = group.candidates.duplicate()
		_shuffle.exec(candidates)
		pool.append_array(candidates.slice(0, int(group.count)))
	_shuffle.exec(pool)
	return pool

func available_masters(player_id: int) -> Array:
	if not player_ids.has(player_id) or is_complete():
		return []
	var result: Array = []
	for master in _masters:
		var taken := false
		for id in assignments:
			if id != player_id and assignments[id].master == master:
				taken = true
		if not taken:
			result.append(master)
	return result

func choose_master(player_id: int, master) -> bool:
	if not available_masters(player_id).has(master):
		error = "该御主不可选择"
		return false
	assignments[player_id] = {"master": master}
	error = ""
	if assignments.size() == player_ids.size():
		var pool := _draw_servants()
		for i in player_ids.size():
			assignments[player_ids[i]]["servant"] = pool[i]
		initial_order = player_ids.duplicate()
		if _randomize_order:
			_shuffle.exec(initial_order)
	return true

func is_complete() -> bool:
	if player_ids.is_empty() or assignments.size() != player_ids.size():
		return false
	for id in player_ids:
		if not assignments.has(id) or not assignments[id].has("servant"):
			return false
	return true
