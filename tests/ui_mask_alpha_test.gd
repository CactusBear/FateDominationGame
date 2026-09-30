extends Node

var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP real GPU alpha sampling requires window renderer")
		finish()
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var parent := Control.new()
	viewport.add_child(parent)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.size = Vector2(32, 32)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/ui_mask.gdshader")
	rect.material = material
	parent.add_child(rect)
	for shape in [0, 1]:
		material.set_shader_parameter("shape", shape)
		for alpha in [0.0, 0.25, 0.5, 1.0]:
			parent.modulate.a = alpha
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var pixel := viewport.get_texture().get_image().get_pixel(24, 16)
			checks += 1
			if absf(pixel.a - alpha) > 0.03:
				failures.append("shape %d alpha %.2f actual %.2f" % [shape, alpha, pixel.a])
	finish()

func finish() -> void:
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
