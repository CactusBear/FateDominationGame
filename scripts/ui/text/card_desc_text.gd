class_name CardDescText
extends RefCounted

const ATTACK_CATEGORY_LABELS := {
	"basic": "基础攻击牌",
	"class": "职阶攻击牌",
	"non_basic": "专属攻击牌",
}

const FIELD_LABELS := {
	"_cost": "魔力消耗",
	"_power": "威力",
	"_score": "战果",
	"_magic": "魔力",
	"_benefit": "地利战力",
	"_buff_level": "层数",
}

static func shown_name(obj) -> String:
	if obj == null:
		return ""
	if obj.has_method("get_shown_name"):
		var s: String = str(obj.get_shown_name())
		if s != "":
			return s
	var n = obj.get("_name")
	return str(n) if n != null else ""

static func card_desc(obj) -> String:
	if obj == null:
		return ""
	var lines: Array[String] = []
	# 名字由金色标题展示，描述里不再重复
	for prop in obj.get_property_list():
		var pname: String = str(prop.get("name", ""))
		if not FIELD_LABELS.has(pname):
			continue
		var v = obj.get(pname)
		if v is BaseNumber:
			lines.append("%s：%d" % [FIELD_LABELS[pname], v.number])
		elif v is int or v is float:
			lines.append("%s：%d" % [FIELD_LABELS[pname], int(v)])
	var attrs = obj.get("_attributes")
	if attrs is Array and attrs.size() > 0:
		# 复用 Attributes 的通用显示名映射（含自定义属性注册），不重复造表
		lines.append("属性：" + "、".join(Attributes.get_shown_attributes(attrs)))
	var cat = obj.get("_category")
	if cat != null and str(cat) != "":
		lines.append("类别：" + ATTACK_CATEGORY_LABELS.get(str(cat), str(cat)))
	#卡面印的打出条件与提示行：文案来自卡自己的数据，这里只负责逐条列出。
	#注意 Object.get 只接受属性名一个参数，不能带默认值
	var notes = obj.get("_shown_notes")
	if notes is Array:
		for note in notes:
			if str(note) != "":
				lines.append(str(note))
	var play_reqs = obj.get("_play_requirements")
	if play_reqs is Array:
		for req in play_reqs:
			if req is Dictionary and str(req.get("shown_note", "")) != "":
				lines.append(str(req["shown_note"]))
	var effs = obj.get("_effects")
	if effs is Array and effs.size() > 0:
		var es: Array[String] = []
		for e in effs:
			# 选项类效果(单选/多选，如令咒三选一)：本体没有独立说明，把各选项文案列出来
			if e is BaseEffect and e.has_options():
				for opt in e._options:
					var opt_name: String = str(opt.get("shown_option_name", ""))
					if opt_name != "":
						es.append(opt_name)
				continue
			var en: String = shown_name(e)
			if en != "":
				es.append(en)
		if es.size() > 0:
			# 效果不带前缀标签，多条换行缩进罗列
			lines.append("\n　　".join(es))
	return "\n".join(lines)

static func token_desc(obj) -> String:
	var lines: Array[String] = []
	var lvl = obj.get("_buff_level")
	var lvl_num: int = (lvl.number as int) if lvl is BaseNumber else 1
	if lvl_num > 1:
		lines.append("层数：%d" % lvl_num)
	var effs = obj.get("_effects")
	# 带选项的效果按"效果名 + 它自己的选项"成组收，没有选项的效果只留名字。
	# 同一个效果既可能挂在状态自己身上、又被持有者的 related_effect_names 指到，
	# 这里按效果名记一遍，避免同一条列两次
	var groups: Array = []
	var flat: Array = []
	var named: Array = []
	if effs is Array:
		for e in effs:
			if not (e is BaseEffect):
				continue
			named.append(e._name)
			if e.has_options():
				var options: Array = []
				for opt in e._options:
					var option_name: String = str(opt.get("shown_option_name", ""))
					if option_name != "":
						options.append(option_name)
				if not options.is_empty():
					groups.append({"head": shown_name(e), "options": options})
			else:
				var en: String = shown_name(e)
				if en != "":
					flat.append(en)
	var related: Array = obj.get("_related_effect_names")
	var owner = obj.from.get_ref() if obj.from is WeakRef else obj.from
	if related is Array and owner != null:
		var owner_effects = owner.get("_effects")
		if owner_effects is Array:
			for effect_name in related:
				for eff in owner_effects:
					if eff is BaseEffect and eff._name == str(effect_name):
						if named.has(eff._name):
							break
						var shown: String = shown_name(eff)
						if shown != "" and not flat.has(shown):
							flat.append(shown)
						break
	# 只有一个带选项的效果时平铺（老口径，多一行效果名是噪音）；
	# 有多个时按效果名分组——几个效果的选项名可能完全相同，平铺会看成同一条列了两遍
	if groups.size() > 1:
		var body: Array = []
		for group in groups:
			var head: String = str(group["head"])
			if head != "":
				body.append(head)
			for option_name in group["options"]:
				body.append("　　" + str(option_name))
		body.append_array(flat)
		if not body.is_empty():
			lines.append("\n".join(body))
		return "\n".join(lines)
	var es: Array = []
	if groups.size() == 1:
		es.append_array(groups[0]["options"])
	es.append_array(flat)
	if not es.is_empty():
		lines.append("\n　　".join(es))
	return "\n".join(lines)
