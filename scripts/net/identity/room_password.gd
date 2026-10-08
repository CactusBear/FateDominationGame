extends RefCounted

var verifier:Dictionary = {}

static func valid_state(value:Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 2: return false
	for key in ["salt","hash"]:
		if not value.get(key) is String or value[key].length() != 64 or not value[key].is_valid_hex_number(false): return false
	return true

func set_password(value:String) -> bool:
	if value.is_empty():
		verifier = {}
		return true
	var bytes:PackedByteArray = Crypto.new().generate_random_bytes(32)
	if bytes.size() != 32: return false
	var salt:String = bytes.hex_encode()
	verifier = {"salt":salt,"hash":(salt+value).sha256_text()}
	return true

func accepts(value:Variant) -> bool:
	if verifier.is_empty(): return true
	if not value is String: return false
	return Crypto.new().constant_time_compare((verifier.salt+value).sha256_text().to_utf8_buffer(),verifier.hash.to_utf8_buffer())
