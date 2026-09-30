extends Node

## 临时探针：采样截图里各卡片的像素颜色，判断"淡金色"来自何处。

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var dir := ProjectSettings.globalize_path("res://tests/runtime_reports")
	for f in ["handoff_b_f00.png", "handoff_d_f16.png"]:
		var img := Image.load_from_file(dir + "/" + f)
		if img == null:
			print("=== ", f, " load FAILED")
			continue
		print("=== ", f, " size=", img.get_size())
		for p in [[132, 120, "card1-body"], [100, 68, "card1-edge-in"], [34, 120, "card1-left-out"], [322, 120, "card2-body"], [512, 120, "card3-body"], [240, 120, "gap1-2"], [148, 120, "card1-right"]]:
			var x: int = p[0]
			var y: int = p[1]
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				print("===   ", p[2], " @(", x, ",", y, ")=", img.get_pixel(x, y))
	get_tree().quit()
