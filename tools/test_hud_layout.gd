extends SceneTree

const Anchor = preload("res://scripts/hud_anchor.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _check_clearance(scene: Node3D, message: String) -> void:
	var ship := Anchor.transformed_bounds(scene._player_hud_local_bounds(), scene.player_ship.global_transform)
	var panel := Anchor.panel_bounds(scene.hud_surface.global_transform, scene.hud_surface.surface_size)
	check(not Anchor.overlaps_ship(scene.hud_surface.global_transform, scene.hud_surface.surface_size, scene.player_ship.global_transform, scene._player_hud_local_bounds(), Anchor.CLEARANCE - 0.001), message)
	if scene.hud_anchor.blocked:
		check(panel.position.y >= ship.end.y + Anchor.CLEARANCE - 0.001, "A blocked HUD must stop entirely above the transformed ship/shield volume")


func run() -> void:
	var scene := load("res://tools/input_harness.gd").new() as Node3D
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.hud_surface.set_process(false)
	scene.demo_mode = false
	scene.xr_active = true
	scene.origin.transform = Transform3D.IDENTITY
	scene.camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 1.3))
	scene.hud_state = {"ready": true, "ui_mode": "game", "paused": true}
	scene._recenter()
	scene._update_hud()
	scene._position_hud(0.0, true)
	check(scene.hud_surface.get_parent() == scene and scene.gameplay_hud, "Gameplay HUD must permit collision-clamped headset-relative placement")
	check(scene.hud_surface.source_rect == Rect2(0, 0, 872, 510), "Gameplay must retain upper status and complete crew roster while excluding the entire bottom HUD")
	check(is_equal_approx(scene.hud_surface.global_basis.x.length(), 1.0) and is_equal_approx(scene.hud_surface.surface_size.x, 1.10), "HUD readability must use fixed world metres, independent of tabletop scale")
	check(scene.pause_label.get_parent() == scene.hud_surface and scene.pause_label.visible and scene.pause_label.position.y > scene.hud_surface.surface_size.y / 2, "Pause must remain visible above the compact HUD after the lower UI is removed")
	check(scene.tracking_label.get_parent() == scene.camera and scene.tracking_label.position.x > 0 and scene.tracking_label.position.y > -.5, "Modifier/controller status must stay accessible at the lower right of the view")
	_check_clearance(scene, "Initial HUD must clear the hull and shields")
	check(scene.hud_surface.global_position.z < scene.camera.global_position.z, "Initial HUD should remain in front of the headset")
	# Move the table out of the viewer's path. The head-relative HUD must follow
	# position, pitch, yaw and roll instead of staying anchored to that table.
	scene.tabletop_root.position = Vector3(8, 4, 8)
	scene.hud_anchor.reset()
	scene._position_hud(0.0, true)
	check(not scene.hud_anchor.blocked and scene.hud_surface.global_position.is_equal_approx(scene.camera.get_camera_transform() * Anchor.HEAD_OFFSET), "Empty space must use the headset-relative pose even if a distant ship is higher")
	scene.camera.position += Vector3(.02, .01, .01)
	scene.camera.rotation = Vector3(-.2, .25, .12)
	scene._position_hud(1.0 / 90)
	check(scene.hud_surface.global_position.is_equal_approx(scene.camera.get_camera_transform() * Anchor.HEAD_OFFSET), "Unobstructed HUD must follow headset motion immediately")
	check(scene.hud_surface.global_basis.is_equal_approx(scene.camera.get_camera_transform().basis), "Unobstructed HUD rotation must preserve headset-relative framing")
	scene.camera.rotation = Vector3.ZERO
	scene._recenter()
	scene.camera.rotation.x = -.85
	scene._position_hud(0.0, true)
	check(scene.hud_anchor.blocked and scene.hud_anchor.lift > 0, "Looking down toward the ship must engage the HUD height stop")
	_check_clearance(scene, "Looking down must not tunnel the HUD through the ship")
	var stopped_ship: AABB = Anchor.transformed_bounds(scene._player_hud_local_bounds(), scene.player_ship.global_transform)
	var stopped_panel: AABB = Anchor.panel_bounds(scene.hud_surface.global_transform, scene.hud_surface.surface_size)
	var gap: float = stopped_panel.position.y - stopped_ship.end.y
	check(gap >= .05 and gap < .07, "The blocked HUD must sit five to seven centimetres above the ship while retaining a safe gap")
	var clearance_lift: float = scene.hud_anchor.lift
	scene.camera.rotation.y = PI
	scene._position_hud(1.0 / 90)
	check(not scene.hud_anchor.blocked and scene.hud_anchor.lift > 0 and scene.hud_anchor.lift < clearance_lift, "Turning away must release the height stop smoothly")
	for frame in range(180):
		scene._position_hud(1.0 / 90)
	check(scene.hud_anchor.lift == 0 and scene.hud_surface.global_position.is_equal_approx(scene.camera.get_camera_transform() * Anchor.HEAD_OFFSET), "Once clear, the HUD must return fully to its headset anchor")
	scene.camera.rotation = Vector3.ZERO
	scene._recenter()
	for scale_value in [.2, .35, .8, 1.5]:
		for rotation_value in [Vector3.ZERO, Vector3(0, 1.2, 0), Vector3(.4, .7, .3)]:
			scene.tabletop_root.basis = Basis.from_euler(rotation_value).scaled(Vector3.ONE * scale_value)
			for height in [-.6, .0, .8]:
				scene.tabletop_root.position += Vector3(.3, height, -.1)
				for frame in range(10):
					scene._position_hud(1.0 / 90)
					_check_clearance(scene, "Scaled/rotated/grabbed ship must never intersect the HUD during smoothing")
				check(scene.hud_surface.global_transform.is_finite(), "Extreme placement fallback must stay finite")
	# Cropping changes geometry only, preserving every retained native pixel.
	var image := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	scene.hud_surface.canvas.frame_image = image
	for native in [Vector2i(35, 30), Vector2i(580, 50), Vector2i(50, 470)]:
		var world: Vector3 = scene.hud_surface.pixel_world(native)
		var normal: Vector3 = scene.hud_surface.global_basis.z.normalized()
		check(scene.hud_surface.ray_pixel(world + normal, -normal) == native, "Top/roster ray picks must preserve original native coordinates under rotation")
	var removed_world: Vector3 = scene.hud_surface.pixel_world(Vector2i(400, 670))
	check(scene.hud_surface.ray_pixel(removed_world + scene.hud_surface.global_basis.z, -scene.hud_surface.global_basis.z) == null, "Removed lower HUD must not intercept pointing at the world")
	var event_crop: Rect2 = scene.event_surface.source_rect
	var panel_crop: Rect2 = scene.world_surface.source_rect
	scene.hud_state.event_open = true
	scene.hud_state.panel_open = true
	scene._sync_hud_layout()
	check(scene.gameplay_hud and scene.event_surface.source_rect == event_crop and scene.world_surface.source_rect == panel_crop, "Gameplay top crop must not alter full native dialog/store/ship panel content")
	scene.hud_state = {"ready": false, "ui_mode": "menu"}
	scene._sync_hud_layout()
	scene._position_hud(0.0)
	check(not scene.gameplay_hud and scene.hud_surface.source_rect == Rect2(0, 0, 1280, 720), "Main menus must retain the entire original native screen")
	var expected: Vector3 = scene.camera.get_camera_transform() * Vector3(0, -.16, -1.8)
	check(scene.hud_surface.global_position.is_equal_approx(expected), "Full main menus must retain the original viewer-relative readable framing")
	scene.xr_active = false
	for mode in ["map_open", "tactical"]:
		scene.hud_state = {"ready": true, "ui_mode": "game", mode: true}
		scene._sync_hud_layout()
		check(not scene.gameplay_hud and scene.hud_surface.source_rect.size == Vector2(1280, 720), "Desktop native map/Tactical display must preserve full content and picking")
	scene.xr_active = true
	scene.hud_state = {"ready": true, "ui_mode": "game", "tactical": true}
	scene._sync_hud_layout()
	check(scene.gameplay_hud, "VR Tactical screen must retain the headset HUD while its hand screen shows full Tactical content")
	if DisplayServer.get_name() != "headless":
		await _capture(scene)
	scene.queue_free()
	print("HUD_LAYOUT_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func rendered() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(scene: Node3D) -> void:
	scene.camera.rotation.x = -.28
	scene._recenter()
	scene._position_hud(0.0, true)
	scene.pause_label.visible = false
	scene.hud_surface.canvas.use_original_frame = false
	# Color bands make a removed lower HUD an objective GPU check, and retained
	# roster/native positions independently test the crop rather than its math.
	var image := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(0, 0, 872, 100), Color.GREEN)
	image.fill_rect(Rect2i(0, 150, 100, 340), Color.BLUE)
	image.fill_rect(Rect2i(0, 550, 1280, 170), Color.RED)
	scene.hud_surface.canvas._accept_frame(image, "hud-layout-fixture")
	await rendered()
	var output: Image = scene.hud_surface.viewport.get_texture().get_image()
	check(output.get_pixel(600, 50).g > .8 and output.get_pixel(30, 650).b > .8, "GPU top crop must preserve both upper status and the long crew roster")
	var red_pixels := 0
	for y in range(0, output.get_height(), 5):
		for x in range(0, output.get_width(), 5):
			var pixel := output.get_pixel(x, y)
			if pixel.r > .8 and pixel.g < .2 and pixel.b < .2: red_pixels += 1
	check(red_pixels == 0, "No lower HUD pixels may leak into the cropped GPU texture")
	scene.hud_state = {"ready": false, "ui_mode": "menu"}
	scene._sync_hud_layout()
	await rendered()
	output = scene.hud_surface.viewport.get_texture().get_image()
	check(output.get_pixel(600, 650).r > .8, "Full native menus must retain their lower content after returning from gameplay crop")
	scene.hud_state = {"ready": true, "ui_mode": "game"}
	scene._sync_hud_layout()
	scene._position_hud(0.0, true)
	# Prefer an immutable native QA snapshot so a concurrent bridge frame cannot
	# change the fixture between its load and visual inspection.
	var native_path := "res://local_game_data/speed-tactical-return-hud_frame.png"
	if FileAccess.file_exists(native_path):
		var native := Image.new()
		native.load_png_from_buffer(FileAccess.get_file_as_bytes(native_path))
		scene.hud_surface.canvas._accept_frame(native, "hud-layout-owned-native")
		await rendered()
		scene.hud_surface.viewport.get_texture().get_image().save_png("res://local_game_data/hud-top-spatial-native.png")
		root.get_texture().get_image().save_png("res://local_game_data/hud-top-spatial-scene.png")
	# The fallback/demo uses the same crop; bottom weapon/reactor rows stay out.
	scene.hud_surface.canvas.original_frame = null
	scene.hud_surface.canvas.set_state({"crew": [{"name": "Roster test", "health": 100}], "paused": false})
	scene.hud_surface.canvas.request_redraw()
	await rendered()
	output = scene.hud_surface.viewport.get_texture().get_image()
	output.save_png("res://local_game_data/hud-top-spatial-demo.png")
	check(output.get_pixel(30, 690).a < .1, "Fallback/demo bottom power/reactor must also disappear under the native crop")
