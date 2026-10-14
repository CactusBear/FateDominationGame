extends RefCounted

## 无状态客户端身份协调器。只返回状态安装/请求/发布意图；不保留身份、连接或 Session。
## 来源与生命周期门由 Session 先执行，服务端认证/白名单/继承授权不在此复制。
const Identity = preload("res://scripts/net/identity/player_identity.gd")
const LanChallenge = preload("res://scripts/net/identity/lan_identity_challenge.gd")
const InheritanceInput = preload("res://scripts/net/identity/identity_inheritance_input.gd")
const Registry = preload("res://scripts/net/identity/player_registry.gd")

func handles(message:Dictionary) -> bool:
	return message.get("kind") in ["lan_identity_challenge","lan_identity_ready","server_identity_challenge","server_identity_ready","server_identity_permissions","inheritance_candidates","inheritance_ticket","identity"]

func receive(message:Dictionary, state:Dictionary, identity:Identity) -> Dictionary:
	var result:Dictionary = {"handled":true,"requests":[]}
	var profile:Dictionary = state.profile
	var context:Dictionary = state.lan_context
	match message.get("kind"):
		"lan_identity_challenge":
			if state.authority_host or state.server_request or not state.identity_sent or state.authenticated or profile.is_empty() or not context.is_empty(): return result
			if not message.get("challenge") is PackedByteArray or message.challenge.size() != 32 or message.get("peer") != state.connection or not message.get("room") is String or message.room.is_empty() or not message.get("instance") is String or message.instance.is_empty(): return result
			result.lan_context = {"peer":message.peer,"room":message.room,"instance":message.instance}
			var proof:Dictionary = result.lan_context.duplicate()
			proof.signature = identity.sign_challenge(message.challenge,LanChallenge.context(profile,message.room,message.instance,message.peer))
			result.requests.append({"kind":"lan_identity_proof","args":proof})
		"lan_identity_ready":
			if not state.server_request and not context.is_empty() and message.get("peer") == context.peer and message.get("room") == context.room and message.get("instance") == context.instance and message.get("identity") == identity.fingerprint(profile.public_key) and message.get("username") == profile.username and message.get("nickname") == profile.nickname:
				result.authenticated = true
				result.changed = true
		"server_identity_challenge":
			if state.server_request and state.identity_sent and message.get("challenge") is PackedByteArray:
				var profile_context:String = JSON.stringify([profile.public_key,profile.username,profile.nickname])
				result.requests.append({"kind":"server_identity_proof","args":{"signature":identity.sign_challenge(message.challenge,profile_context)}})
		"server_identity_ready":
			if not profile.is_empty() and message.get("identity") == identity.fingerprint(profile.public_key) and message.get("username") == profile.username and message.get("nickname") == profile.nickname:
				result.authenticated = true
				result.changed = true
		"server_identity_permissions":
			if state.authenticated and message.get("admin") is bool:
				result.admin = message.admin
				result.changed = true
		"inheritance_candidates":
			if message.get("model") is Dictionary and InheritanceInput.new().accept(message.model):
				result.request_floor = int(message.model.request_floor)
				result.candidates = message.model.duplicate(true)
		"inheritance_ticket":
			if message.get("member") is int and message.member > 0 and message.get("token") is String and Registry.valid_id(message.token):
				result.inheritance_ticket = {"member":message.member,"token":message.token}
		"identity":
			if message.get("member") is int and message.member > 1 and message.get("token") is String and message.token.length() == state.resume_token_length:
				result.resume_ticket = {"member":message.member,"token":message.token}
				result.requests.append({"kind":"identity_ack","args":{"token":message.token}})
				if state.data_revision > 0 and message.get("data_revision") == state.data_revision and state.assets_installed:
					result.requests.append({"kind":"data_ack","args":{"revision":state.data_revision}})
				result.changed = true
		_:
			result.handled = false
	return result