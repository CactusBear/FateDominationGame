class_name MatchSelectionAuthority
extends RefCounted

## 仅主机持有规则对象和隐藏分配。连接为 0 的座位才是 AI。
var rules
var controllers: Dictionary = {}
var error: String = ""
var _masters: Dictionary = {}

func setup(mode, seats: Dictionary, masters: Array, servants: Array, config: Dictionary) -> bool:
	if not is_instance_of(mode, preload("res://scripts/selection/selection_mode.gd")) or seats.is_empty():
		return _reject("选人规则或座位无效")
	for id in seats:
		if not id is int or id < 0 or not seats[id] is int or seats[id] < 0:
			return _reject("座位控制声明无效")
	var named: Dictionary = {}
	for master in masters:
		if named.has(master._name):
			return _reject("御主模板标识重复")
		named[master._name] = master
	if not mode.setup(seats.keys(), masters, servants, config):
		return _reject(mode.error)
	rules = mode
	controllers = seats.duplicate()
	_masters = named
	var bot := DummyBot.new()
	for id in controllers:
		if controllers[id] == 0:
			var master = bot.pick_master(rules, id)
			if master == null or not rules.choose_master(id, master):
				return _reject("AI 无法选择御主")
	return true

func choose(sender: int, seat: int, master_name: String) -> bool:
	if rules == null or sender <= 0 or controllers.get(seat, -1) != sender:
		return _reject("不能操作该座位")
	if not _masters.has(master_name) or not rules.choose_master(seat, _masters[master_name]):
		return _reject("御主不可选择")
	return true

func view_for(sender: int) -> Dictionary:
	var view := {"seats": [], "choices": [], "selected": [], "complete": false}
	if rules == null:
		return view
	view.complete = rules.is_complete()
	for seat in controllers:
		if rules.assignments.has(seat):
			view.selected.append({"seat": seat, "master": str(rules.assignments[seat].master._name)})
		if sender > 0 and controllers[seat] == sender:
			view.seats.append(seat)
			for master in rules.available_masters(seat):
				view.choices.append({"seat": seat, "name": str(master._name), "label": str(master.get_shown_name())})
	return view

func _reject(reason: String) -> bool:
	error = reason
	return false
