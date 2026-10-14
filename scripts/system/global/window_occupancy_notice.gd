extends Node
## 真窗口测试的"占用提示" —— 通知用户此刻能不能操作电脑。
##
## 为什么放在项目侧、而不是各测试 runner 里各接一次：
## 只要有一条启动路径忘了接通知，用户就会在不知情的情况下被测试抢走鼠标/键盘
## （已经发生过：某个 runner 漏接，用户看到窗口弹出来却没有任何提示）。
## 窗口一出现就通知，等于把这件事从"每个调用方自觉"变成"项目自身行为"。
##
## 判定方式**显式声明、不靠猜**：测试命令在 `--` 之后传用户参数 `window`
## （例：`Godot --path . --scene res://tests/x.tscn -- window`）。
## 正式游戏不带该参数，因此正式运行**绝不**弹通知；headless 测试也不带。
##
## 通知本身复用 `tools/win_notify.py`（无第三方依赖的 Toast，失败退化消息框），
## 不在这里重写一套 PowerShell。

const DECLARED_TEST_ARG := "window"
const NOTIFY_SCRIPT := "res://tools/win_notify.py"

## 是不是一次"声明过的真窗口测试"。其他代码（如 runner）也可以调它做同一判定。
static func is_window_test() -> bool:
	return DECLARED_TEST_ARG in OS.get_cmdline_user_args()

func _ready() -> void:
	if not is_window_test():
		return
	say("⚠ 测试窗口已启动",
		"测试正在占用鼠标和键盘 —— 现在请【不要】操作电脑；窗口关闭时会再弹一条通知。")

func _exit_tree() -> void:
	# 正常退出时补一条"可以操作了"。进程被强杀时这里不会执行，
	# 那种情况由调用方 runner 的 finally 兜底。
	if not is_window_test():
		return
	say("✓ 测试窗口已关闭", "现在【可以】操作电脑了。")

## 弹一条系统通知。绝不报错——通知失败不能影响游戏/测试本身。
func say(title: String, message: String) -> void:
	var script_path := ProjectSettings.globalize_path(NOTIFY_SCRIPT)
	if not FileAccess.file_exists(script_path):
		return
	for exe in ["python", "py", "python3"]:
		var pid := OS.create_process(exe, ["-B", script_path, "say", title, message])
		if pid > 0:
			print("[WindowOccupancyNotice] 已通知（", exe, "）：", title)
			return
	push_warning("[WindowOccupancyNotice] 通知未发出：找不到可用的 python 解释器")
