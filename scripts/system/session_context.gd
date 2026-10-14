class_name SessionContext
extends RefCounted

## A graph-leaf keep-alive handle. Construction alone confers no provenance.
## The service's issuance record, not these fields, is the validation authority.
var _source_token:SessionToken
var _source_origin:StringName

func _init(source_token:SessionToken = null, source_origin:StringName = &"") -> void:
	_source_token = source_token
	_source_origin = source_origin

func token() -> SessionToken:
	return _source_token

func origin() -> StringName:
	return _source_origin
