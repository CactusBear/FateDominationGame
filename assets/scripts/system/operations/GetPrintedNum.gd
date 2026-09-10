class_name GetPrintedNum
extends RefCounted

func exec(index:BaseNumber, object:BaseObject):

	if object.numbers.size() <= index.number:
		#show("超出数组范围")
		return
	return object.numbers[index.number]
