extends RefCounted

const Identity = preload("res://scripts/net/identity/player_identity.gd")
const Names = preload("res://scripts/net/identity/player_name_rules.gd")
var pending:Dictionary = {}
var authenticated:Dictionary = {}
var profiles:Dictionary = {}
var room_id:String = ""
var instance_id:String = ""
var timeout_msec:int = 10000
var max_pending:int = 64
var max_profile_bytes:int = 8192
var error:String = ""

func configure(room:String, instance:String) -> bool:
	pending.clear()
	authenticated.clear()
	profiles.clear()
	room_id = room
	instance_id = instance
	return not room.is_empty() and not instance.is_empty()

static func context(profile:Dictionary, room:String, instance:String, peer:int) -> String:
	return JSON.stringify(["FateDomination LAN identity v1",room,instance,peer,profile.public_key,profile.username,profile.nickname])

func begin(peer:int, profile:Dictionary, now:int) -> Dictionary:
	error = ""
	expire(now)
	if peer <= 1 or room_id.is_empty() or instance_id.is_empty() or pending.has(peer) or authenticated.has(peer) or pending.size() >= max_pending:
		return _reject("身份挑战状态无效或超过预算")
	if profile.size() != 3 or not profile.get("public_key") is String or not profile.get("username") is String or not profile.get("nickname") is String:
		return _reject("身份登记字段无效")
	if var_to_bytes(profile).size() > max_profile_bytes or profile.public_key.to_utf8_buffer().size() > 4096:
		return _reject("身份登记超过消息预算")
	var reason:String = Names.username_error(profile.username)
	if not reason.is_empty(): return _reject(reason)
	if Identity.fingerprint(profile.public_key).is_empty(): return _reject("身份公钥无效")
	var challenge:PackedByteArray = Crypto.new().generate_random_bytes(32)
	if challenge.size() != 32: return _reject("无法创建身份挑战")
	var saved:Dictionary = profile.duplicate(true)
	pending[peer] = {"profile":saved,"challenge":challenge,"deadline":now+timeout_msec,"room":room_id,"instance":instance_id}
	return {"kind":"lan_identity_challenge","challenge":challenge,"peer":peer,"room":room_id,"instance":instance_id}

func prove(peer:int, args:Dictionary, now:int) -> Dictionary:
	error = ""
	if not pending.has(peer): return _reject("没有可用的身份挑战")
	var record:Dictionary = pending[peer]
	pending.erase(peer) # 每次尝试都消费挑战，包括错误证明。
	if args.size() != 4 or not args.get("signature") is PackedByteArray or args.get("peer") != peer or args.get("room") != room_id or args.get("instance") != instance_id:
		return _reject("身份挑战连接或房间实例不匹配")
	if now >= record.deadline or record.room != room_id or record.instance != instance_id:
		return _reject("身份挑战已过期或房间已替换")
	var profile:Dictionary = record.profile
	if not Identity.verify_challenge(profile.public_key,record.challenge,args.signature,context(profile,room_id,instance_id,peer)):
		return _reject("密钥身份认证失败")
	var id:String = Identity.fingerprint(profile.public_key)
	for other in profiles:
		if other != id and profiles[other].username == profile.username: return _reject("用户名已被使用")
	profiles[id] = profile
	authenticated[peer] = id
	return {"kind":"lan_identity_ready","identity":id,"username":profile.username,"nickname":profile.nickname,"peer":peer,"room":room_id,"instance":instance_id}

func forget(peer:int) -> void:
	pending.erase(peer)
	authenticated.erase(peer)

func expire(now:int) -> void:
	for peer in pending.keys():
		if now >= pending[peer].deadline: pending.erase(peer)

func _reject(reason:String) -> Dictionary:
	error = reason
	return {}
