extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var output_dir := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://local_game_data")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.008)
	world.environment = environment
	stage.add_child(world)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.8, 2.0)
	camera.look_at(Vector3(0.0, 1.8, -1.0))
	camera.current = true
	var space: Node3D = load("res://scripts/space_environment.gd").new()
	stage.add_child(space)
	space.build()
	space.set_process(false)
	space.set_travel_direction(Vector3.RIGHT)
	var label := Label.new()
	label.position = Vector2(28.0, 24.0)
	label.add_theme_font_size_override("font_size", 22)
	root.add_child(label)
	space.apply_state({"hazard": "clear", "jumping": false})
	label.text = "NORMAL: STARS SURROUND THE SHIP"
	await _save_frame(output_dir.path_join("jump_normal.png"))
	space.apply_state({"hazard": "sun", "jumping": true, "paused": true, "frozen": true})
	space._process(0.4)
	label.text = "NATIVE JUMP: HORIZONTAL SHIP TRAVEL >"
	await _save_frame(output_dir.path_join("jump_stretched.png"))
	space.set_travel_direction(Vector3(1.0, 0.0, -1.0))
	label.text = "NATIVE JUMP: SHIP BOW TURNED 45 DEGREES"
	await _save_frame(output_dir.path_join("jump_heading.png"))
	space.apply_state({"hazard": "clear", "jumping": true, "event_open": true, "paused": true})
	label.text = "ARRIVAL DIALOG: STARS RESTORED"
	await _save_frame(output_dir.path_join("jump_arrived.png"))
	print("JUMP_CAPTURE PASS ", output_dir)
	quit()


func _save_frame(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save jump capture: %s" % path)
