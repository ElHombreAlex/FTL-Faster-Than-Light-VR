extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const HullBar = preload("res://scripts/enemy_hull_bar.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func rendered() -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state_path := ""
	var output := "res://local_game_data/ship-status"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--state="): state_path = arg.trim_prefix("--state=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var recorded_native := not state_path.is_empty()
	var native: Dictionary = {}
	if recorded_native:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
		if parsed is Dictionary:
			native = parsed.get("enemy", {})
		check(not native.is_empty(), "--state must reference a recorded snapshot containing an enemy ship")
		if native.is_empty():
			quit(1)
			return
	else:
		# Portable synthetic fixture, using only assets from the documented
		# owner-local extraction. No private campaign snapshot is required.
		native = {"layout": "rebel_long", "asset_key": "rebel_long", "shield": 2}
	var ship := ShipModel.new()
	root.add_child(ship)
	ship.build(str(native.get("asset_key", native.get("layout", "auto_assault"))), true)
	check(ship.hull_voxel_count > 0, "Extract the requested owned ship assets before running the render test")
	if ship.hull_voxel_count == 0:
		quit(1)
		return
	ship.inspect_rooms = true
	ship.simulation_paused = true
	# Hold geometry steady so the restored image has a direct pixel oracle.
	ship.set_process(false)
	var state := native.duplicate(true)
	state["cloaked"] = false
	state["cloak_progress"] = 0.0
	ship.apply_live(state)
	if recorded_native:
		var shield_shape: Dictionary = native.get("shield_shape", {})
		check(not shield_shape.is_empty(), "A native snapshot must contain its authoritative shield_shape")
		var expected_center := ship.pixel_point(shield_shape.get("center", {}), ship.shield_center.y)
		check(ship.shield_center.is_equal_approx(expected_center), "The shield must preserve the actual native ellipse center without an extra enemy offset")
	var outside_corners := 0
	var maximum_radius := 0.0
	for point in ship.shield_fit_points:
		var radius: float = ((point - ship.shield_center) / ship.shield_radii).length()
		maximum_radius = maxf(maximum_radius, radius)
		if radius > 1.001: outside_corners += 1
	check(outside_corners == 0, "Every extruded hull and room-wall corner must fit inside the shield volume")
	check(ship.artillery_nodes.size() == native.get("artillery", []).size(), "Every recorded native artillery weapon must have a rendered model")
	for row in native.get("artillery", []):
		var gun: Node3D = ship.artillery_nodes[int(row.slot)]
		var rect: Dictionary = ship.layout_data.image_rect
		var expected_mount := Vector3((float(rect.x) + float(row.mount.x)) / 35.0 * ship.TILE - ship.layout_center.x * ship.TILE,
			0.14, (float(rect.y) + float(row.mount.y)) / 35.0 * ship.TILE - ship.layout_center.y * ship.TILE)
		check(gun.position.is_equal_approx(expected_mount), "Recorded native artillery mounts must remain aligned with the actual hull image")
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101822")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d4e7f2")
	settings.ambient_light_energy = 0.6
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
	await rendered()
	var normal := root.get_texture().get_image()
	normal.save_png(output + "-normal.png")
	state["cloaked"] = true
	state["cloak_progress"] = 1.0
	ship.apply_live(state)
	await rendered()
	var faded := root.get_texture().get_image()
	faded.save_png(output + "-cloaked.png")
	var changed_pixels := 0
	for y in range(normal.get_height()):
		for x in range(normal.get_width()):
			var before := normal.get_pixel(x, y)
			var after := faded.get_pixel(x, y)
			if Vector3(before.r - after.r, before.g - after.g, before.b - after.b).length() > 0.06:
				changed_pixels += 1
	check(changed_pixels > 15000, "Cloaking must visibly change the mobile Vulkan ship image, including batched hull geometry")
	state["cloaked"] = false
	state["cloak_progress"] = 0.0
	ship.apply_live(state)
	await rendered()
	var restored := root.get_texture().get_image()
	restored.save_png(output + "-restored.png")
	var normal_bytes := normal.get_data()
	var restored_bytes := restored.get_data()
	var restore_error := 0
	var restore_total_error := 0
	for i in range(normal_bytes.size()):
		var error := absi(int(normal_bytes[i]) - int(restored_bytes[i]))
		restore_error = maxi(restore_error, error)
		restore_total_error += error
	var restore_mean_error := float(restore_total_error) / maxf(normal_bytes.size(), 1)
	# Vulkan blending can round isolated edge pixels by two bytes when its
	# transparent pass is removed. Larger changes reveal a lingering fade.
	check(restore_error <= 2 and restore_mean_error < 0.001, "Uncloaking must return the rendered ship to its original pixels within isolated GPU byte rounding")
	var bar := HullBar.new()
	root.add_child(bar)
	bar.build()
	bar.set_state({"hull": 8, "hull_max": 15})
	await rendered()
	var hull_image := bar.viewport.get_texture().get_image()
	hull_image.save_png(output + "-hull-8-of-15.png")
	var green_runs := 0
	var previous_green := false
	for x in range(34, 754):
		var color := hull_image.get_pixel(x, 74)
		var green := color.g > 0.9 and color.r < 0.6 and color.a > 0.8
		if green and not previous_green:
			green_runs += 1
		previous_green = green
	check(green_runs == 8, "Eight of fifteen native hull points must render exactly eight lit pips, without the player mask's thirty separators")
	for i in range(15):
		var color := hull_image.get_pixel(roundi(bar.hull_cell_rect(i).get_center().x), 74)
		check((color.g > 0.9) == (i < 8), "Each rendered hull cell must match its native health unit")
	bar.set_state({"hull": 8, "hull_max": 22})
	await rendered()
	hull_image = bar.viewport.get_texture().get_image()
	hull_image.save_png(output + "-hull-8-of-22.png")
	green_runs = 0
	previous_green = false
	for x in range(34, 754):
		var color := hull_image.get_pixel(x, 74)
		var green := color.g > 0.9 and color.r < 0.6 and color.a > 0.8
		if green and not previous_green: green_runs += 1
		previous_green = green
	check(green_runs == 8, "A different native maximum must still display exactly eight remaining hull pips")
	bar.queue_free()
	var native_artillery_count := ship.artillery_nodes.size()
	var shield_padding := ship.shield_fit_padding
	ship.queue_free()
	await process_frame
	print("SHIP_STATUS_RENDER_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures,
		" fixture=", "recorded_native" if recorded_native else "synthetic_owned_asset",
		" renderer=", RenderingServer.get_current_rendering_method(), " cloak_changed_pixels=", changed_pixels,
		" restored_max_byte_error=", restore_error, " restored_mean_byte_error=", restore_mean_error,
		" hull_units=8/15+8/22 layout=", native.get("layout", ""),
		" artillery=", native_artillery_count, " outside_shield_corners=", outside_corners, " maximum_corner_radius=", maximum_radius,
		" shield_padding=", shield_padding, " output=", output)
	quit(0 if failures == 0 else 1)
