extends BaseNumber

## 公开 BaseNumber 运算的被动观察器；数学行为完全委托原实现。
## 通过公开 SetPlayerData 提供合法 order 数字，不替换 operation/router。
var deltas: Array = []

func add(num: BaseNumber) -> BaseNumber:
	deltas.append(num.number)
	return super.add(num)
