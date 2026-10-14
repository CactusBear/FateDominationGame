class_name ShuffleArray
extends RefCounted

const RuleRandom = preload("res://scripts/match/rule_random.gd")

# 只读预检供可信工厂在创建克隆之前拒绝；不声明/消耗随机流。
static func can_shuffle() -> bool:
	return RuleRandom.is_known()

# 成功仍返回原数组；未声明随机流返回 null，数组保持原样（包括空/单元素）。
# 复用 RuleRandom 的失败关闭洗牌，不在消费口取全局随机或声明流。
func exec(arr:Array):
	if arr == null or not RuleRandom.shuffle(arr):
		return null
	return arr
