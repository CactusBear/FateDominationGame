extends "res://scripts/net/server/server_bootstrap.gd"

## 隔离 bootstrap 加载边界：不运行角色路由，不改变继承的加载/首错/退出函数。
func _ready() -> void:
	var descriptor:String = OS.get_environment("HERMES_ROUND64_NATIVE_DESCRIPTOR")
	var error:String = _load_signaling_native(descriptor)
	print("ROUND64_BOOTSTRAP_REJECTION ",JSON.stringify({"reason":error}))
	if not error.is_empty():
		_signal_fail(error)
		return
	print("CHECK true original DLL bootstrap contract accepted")
	print("RESULT ",JSON.stringify({"suite":"round64_bootstrap_contract","checks":1,"failures":[]}))
	get_tree().quit(0)
