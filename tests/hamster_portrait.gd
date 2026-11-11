extends SceneTree

const Habitat = preload("res://habitat.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 800)
	var habitat := Habitat.new()
	root.add_child(habitat)
	habitat.camera.position = Vector3(-2.0, 1.65, 4.0)
	habitat.camera.look_at(Vector3(0, 0.60, 0.1))
	habitat.camera.fov = 30.0
	var actor := {"pos": Vector2.ZERO, "state": "嗅", "phase": 0.4, "dir": 0.0}
	var arguments := OS.get_cmdline_user_args()
	var version := arguments[0] if not arguments.is_empty() else "1.4.0"
	for index in range(2):
		for pet in range(2):
			habitat.show_pet(pet, actor, pet == index)
		await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://dist/hamster-" + version + "-" + str(index) + ".png")
		if result != OK:
			printerr("仓鼠特写保存失败：", result)
			quit(1)
			return
	print("两只仓鼠特写已保存")
	quit()
