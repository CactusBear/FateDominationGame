@tool
class_name McpServerVersionCheck
extends RefCounted

## Published v4 compatibility value. Lifecycle owns the authenticated
## handshake and episode transition; this class intentionally owns no timer,
## connection, or manager reference.


## Leading numeric `major.minor.patch` of a version as `[major, minor, patch]`,
## or `[]` when it does not start that way (a dev build, a malformed pin).
## A suffix after the patch (`4.0.3+local.1`, `4.1.0-rc1`) is ignored; a
## dangling separator (`4.0.3+`) is not a version.
static func version_tuple(version: String) -> Array:
	var regex := RegEx.create_from_string("^(\\d+)\\.(\\d+)\\.(\\d+)(?:$|[.+-][0-9A-Za-z][0-9A-Za-z.+-]*$)")
	var found := regex.search(version.strip_edges())
	if found == null:
		return []
	return [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))]


static func compare(a: Array, b: Array) -> int:
	for index in range(3):
		if int(a[index]) != int(b[index]):
			return -1 if int(a[index]) < int(b[index]) else 1
	return 0


## `candidate` is a parseable version older than `reference` within the same
## major version. Unparseable, equal, newer, or another major all read false:
## a caller may only replace what it can prove is older than itself.
static func is_older_same_major(candidate: String, reference: String) -> bool:
	var candidate_tuple := version_tuple(candidate)
	var reference_tuple := version_tuple(reference)
	if candidate_tuple.is_empty() or reference_tuple.is_empty():
		return false
	if int(candidate_tuple[0]) != int(reference_tuple[0]):
		return false
	return compare(candidate_tuple, reference_tuple) < 0


static func evaluate(actual_version: String, expected_version: String) -> Dictionary:
	if actual_version.is_empty():
		return {"compatible": false, "reason": "missing_version"}
	var compatible := actual_version == expected_version
	return {
		"compatible": compatible,
		"reason": "" if compatible else "version_mismatch",
	}
