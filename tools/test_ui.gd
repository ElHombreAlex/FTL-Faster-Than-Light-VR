extends SceneTree

var failures := 0
var content_updates := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3)
	camera.current = true
	root.add_child(camera)
	var surface: Node3D = load("res://scripts/hud_surface.gd").new()
	surface.frame_file = "ui-test-frame.png"
	root.add_child(surface)
	surface.set_process(false)
	surface.canvas.texture_changed.connect(func(): content_updates += 1)
	var image := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.3, 1.0))
	image.save_png("res://local_game_data/ui-test-frame.png")
	surface.canvas.poll_original_frame()
	var texture: Texture2D = surface.canvas.original_frame
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var initial_updates := content_updates
	check(surface.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "HUD must use one-shot viewport rendering, rather than per-frame rendering")
	surface.set_state({"paused": true})
	surface.canvas.poll_original_frame()
	check(content_updates == initial_updates, "Unchanged native PNGs and live state must not schedule another native HUD render")
	image.fill(Color(0.7, 0.2, 0.3, 1.0))
	image.save_png("res://local_game_data/ui-test-frame.png")
	surface.canvas.poll_original_frame()
	check(surface.canvas.original_frame == texture, "Native PNG updates must reuse the existing GPU texture")
	check(surface.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Fresh native pixels must schedule one viewport render")
	check(surface.canvas.frame_image.get_pixel(0, 0).r > 0.6, "The refreshed image must also update picking pixels")
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	check(surface.viewport.get_texture().get_image().get_pixel(0,0).r > 0.6, "A second one-shot render must update the actual GPU viewport texture")
	var before_crop := content_updates
	surface.set_crop(Rect2(0, 0, 1280, 720), Vector2(2.85, 1.603125))
	check(content_updates == before_crop, "An identical crop must not schedule another render of a static hand screen")
	surface.set_crop(Rect2(300, 90, 650, 520), Vector2(1.02, 0.816))
	check(content_updates == before_crop + 1, "A real native panel crop change must render the new bounds once")
	var keyboard: Node3D = load("res://scripts/rename_keyboard.gd").new()
	root.add_child(keyboard)
	keyboard.set_entry({"active":true,"id":"ui-test","kind":"crew","text":"Dana","cursor":2})
	check(keyboard.visible and keyboard.value_label.text == "Da|na", "Native cursor and current name must display in the VR keyboard")
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	keyboard.viewport.get_texture().get_image().save_png("res://local_game_data/rename-keyboard.png")
	var result: Dictionary = keyboard.activate({"op":"shift"})
	check(result.is_empty() and not keyboard.upper, "Shift must change keyboard case without sending a game hotkey")
	result = keyboard.activate({"op":"confirm"})
	check(result.op == "confirm" and result.entry_id == "ui-test", "Done must submit the exact active native text field")
	keyboard.set_entry({"active":false})
	check(not keyboard.visible and keyboard.ray_hit(Vector3(0,0,1), Vector3.FORWARD).is_empty(), "An inactive keyboard must disappear and stop consuming controller rays")
	surface.queue_free()
	keyboard.queue_free()
	await process_frame
	print("UI_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
