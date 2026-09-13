class_name ShowMessage
extends RefCounted

#把一条提示消息交给界面展示。
#operation只负责"产生消息"，不决定显示形态(弹窗/浮窗/日志)——显示是界面层的事，
#这样同一条消息在单机、联机、不同界面上都能复用，不必每加一处提示就改一次效果。
#player_id = -1 表示所有人都能看到；填具体玩家时只给该玩家看(如"你的移动失败")
func exec(message:String, player_id:int = -1):

	EffectManager.push_message(message, player_id)
