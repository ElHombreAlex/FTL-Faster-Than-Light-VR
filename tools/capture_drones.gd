extends SceneTree

const DroneModel = preload("res://scripts/voxel_drone.gd")
const ShipModel = preload("res://scripts/ship_model.gd")
const CombatEffects = preload("res://scripts/combat_effects.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	var args := OS.get_cmdline_user_args()
	var firing_capture := args.has("--shots")
	var output := "res://local_game_data/drone_shots_preview.png" if firing_capture else "res://local_game_data/drone_gallery.png"
	for argument in args:
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101b27")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.58
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -25, 0)
	light.light_energy = 1.6
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	if firing_capture:
		_shots(world, camera)
	else:
		_gallery(world, camera)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output)
	var result := root.get_texture().get_image().save_png(path)
	print("DRONE_CAPTURE ", "shots" if firing_capture else "gallery", " result=", result, " path=", path)
	quit(result)


func _gallery(world: Node3D, camera: Camera3D) -> void:
	camera.size = 3.4
	camera.position = Vector3(0.4, 4.3, 5.0)
	camera.look_at(Vector3(0, 0.15, 0))
	var entries := [
		["combat", "COMBAT_1", "COMBAT I"], ["combat", "COMBAT_2", "COMBAT II"],
		["beam", "BEAM_1", "BEAM I"], ["beam", "BEAM_2", "BEAM II"],
		["defense", "DEFENSE_1", "DEFENSE I"], ["defense", "DEFENSE_2", "DEFENSE II"],
		["anti_drone", "ANTI_DRONE", "ANTI DRONE"], ["hacking", "HACKING", "HACKING"],
		["shield", "SHIELD", "SHIELD"], ["boarding", "BOARDER", "BOARDING"],
		["repair", "REPAIR", "REPAIR"], ["battle", "BATTLE", "BATTLE"],
		["ion_boarder", "ION_BOARDER", "ION BOARDER"]]
	for i in range(entries.size()):
		var entry: Array = entries[i]
		var drone := DroneModel.new()
		world.add_child(drone)
		var exterior: bool = entry[0] not in ["repair", "battle", "ion_boarder"]
		drone.build({"kind": entry[0], "species": entry[0], "name": entry[1],
			"is_space": exterior, "deployed": true, "powered": true})
		drone.position = Vector3((i % 5 - 2) * 0.87, 0.22, (i / 5 - 1) * 1.25)
		drone.scale = Vector3.ONE * 2.9
		drone.rotation.y = -0.65 if exterior else PI + 0.15
		_label(world, entry[2], drone.position + Vector3(0, -0.19, 0.30), 33)
	_label(world, "ORIGINAL VOXEL DRONES", Vector3(0, 0.35, -2.15), 43)


func _shots(world: Node3D, camera: Camera3D) -> void:
	# Explicit native-schema fixtures make the muzzle/trajectory capture
	# repeatable. They do not modify game state or claim native collision hits.
	var ship := ShipModel.new()
	world.add_child(ship)
	ship.build("kestral", false)
	ship.set_process(false)
	ship.apply_live({"rooms": [], "crew": [], "drones": [
		{"id": "capture-combat", "name": "COMBAT_2", "kind": "combat", "is_space": true,
			"deployed": true, "powered": true, "x": 470, "y": 105, "angle": 180},
		{"id": "capture-beam", "name": "BEAM_2", "kind": "beam", "is_space": true,
			"deployed": true, "powered": true, "x": 470, "y": 240, "angle": 180}]})
	ship.set_shields(0)
	var effects := CombatEffects.new()
	world.add_child(effects)
	effects.set_process(false)
	effects.spawn_shot({"kind": "laser", "drone_id": "capture-combat", "projectile_id": "capture-laser",
		"origin_space": 0, "target_space": 0, "origin_point": {"x": 470, "y": 105},
		"target": {"x": 235, "y": 105}, "outcome": "pending"}, ship, ship)
	effects.spawn_shot({"kind": "beam", "drone_id": "capture-beam", "projectile_id": "capture-beam",
		"origin_space": 0, "target_space": 0, "origin_point": {"x": 470, "y": 240},
		"target": {"x": 235, "y": 240}, "end_point": {"x": 235, "y": 265}, "outcome": "pending"}, ship, ship)
	effects.update_live_projectiles([{"id": "capture-laser", "progress": 0.22},
		{"id": "capture-beam", "progress": 0.5, "beam_point": {"x": 235, "y": 252}}])
	effects._process(0.1)
	var center: Vector3 = ship.pixel_point({"x": 365, "y": 175}, 0.22)
	camera.size = 1.6
	camera.position = center + Vector3(0.05, 1.9, 1.7)
	camera.look_at(center)
	_label(world, "COMBAT II  /  NATIVE LASER", ship.pixel_point({"x": 430, "y": 60}, 0.38), 24)
	_label(world, "BEAM II  /  NATIVE SWEEP", ship.pixel_point({"x": 430, "y": 300}, 0.8), 24, Color("1b3447"))
	print("DRONE_SHOT_GEOMETRY muzzle_laser=", effects.shots[0]["start"],
		" muzzle_beam=", effects.shots[1]["start"], " impacts=", effects.impacts.size())


func _label(world: Node3D, text: String, location: Vector3, size: int, color: Color = Color("d7e5e7")) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiAssets.font("body")
	label.font_size = size
	label.pixel_size = 0.0023
	label.modulate = color
	label.outline_modulate = Color("101b27")
	label.outline_size = 2
	label.no_depth_test = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = location
	world.add_child(label)
