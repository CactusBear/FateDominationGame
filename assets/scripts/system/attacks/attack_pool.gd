extends RefCounted
class_name AttackPool

#攻击牌池：登记所有攻击卡类，供牌库生成按「属性+威力」或「特殊名」查找。
#基础攻击牌（Basic Attack）
static var BASIC_ATTACKS: Array = [
	PhysicalAttack02, PhysicalAttack03, PhysicalAttack04, PhysicalAttack15,
	PrecisionStrike02, PrecisionStrike03, PrecisionStrike04, PrecisionStrike15,
	MagicBlast02, MagicBlast03, MagicBlast04, MagicBlast15,
	Preparation, Surveil, Luck,
]

#职阶攻击牌（Class Attack，会进牌库的职阶卡）
static var CLASS_ATTACKS: Array = [
	BerserkerClassStrength37, BerserkerClassStrength59,
	BerserkerClassAgility37, BerserkerClassAgility59,
	BerserkerClassMagic37, BerserkerClassMagic59,
	AvengerClass, ForeignerClass, MooncancerClass,
]


#按属性+威力查找攻击卡（力量/敏捷/魔术，含基础与职阶）。找不到返回 null。
static func find_by_attribute_power(attribute: String, power: int) -> BaseAttack:
	for cls in BASIC_ATTACKS + CLASS_ATTACKS:
		var card: BaseAttack = cls.new()
		if attribute in card._attributes and card._power.number == power:
			return card
		card.del()
	return null


#按内部名查找特殊攻击卡（如 surveil / luck / preparation）。找不到返回 null。
static func find_special(attack_name: String) -> BaseAttack:
	for cls in [Preparation, Surveil, Luck]:
		var card: BaseAttack = cls.new()
		if card._name == attack_name:
			return card
		card.del()
	return null


#解析牌库构成条目："attribute:power"（力量/敏捷/魔术，如 "strength:2"）或 "special:name"（如 "special:surveil"）。
#返回对应的攻击卡实例，找不到或格式不符返回 null。
static func resolve(entry: String) -> BaseAttack:
	var parts = entry.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "special":
		return find_special(parts[1])
	return find_by_attribute_power(parts[0], int(parts[1]))
