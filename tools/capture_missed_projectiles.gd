extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const CombatEffects = preload("res://scripts/combat_effects.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var output := "res://local_game_data/miss_capture"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101b27")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -20, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var player := ShipModel.new()
	var enemy := ShipModel.new()
	world.add_child(player)
	world.add_child(enemy)
	player.build("kestral", false)
	enemy.build("rebel_squat", true)
	for ship in [player, enemy]:
		ship.set_process(false)
		ship.set_shields(0)
	player.position = Vector3(-1.8, 0, 0)
	enemy.position = Vector3(1.7, 0, 0)
	enemy.rotation.y = PI / 2.0 if int(enemy.layout_data.get("vertical", 0)) != 0 else PI
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	world.add_child(camera)
	camera.position = Vector3(1.3, 4.8, 5.2)
	camera.look_at(Vector3(1.3, 0, 0))
	var effects := CombatEffects.new()
	world.add_child(effects)
	effects.set_process(false)
	# Native-schema fixtures expose a missed flight independently of any game
	# launch. Only the input snapshot values drive progress and disappearance.
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "capture-miss", "target_room": 0}, player, enemy)
	effects.update_live_projectiles([{"id": "capture-miss", "progress": 0.76}])
	effects._process(0.1)
	var proof: Dictionary = {}
	proof["before"] = effects.shots[0]["node"].global_position
	await _capture(output, "01_before_miss")
	effects.resolve_live({"projectile_id": "capture-miss", "outcome": "miss"}, enemy)
	effects.update_live_projectiles([{"id": "capture-miss", "progress": 0.94, "missed": true}])
	effects._process(0.1)
	proof["passed"] = effects.shots[0]["node"].global_position
	await _capture(output, "02_passing_miss")
	effects.update_live_projectiles([{"id": "capture-miss", "progress": 0.5, "missed": true}])
	effects._process(0.1)
	proof["reordered"] = effects.shots[0]["node"].global_position
	await _capture(output, "03_reordered_stays_forward")
	effects.update_live_projectiles([{"id": "capture-miss", "progress": 1.3, "missed": true}])
	effects._process(0.1)
	proof["beyond"] = effects.shots[0]["node"].global_position
	await _capture(output, "04_beyond_target")
	effects.update_live_projectiles([])
	effects._process(1.1)
	proof["remaining_shots"] = effects.shots.size()
	proof["impacts"] = effects.impacts.size()
	await _capture(output, "05_native_absence")
	var file := FileAccess.open(output.path_join("proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "\t"))
	print("MISS_CAPTURE PASS snapshots=5 remaining_shots=", effects.shots.size(), " impacts=", effects.impacts.size(), " output=", output)
	quit(0)


func _capture(output: String, name: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	assert(result == OK, "Miss capture must save its rendered frame")
