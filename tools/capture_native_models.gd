extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	var state_path := "res://local_game_data/live_state.json"
	var output_path := ""
	for argument in args:
		if argument.begins_with("--state="):
			state_path = argument.trim_prefix("--state=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	var side := "enemy" if args.has("--enemy") else "player"
	if not data.has(side):
		push_error("No native %s ship in the current snapshot" % side)
		quit(1)
		return
	var native_ship: Dictionary = data[side]
	var ship := ShipModel.new()
	root.add_child(ship)
	ship.build(str(native_ship.get("asset_key", native_ship.layout)), side == "enemy")
	ship.inspect_rooms = true
	ship.apply_live(native_ship)
	ship.simulation_paused = true
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101822")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.45
	environment.environment = settings
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.5
	root.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(2.0, maxf(ship.shield_radii.x, ship.shield_radii.z) * 2.35)
	var view_center := Vector3(ship.shield_center.x, 0, ship.shield_center.z)
	camera.position = view_center + Vector3(1.2, 2.3, 2.1)
	root.add_child(camera)
	camera.look_at(view_center)
	ship.set_viewer_position(camera.global_position)
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://local_game_data/native_models%s_preview.png" % ("_enemy" if side == "enemy" else ""))
	if not output_path.is_empty():
		path = ProjectSettings.globalize_path(output_path)
	root.get_texture().get_image().save_png(path)
	print("NATIVE_MODEL_CAPTURE ", side, " ", path, " crew=", ship.crew_nodes.size(), " doors=", ship.door_nodes.size(), " drones=", ship.drone_nodes.size(), " hull_voxels=", ship.hull_voxel_count)
	var weapon_charge_state: Array = []
	for slot in range(mini(ship.weapon_nodes.size(), native_ship.get("weapons", []).size())):
		var weapon: Node3D = ship.weapon_nodes[slot]
		weapon_charge_state.append({"slot": slot, "name": weapon.weapon_name, "powered": weapon.powered,
			"charge_fraction": weapon.charge, "stored_shots": weapon.charge_level, "stored_max": weapon.charge_max})
	var door_tiers: Dictionary = {}
	for door in ship.door_nodes.values():
		var tier: int = door.get_meta("blast_tier", 0)
		door_tiers[tier] = int(door_tiers.get(tier, 0)) + 1
	print("NATIVE_VISUAL_STATE weapons=", weapon_charge_state, " fire_tiles=", ship.room_hazards.fire_points.size(),
		" breach_tiles=", ship.room_hazards.breach_points.size(), " effective_door_tiers=", door_tiers)
	var crew_facing: Array = []
	for miniature in ship.crew_nodes.values():
		var model: Node3D = miniature.get_node("Model")
		if model.has_method("face_viewer"):
			var direction: Vector3 = ship.to_local(camera.global_position) - miniature.position
			crew_facing.append({"id": miniature.get_meta("crew_id"), "state": model.animation_state,
				"visible": miniature.visible,
				"yaw_error": absf(wrapf(model.rotation.y - atan2(-direction.x, -direction.z), -PI, PI)),
				"body_pitch": model.rotation.x, "body_roll": model.rotation.z})
		elif model.get("family") != null:
			crew_facing.append({"id": miniature.get_meta("crew_id"), "drone_family": model.family, "visible": miniature.visible})
	print("NATIVE_CREW_FACING ", crew_facing)
	var drone_models: Array = []
	for native_drone in native_ship.get("drones", []):
		var drone_id := str(native_drone.get("id", ""))
		if ship.drone_nodes.has(drone_id):
			var model: Node3D = ship.drone_nodes[drone_id]
			drone_models.append({"id": drone_id, "name": model.drone_name, "family": model.family,
				"position_error": model.position.distance_to(ship.pixel_point(native_drone, 0.3)),
				"angle_error": absf(wrapf(model.rotation.y + deg_to_rad(float(native_drone.get("angle", 0))), -PI, PI))})
	print("NATIVE_DRONE_MODELS ", drone_models)
	var outside_footprint := 0
	var outside_volume := 0
	var outside_native_footprint := 0
	var max_native_radial := 0.0
	var shape: Dictionary = native_ship.get("shield_shape", {})
	var native_radii := Vector2(float(shape.get("a", 0)) / 35.0 * ship.TILE, float(shape.get("b", 0)) / 35.0 * ship.TILE)
	var hull: MultiMeshInstance3D = ship.get_node_or_null("ExtrudedHull")
	if hull != null:
		for i in range(hull.multimesh.instance_count):
			var transform := hull.multimesh.get_instance_transform(i)
			if native_radii.x > 0 and native_radii.y > 0:
				var delta := transform.origin - ship.shield_center
				var radial := Vector2(delta.x / native_radii.x, delta.z / native_radii.y).length()
				max_native_radial = maxf(max_native_radial, radial)
				outside_native_footprint += 1 if radial > 1.0 else 0
			var local := (transform.origin - ship.shield_center) / ship.shield_radii
			if local.x * local.x + local.z * local.z > 1.0:
				outside_footprint += 1
			local.y -= transform.basis.y.length() * 0.5 / ship.shield_radii.y
			if local.length_squared() > 1.0:
				outside_volume += 1
	var max_room_alignment_px := 0.0
	var max_mount_alignment_px := 0.0
	var native_weapons: Array = native_ship.get("weapons", [])
	var source_mounts: Array = ship.layout_data.get("weapon_mounts", [])
	for slot in range(mini(native_weapons.size(), source_mounts.size())):
		var native_mount: Dictionary = native_weapons[slot].get("mount", {})
		if not native_mount.is_empty():
			var source_mount: Dictionary = source_mounts[slot]
			max_mount_alignment_px = maxf(max_mount_alignment_px, Vector2(float(native_mount.x) - float(source_mount.x), float(native_mount.y) - float(source_mount.y)).length())
	var outside_corners := 0
	var max_corner_radius := 0.0
	for point in ship.shield_fit_points:
		var radius: float = ((point - ship.shield_center) / ship.shield_radii).length()
		max_corner_radius = maxf(max_corner_radius, radius)
		outside_corners += 1 if radius > 1.001 else 0
	for room in native_ship.get("rooms", []):
		if ship.room_nodes.has(int(room["id"])):
			var native_center: Vector3 = ship.pixel_point(room.get("center", {}), 0.065)
			var error: Vector3 = native_center - ship.room_nodes[int(room["id"])].position
			max_room_alignment_px = maxf(max_room_alignment_px, Vector2(error.x, error.z).length() * 35.0 / ship.TILE)
	print("SHIELD_MODEL_GEOMETRY native=", shape, " local_center=", ship.shield_center, " radii=", ship.shield_radii, " padding=", ship.shield_fit_padding,
		" native_outside_footprint=", outside_native_footprint, " native_radial_max=", max_native_radial, " outside_footprint=", outside_footprint,
		" outside_keel=", outside_volume, " outside_hull_wall_corners=", outside_corners, " corner_radial_max=", max_corner_radius,
		" room_alignment_max_px=", max_room_alignment_px, " weapon_mount_alignment_max_px=", max_mount_alignment_px,
		" texture=", ship.layout_data.get("image_source_path", ""), " image_rect=", ship.layout_data.get("image_rect", {}))
	quit()
