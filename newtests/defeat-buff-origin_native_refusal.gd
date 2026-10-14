extends "res://newtests/defeat-buff-origin_contract.gd"

# Real sticky audit refusal intentionally ends this process; no continuation ABI is claimed.
func run() -> void:
	active_child_registration_failure()
	print("RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
