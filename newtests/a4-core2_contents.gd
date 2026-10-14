extends Node
const Domain = preload("res://scripts/system/atomic_execution_domain.gd")
var checks:int = 0
var failures:Array = []

func check(ok:bool, label:String) -> void:
	checks += 1
	print("CHECK ", label, " ", ok)
	if not ok: failures.append(label)

func _ready() -> void:
	var d = Domain.new()
	check(d.has_method(&"stage_container_contents"), "raw contents ABI present")
	if d.has_method(&"stage_container_contents"):
		var target:Array = [1]
		var alias:Array = target
		check(d.stage_container_contents(target, [1, 2], &"journal").status == "COMPLETED", "array growth staged")
		check(target == [1], "staging zero live writes")
		var window:Dictionary = Domain.acquire_publication_window()
		check(d.seal(window.window).status == "COMPLETED", "array growth sealed")
		check(d.install_sealed(window.window).status == "COMPLETED", "array growth installed")
		check(is_same(alias, target) and alias == [1, 2], "array growth retains target identity")
		Domain.release_publication_window(window.window)
	print("RESULT ", JSON.stringify({"suite":"A4-core2-contents", "checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
