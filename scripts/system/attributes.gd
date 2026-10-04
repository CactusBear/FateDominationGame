extends Node
class_name Attributes


#卡牌属性。卡面左上角的属性旗标，一张卡可以同时具有多个属性。
#属性主要出现在攻击卡上，部分非攻击卡也会带有宝具属性。
const STRENGTH = "strength"
const AGILITY = "agility"
const MAGIC = "magic"
const SPECIAL = "special"
const NOBLE_PHANTASM = "noble_phantasm"


#全部属性
const all_attributes:Array = [
	STRENGTH,
	AGILITY,
	MAGIC,
	SPECIAL,
	NOBLE_PHANTASM
]


#dic
const shown_attributes:Dictionary = {
	STRENGTH : "力量",
	AGILITY : "迅捷",
	MAGIC : "魔术",
	SPECIAL : "特殊",
	NOBLE_PHANTASM : "宝具"
}


#运行时注册的自定义属性，{属性名 : 显示名}。
#属性不写死，特殊卡牌或扩展可以注册上表以外的新属性
static var custom_attributes:Dictionary = {}


#注册自定义属性，shown_name留空时显示名与属性名相同
static func register_attribute(attribute:String, shown_name:String = ""):
	if all_attributes.has(attribute):
		return
	if shown_name == "":
		shown_name = attribute
	custom_attributes[attribute] = shown_name


static func unregister_attribute(attribute:String):
	custom_attributes.erase(attribute)


#上表的属性加上已注册的自定义属性
static func get_all_attributes() -> Array:
	var all:Array = all_attributes.duplicate()
	all.append_array(custom_attributes.keys())
	return all


#是否为已知属性。未注册的属性也能照常参与比对，这里只用于提示
static func is_known_attribute(attribute:String) -> bool:
	return all_attributes.has(attribute) or custom_attributes.has(attribute)


static func get_shown_attribute(attribute:String) -> String:
	if shown_attributes.has(attribute):
		return shown_attributes[attribute]
	if custom_attributes.has(attribute):
		return custom_attributes[attribute]
	return attribute


#取出一组属性的显示名，用于界面展示
static func get_shown_attributes(attributes:Array) -> Array:
	var shown:Array = []
	for attribute in attributes:
		shown.append(get_shown_attribute(attribute))
	return shown
