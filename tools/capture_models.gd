extends SceneTree

const CrewModel = preload("res://scripts/voxel_crew.gd")
const WeaponModel = preload("res://scripts/voxel_weapon.gd")
const ShipModel = preload("res://scripts/ship_model.gd")
const DroneModel = preload("res://scripts/voxel_drone.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var weapons_only := OS.get_cmdline_user_args().has("--weapons")
	var drones_only := OS.get_cmdline_user_args().has("--drones")
	var crew_only := OS.get_cmdline_user_args().has("--crew")
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("111b25")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.6
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0 if drones_only else 2.5 if crew_only else 1.8 if weapons_only else 2.1
	camera.position = Vector3(0.6, 3.4 if drones_only or crew_only else 2.2, 4.3)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.2, 0.2))
	if drones_only:
		var kinds := ["combat", "beam", "defense", "hacking", "shield", "boarding", "anti_drone", "repair", "battle", "ion_boarder"]
		for i in range(kinds.size()):
			var drone := DroneModel.new()
			drone.position = Vector3((i % 5 - 2) * 0.75, 0.22, -0.95 if i < 5 else 0.95)
			drone.scale = Vector3.ONE * 2.8
			world.add_child(drone)
			var exterior: bool = kinds[i] not in ["repair", "battle", "ion_boarder"]
			drone.build({"kind": kinds[i], "species": kinds[i], "name": str(kinds[i]).to_upper() + "_1", "is_space": exterior,
				"deployed": true, "powered": true, "repairing": kinds[i] == "repair", "fighting": kinds[i] == "battle"})
			# Gallery poses are presentation fixtures, not synthetic game state.
			drone.rotation.y = -0.55 if exterior else PI + 0.2
			drone.animate(0.3)
			_label(world, str(kinds[i]).replace("_", " ").to_upper(), drone.position + Vector3(0, -0.16, 0.27))
	for i in range(CrewModel.SPECIES.size()):
		if weapons_only or drones_only:
			break
		var model := CrewModel.new()
		model.position = Vector3((i % 4 - 1.5) * (0.78 if crew_only else 0.63), 0.1,
			(-0.95 if i < 4 else 0.95) if crew_only else (-0.65 if i < 4 else 0.4))
		model.scale = Vector3.ONE * 3.0
		world.add_child(model)
		model.build(CrewModel.SPECIES[i])
		model.facing = PI + 0.3
		var states := ["work", "repair", "run", "fight"]
		var state: String = states[i % 4]
		model.set_state({"working": state == "work", "repairing": state == "repair", "running": state == "run", "fighting": state == "fight"})
		model.animate(0.3)
		model.face_viewer(camera.position - model.position, 1.0)
		_label(world, str(CrewModel.SPECIES[i]).to_upper() + "\n" + state, model.position + Vector3(0, -0.06, 0.20))
	for i in range(6):
		if drones_only or crew_only: break
		var weapon := WeaponModel.new()
		weapon.position = Vector3((i % 3 - 1) * 0.88, 0.12, -0.52 if i < 3 else 0.70) if weapons_only else Vector3((i - 2.5) * 0.48, 0.04, 1.35)
		weapon.scale = Vector3.ONE * (2.8 if weapons_only else 1.8)
		world.add_child(weapon)
		var kinds := ["laser", "ion", "beam", "missile", "bomb", "flak"]
		var fraction := float(i) / 5.0 if weapons_only else 1.0
		weapon.build({"kind": kinds[i], "powered": true, "charge_fraction": fraction, "charge_max": 4 if kinds[i] == "laser" else 1, "charge_level": 2 if kinds[i] == "laser" else 0})
		var label := Label3D.new()
		label.font = UiAssets.font("body")
		label.outline_size = 0
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.text = str(kinds[i]).to_upper() + (" • %d%% CHARGED" % roundi(fraction * 100) if weapons_only else "")
		label.font_size = 36
		label.pixel_size = 0.0025
		label.position = weapon.position + Vector3(0, -0.02, 0.30 if weapons_only else 0.13)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://local_game_data/drone_gallery.png" if drones_only else "res://local_game_data/crew_gallery.png" if crew_only else "res://local_game_data/weapon_gallery.png" if weapons_only else "res://local_game_data/model_gallery.png")
	root.get_texture().get_image().save_png(path)
	print("MODEL_CAPTURE ", path)
	quit()


func _label(world: Node3D, text: String, location: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiAssets.font("body")
	label.outline_size = 0
	label.font_size = 38
	label.pixel_size = 0.0025
	label.position = location
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(label)
