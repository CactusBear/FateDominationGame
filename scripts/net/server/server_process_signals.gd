extends RefCounted

## 仅装载固定本机原生适配器，不从网络或配置接收类名与脚本路径。
static func create():
	if not ClassDB.class_exists("FateServerSignals"):
		GDExtensionManager.load_extension("res://addons/fate_server_signals/fate_server_signals.gdextension")
	return ClassDB.instantiate("FateServerSignals") if ClassDB.class_exists("FateServerSignals") else null
