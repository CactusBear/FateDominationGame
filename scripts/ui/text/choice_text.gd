class_name ChoiceText
extends RefCounted

## 选择确认按钮的纯文本格式化；不读取规则或 UI 状态。
static func card_confirm(verb: String, option_label: String) -> String:
	if not verb.is_empty(): return "确认%s" % verb
	if not option_label.is_empty(): return "确认 %s" % option_label
	return "确认弃置"
