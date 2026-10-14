class_name ContentEnvironment
extends RefCounted


# 只切换既有两个全局根；token 由调用方持有，嵌套按后进先出恢复。
# 路径原样传递，不校验、加载、清缓存或保存额外状态。
static func install(data_root: String, cache_path: String) -> Dictionary:
	var token := {
		"session_data_dir": LoadHelper.session_data_dir,
		"stored_jsons_path": LoadGame.stored_jsons_path,
	}
	LoadHelper.session_data_dir = data_root
	LoadGame.stored_jsons_path = cache_path
	return token


# token 必须是 install 返回的完整未篡改字典。
# 不自动恢复：调用方在成功、失败和提前返回路径都须显式调用。
static func restore(token: Dictionary) -> void:
	LoadHelper.session_data_dir = token["session_data_dir"]
	LoadGame.stored_jsons_path = token["stored_jsons_path"]
