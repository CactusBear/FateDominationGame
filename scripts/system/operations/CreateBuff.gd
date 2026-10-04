class_name CreateBuff
extends RefCounted

func exec(buff_name:String, buff_img:String, buff_id:int):

	var buff = BaseBuff.new(buff_name, buff_img)
	return buff
