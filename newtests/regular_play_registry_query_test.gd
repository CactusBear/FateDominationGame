extends Node

class PropertyTarget extends RefCounted:
	var writes:int = 0
	var value = 0:
		set(next):
			writes += 1
			value = next

var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", ok, " ", label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	# 动态查询入口；缺入口必须显式失败而非放宽断言。
	var factory := Callable(AllOperations, "create_instance_of")
	check(factory.is_valid(), "registry exposes instance query")
	if factory.is_valid():
		var expected := {
			"remove_from_array":"res://scripts/system/operations/RemoveFromArray.gd",
			"add_to_array":"res://scripts/system/operations/AddToArray.gd",
			"set_property":"res://scripts/system/operations/SetProperty.gd",
			"record_log":"res://scripts/system/operations/RecordLog.gd"
		}
		for func_name in expected:
			var first:RefCounted = factory.call(func_name)
			var second:RefCounted = factory.call(func_name)
			check(first is RefCounted, func_name + " RefCounted")
			check(first.get_script().resource_path == expected[func_name], func_name + " literal script")
			check(first.get_script() == second.get_script(), func_name + " stable script identity")
			check(first != second, func_name + " fresh instance per query")
			check(first.has_method("exec"), func_name + " original exec")
		var names:Array = AllOperations._OPERATION_SCRIPTS.keys()
		names.sort()
		check(names == ["AddToArray", "RecordLog", "RemoveFromArray", "SetProperty"], "required scripts")
		check(AllOperations.get_entry("unknown_operation").is_empty(), "unknown metadata unchanged")
		check(AllOperations.get_class_name_of("pay_magic") == "PayMagic", "payment metadata unchanged")
		var item := RefCounted.new()
		var arr:Array = [item, item]
		var alias:Array = arr
		var remove:RefCounted = factory.call("remove_from_array")
		check(remove.exec(item, arr) == true, "remove returns true value")
		check(is_same(arr, alias) and arr.size() == 1 and arr[0] == item, "remove first match preserves alias")
		check(remove.exec(RefCounted.new(), arr) == false and arr.size() == 1, "missing remove returns false value")
		var add:RefCounted = factory.call("add_to_array")
		check(is_same(add.exec(item, arr, -1), arr), "add returns original array")
		check(arr == [item, item] and is_same(arr, alias), "append preserves duplicate and alias")
		var inserted := RefCounted.new()
		add.exec(inserted, arr, 0)
		check(arr == [inserted, item, item], "explicit insertion index preserved")
		var target := PropertyTarget.new()
		var set_property:RefCounted = factory.call("set_property")
		check(set_property.exec(target, "value", 1.25) == 1.25, "property returns written value")
		check(target.writes == 1 and typeof(target.value) == TYPE_FLOAT, "setter and float type preserved")
		check(set_property.exec(target, "missing", 4) == null and target.writes == 1, "missing property remains no-op")
		check(set_property.exec(null, "value", 4) == null, "null property target remains no-op")
	print("RESULT ", JSON.stringify({"suite":"regular_play_registry_query", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
