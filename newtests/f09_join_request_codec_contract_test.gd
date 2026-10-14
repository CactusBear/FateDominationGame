extends Node

const Codec = preload("res://scripts/net/identity/host_identity_request_codec.gd")
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var codec = Codec.new()
	for spectator in [false,true]:
		for name in ["合法昵称","","  ","含 / : @ 字符\n昵称","长".repeat(4096)]:
			var args:Dictionary = {"name":name,"spectator":spectator}
			var before:Dictionary = args.duplicate(true)
			check(codec.validate("join",args) == {"ok":true}, "字符串及布尔形状不附加昵称政策")
			check(args == before, "合法请求不变异")
	var invalid:Array = [
		{}, {"name":"昵称"}, {"spectator":false},
		{"name":null,"spectator":false}, {"name":7,"spectator":false},
		{"name":true,"spectator":false}, {"name":[],"spectator":false},
		{"name":{},"spectator":false}, {"name":"昵称","spectator":null},
		{"name":"昵称","spectator":0}, {"name":"昵称","spectator":1},
		{"name":"昵称","spectator":"false"}, {"name":"昵称","spectator":[]},
		{"name":"昵称","spectator":{}}
	]
	for args in invalid:
		var before:Dictionary = args.duplicate(true)
		check(codec.validate("join",args) == {"ok":false,"reason":"请求无效"}, "缺字段或错类型沿用原拒绝")
		check(args == before, "非法请求不变异")
	# 仅使用测试哨兵；不输出字典或凭据，真实认证仍由身份入口完成。
	var extra:Dictionary = {"name":"昵称","spectator":true,"password":"fixture-only","resume":"fixture-only","identity_key":"fixture-only","member_id":9,"nested":{"keep":[1,2]}}
	var extra_before:Dictionary = extra.duplicate(true)
	check(codec.validate("join",extra) == {"ok":true}, "额外身份字段不被信封层拒绝")
	check(extra == extra_before, "原字典完整保留供身份入口消费")
	# 凭据字段自身即使形状无效也不由本层代验；ok只代表两字段门通过。
	var unverified:Dictionary = {"name":"","spectator":false,"password":null,"resume":[],"identity_key":{},"member_id":-1}
	var unverified_before:Dictionary = unverified.duplicate(true)
	check(codec.validate("join",unverified) == {"ok":true}, "形状通过不代表凭据或成员已认证")
	check(unverified == unverified_before, "未验证身份字段仍完整保留")
	check(codec.validate("identity_candidates",{}) == {"ok":true}, "既有候选成功契约保留")
	check(codec.validate("identity_candidates",{"extra":true}) == {"ok":false,"reason":"候选查询不接受身份参数"}, "既有候选失败契约保留")
	check(codec.validate("identity_inherit",{"target_member":3,"successor_member":4,"revision":8}) == {"ok":true}, "既有继承成功契约保留")
	check(codec.validate("identity_inherit",{}) == {"ok":false,"reason":"继承请求字段无效"}, "既有继承失败契约保留")
	check(codec.validate("other",{}) == {"ok":false,"reason":"身份请求类型无效"}, "未知类型仍拒绝")
	print("RESULT "+JSON.stringify({"suite":"f09_join_request_codec_contract","checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
