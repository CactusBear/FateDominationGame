extends RefCounted
## 纯失败投影：不保存状态、不读路径、不发信号、不记录原始结果或上下文。
## PID/request-instance/批准相对标识由可信 caller 在投影后独立绑定。

const STAGES:Array = ["path", "seat", "snapshot", "write", "hash", "native_commit", "initial_commit"]
const NATIVE_STAGES:Array = [
	"invalid_size", "invalid_path", "native_extension_unavailable", "native_interface_unavailable", "invalid_native_result",
	"invalid_argument", "embedded_nul", "drive_path_required", "alternate_stream_rejected", "absolute_path_required",
	"normalized_path_required", "same_path", "missing_or_link_path", "same_directory_required", "volume",
	"local_fixed_volume_required", "open_temporary", "open_target", "disk_file_required", "stat",
	"regular_single_link_required", "same_file", "validated_size_changed", "path_too_long", "native_replace",
	"filesystem_exception", "exception"
]

## 非 native 分支只在 caller 已确认失败时调用；Godot Error 与 OS error 分列。
static func project(stage:Variant, result:Variant = null, godot_error:Variant = null) -> Dictionary:
	var diagnostic:Dictionary = {"version":1, "stage":"unknown", "native_stage":null, "native_error":null, "godot_error":null}
	if not stage is String or stage not in STAGES:
		return diagnostic
	diagnostic.stage = stage
	if stage != "native_commit":
		if godot_error is int and godot_error > 0 and godot_error <= ERR_PRINTER_ON_FIRE:
			diagnostic.godot_error = godot_error
		return diagnostic
	if not result is Dictionary or not result.get("ok") is bool or not result.get("stage") is String or not result.get("native_error") is int or not result.get("durability_guaranteed") is bool or result.durability_guaranteed != false or result.native_error < 0 or result.native_error > 4294967295:
		diagnostic.native_stage = "invalid_native_result"
		return diagnostic
	if result.ok:
		if result.stage == "published" and result.native_error == 0:
			return {}
		diagnostic.native_stage = "invalid_native_result"
		return diagnostic
	if result.stage not in NATIVE_STAGES:
		diagnostic.native_stage = "unknown"
		return diagnostic
	diagnostic.native_stage = result.stage
	# wrapper/预检以 0 代表未采集原生错误；不将 0 或 Godot Error 猜成 WinAPI errno。
	if result.native_error > 0 and result.stage in ["same_directory_required", "volume", "open_temporary", "open_target", "stat", "native_replace", "filesystem_exception"]:
		diagnostic.native_error = result.native_error
	return diagnostic
