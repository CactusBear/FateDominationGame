extends RefCounted

const KEY_BITS:int = 2048
var _key:CryptoKey
var error:String = ""

func open(path:String) -> bool:
	error = ""
	var candidate:CryptoKey = CryptoKey.new()
	if FileAccess.file_exists(path):
		if candidate.load(path) != OK or candidate.is_public_only():
			error = "本地身份密钥无效，拒绝覆盖"
			return false
	else:
		candidate = Crypto.new().generate_rsa(KEY_BITS)
		if candidate == null:
			error = "无法生成身份密钥"
			return false
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			error = "无法创建身份目录"
			return false
		var temporary:String = path+"."+Crypto.new().generate_random_bytes(16).hex_encode()+".tmp"
		if candidate.save(temporary) != OK:
			error = "身份密钥保存失败"
			DirAccess.remove_absolute(temporary)
			return false
		if FileAccess.file_exists(path) or DirAccess.rename_absolute(temporary,path) != OK:
			DirAccess.remove_absolute(temporary)
			error = "身份密钥已存在或无法写入，请重新读取"
			return false
	_key = candidate
	return true

func public_key() -> String:
	return "" if _key == null else _key.save_to_string(true)

static func fingerprint(public_pem:String) -> String:
	var key:CryptoKey = CryptoKey.new()
	if key.load_from_string(public_pem,true) != OK: return ""
	return key.save_to_string(true).sha256_text()

func sign_challenge(challenge:PackedByteArray,context:String = "") -> PackedByteArray:
	if _key == null or challenge.size() != 32: return PackedByteArray()
	return Crypto.new().sign(HashingContext.HASH_SHA256,_digest(challenge,context),_key)

static func verify_challenge(public_pem:String,challenge:PackedByteArray,signature:PackedByteArray,context:String = "") -> bool:
	if public_pem.to_utf8_buffer().size() > 4096 or challenge.size() != 32 or signature.size() != KEY_BITS/8: return false
	var key:CryptoKey = CryptoKey.new()
	if key.load_from_string(public_pem,true) != OK: return false
	return Crypto.new().verify(HashingContext.HASH_SHA256,_digest(challenge,context),signature,key)

static func _digest(challenge:PackedByteArray,profile_context:String) -> PackedByteArray:
	var context:HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("FateDomination identity challenge v1\n".to_utf8_buffer())
	context.update(challenge)
	context.update(profile_context.to_utf8_buffer())
	return context.finish()
