extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.003, 0.008)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.6, 0.75)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.8, 2.0)
	camera.look_at(Vector3(0.0, 1.8, -1.0))
	camera.current = true
	var space: Node3D = load("res://scripts/space_environment.gd").new()
	stage.add_child(space)
	space.build()
	for kind in ["clear", "asteroid", "sun", "storm", "nebula", "pulsar"]:
		space.apply_state({"hazard": kind})
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://local_game_data/environment_%s.png" % kind))
	print("ENVIRONMENT_CAPTURE PASS")
	quit()
