extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const HullBar = preload("res://scripts/enemy_hull_bar.gd")
const Hazards = preload("res://scripts/room_hazards.gd")
const Voxels = preload("res://scripts/voxel_mesh.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Visual fixture only; no bridge, input, game state, or save writes.
	root.size = Vector2i(1400, 900)
	var ship := ShipModel.new()
	root.add_child(ship)
	var hazards := Hazards.new()
	ship.add_child(hazards)
	hazards.build()
	hazards.set_live(ship, {"rooms": [{"visible": true, "fire_tiles": [{"x": -90, "y": 115}], "breach_tiles": [{"x": 90, "y": 115}]}]})
	hazards.animate(0.42)
	for i in range(4):
		var door_center := Vector3((i - 1.5) * 0.49, 0.22, -0.02)
		var frame := Voxels.make([Voxels.block(Vector3(-0.077, 0, 0), Vector3(0.025, 0.11, 0.034), Color("516b77")),
			Voxels.block(Vector3(0.077, 0, 0), Vector3(0.025, 0.11, 0.034), Color("516b77")),
			Voxels.block(Vector3(0, 0.06, 0), Vector3(0.179, 0.01, 0.034), Color("516b77"))])
		frame.position = door_center
		frame.scale = Vector3.ONE * 2.0
		root.add_child(frame)
		for side in [-1, 1]:
			var leaf: MeshInstance3D = ship._make_door_leaf(i)
			leaf.position = door_center + Vector3(side * 0.031 * 2.0, 0, 0)
			leaf.scale = Vector3.ONE * 2.0
			root.add_child(leaf)
		_label(["STANDARD", "BLAST", "IMPROVED", "CREW BOOST"][i], Vector3((i - 1.5) * 0.49, 0.12, 0.10))
	var floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.025, 0.39)
	floor.mesh = box
	floor.position = Vector3(0, 0.065, 0.59)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("66767c")
	floor.material_override = material
	root.add_child(floor)
	_label("FIRE", Vector3(-0.46, 0.065, 0.80))
	_label("HULL BREACH", Vector3(0.46, 0.065, 0.80))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101923")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.45
	environment.environment = settings
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 1.6
	root.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.32
	camera.position = Vector3(0.55, 1.8, 2.5)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0.27, 0.33))
	var life := HullBar.new()
	root.add_child(life)
	life.build()
	life.set_state({"hull": 12, "hull_max": 20})
	life.position = Vector3(0, 0.56, -0.15)
	life.face_viewer(camera.position)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://local_game_data/ship_details_fixture.png")
	root.get_texture().get_image().save_png(path)
	print("SHIP_DETAIL_FIXTURE ", path, " fire_tiles=", hazards.fire_points.size(), " breach_tiles=", hazards.breach_points.size(), " door_tiers=0,1,2,3")
	quit()


func _label(text: String, location: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiAssets.font("body")
	label.outline_size = 0
	label.position = location
	label.font_size = 38
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.pixel_size = 0.0016
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	root.add_child(label)
