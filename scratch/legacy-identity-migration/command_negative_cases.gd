extends RefCounted

## 静态交付夹具：未运行 Godot；主代理可在串行运行验收时调用 run()。
static func run() -> Array[String]:
	var errors:Array[String] = []
	var migration = preload("res://scripts/net/legacy_identity_migration.gd")
	var console = preload("res://scripts/net/server_console_channel.gd").new()
	console.configure("",null,null)
	for text in ["{}","[]","null",'{"01":2}','{"0":2}','{"2":true}','{"2":2.5}','{"2":"fingerprint"}','{"2":2,"2":3}','{"2":2,"3":2}','{"member_identities":{"2":"key"}}']:
		if migration.parse_approval("legacy_approved",text).ok: errors.append("非法映射被接受：" + text)
	if migration.parse_approval("true",'{"2":2}').ok: errors.append("缺显式审批标记")
	if not migration.parse_approval("legacy_approved",'{"2":2,"3":3}').ok: errors.append("合法显式映射被拒绝")
	var instance:String = "a".repeat(32)
	for command in ["room r legacy-approve", "room r legacy-reject -1", "room r legacy-reject -1 " + instance + " extra", "room r legacy-approve -1 " + instance + " true '{}'"]:
		if console.execute(command).ok: errors.append("非法命令被接受")
	for command in ["room r legacy-reject -1 " + instance, "room r legacy-approve -1 " + instance + " legacy_approved '{\"2\":2}'"]:
		var response:Dictionary = console.execute(command,false)
		if response.get("error") != "旧档迁移仅允许可信本机控制台": errors.append("公网管理员绕过本机隔离")
	return errors
