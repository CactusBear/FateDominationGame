extends RefCounted

const RoomPassword = preload("res://scripts/net/identity/room_password.gd")
const SAVE_FAILURE:String = "房间密码保存失败，原设置未改变"

## 请求作用域事务；授权、协议、发布、revision 与是否需要落盘均由调用者决定。
## persist 必须是同步、无参、返回 bool 的显式能力；不需要落盘时由调用者传入返回 true 的能力。
## 不保存对象或 Callable，也不读取 Session、Room 或部署路径；空字符串沿用原有取消密码语义。
func receive(password:RoomPassword, value:String, persist:Callable) -> Dictionary:
	if not persist.is_valid():
		return {"ok":false,"reason":SAVE_FAILURE}
	var previous:Dictionary = password.verifier.duplicate(true)
	if not password.set_password(value) or not persist.call():
		password.verifier = previous
		return {"ok":false,"reason":SAVE_FAILURE}
	return {"ok":true,"reason":""}
