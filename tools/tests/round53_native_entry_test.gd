extends SceneTree
func _initialize() -> void:
    var entry = load("res://scripts/net/server/server_bootstrap.gd").new()
    if not entry.has_method("_load_signaling_native"):
        print("R53_ENTRY_TEST missing explicit initialization boundary")
        entry.free()
        quit(1)
        return
    var descriptor: String = OS.get_cmdline_user_args()[0]
    var error: String = entry._load_signaling_native(descriptor)
    entry.free()
    print("R53_ENTRY_TEST ", error.is_empty())
    quit(0 if error.is_empty() else 1)