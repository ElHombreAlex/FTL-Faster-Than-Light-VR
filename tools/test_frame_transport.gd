extends SceneTree

var failures := 0
var transport_path := "res://local_game_data/transport-test/screen_frame.rgba"


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func write_frame(image: Image, sequence: int) -> void:
	var header := PackedByteArray()
	header.resize(36)
	for i in range(4): header[i] = "FVR1".to_ascii_buffer()[i]
	header.encode_u32(4, 1)
	header.encode_u32(8, image.get_width())
	header.encode_u32(12, image.get_height())
	header.encode_u32(16, 4)
	header.encode_u64(20, sequence)
	header.encode_double(28, 123.5)
	var file := FileAccess.open(transport_path, FileAccess.WRITE)
	file.store_buffer(header)
	file.store_buffer(image.get_data())
	file.close()


func run() -> void:
	var surface: Node3D = load("res://scripts/hud_surface.gd").new()
	surface.frame_file = "screen_frame.png"
	root.add_child(surface)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://local_game_data/transport-test"))
	surface.canvas.base_path = ProjectSettings.globalize_path("res://local_game_data/transport-test")
	surface.set_process(false)
	var image := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.8, 0.2, 1))
	image.set_pixel(536, 281, Color(0.9, 0.1, 0.2, 0))
	write_frame(image, 1)
	surface.canvas.poll_original_frame()
	check(surface.canvas.frame_image.get_size() == Vector2i(960, 540), "Live raw frames must retain their reduced transport dimensions")
	check(surface.canvas.frame_image.get_pixel(0, 0).g > 0.7, "Raw frame orientation must be top-down RGBA")
	var texture: Texture2D = surface.canvas.original_frame
	var count: int = surface.canvas.received_frames
	surface.canvas.poll_original_frame()
	check(surface.canvas.received_frames == count, "An unchanged raw sequence must skip texture upload")
	var broken := FileAccess.open(transport_path, FileAccess.WRITE)
	broken.store_buffer("FVR1".to_ascii_buffer())
	broken.close()
	surface.canvas.poll_original_frame()
	check(surface.canvas.received_frames == count and surface.canvas.original_frame == texture, "Truncated raw headers must retain the last complete frame")
	write_frame(image, 1)
	broken = FileAccess.open(transport_path, FileAccess.READ_WRITE)
	broken.seek(8)
	broken.store_32(5000)
	broken.close()
	surface.canvas.poll_original_frame()
	check(surface.canvas.received_frames == count, "Malformed raw dimensions must never allocate or upload a texture")
	check(surface.canvas.native_alpha_at(Vector2i(715, 375)) < 0.1, "Native alpha picking must sample reduced image coordinates")
	image.set_pixel(536, 281, Color(0.9, 0.1, 0.2, 1))
	write_frame(image, 2)
	surface.canvas.poll_original_frame()
	check(surface.canvas.original_frame == texture, "Reduced raw frames must reuse their GPU texture")
	surface.set_crop(Rect2(335, 90, 760, 570), Vector2(1.02, 0.765))
	var center: Variant = surface.ray_pixel(Vector3(0, 0, 1), Vector3.FORWARD)
	check(center == Vector2i(715, 375), "Floating map centers must round to native pixels rather than truncate")
	check(surface.canvas.native_used_rect() == Rect2i(0, 0, 1280, 720), "Panel bounds must be expressed in native pixels")
	check(surface.viewport.size == Vector2i(960, 540), "Tactical viewport must match its reduced transport")
	for i in range(4): await process_frame
	if RenderingServer.get_current_rendering_method() != "gl_compatibility" and not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		var rendered: Image = surface.viewport.get_texture().get_image()
		check(rendered.get_pixel(0, 0).g > 0.7, "Reduced native texture crop must render through the logical canvas")
	var full := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	full.fill(Color(0.2, 0.4, 0.9, 1))
	write_frame(full, 3)
	surface.canvas.poll_original_frame()
	check(surface.viewport.size == Vector2i(1280, 720), "Full-resolution jump-map frames must restore the native viewport resolution")
	check(surface.viewport.size_2d_override == Vector2i(1280, 720) and surface.viewport.size_2d_override_stretch, "Resolution changes must preserve the logical native canvas")
	check(surface.ray_pixel(Vector3(0, 0, 1), Vector3.FORWARD) == Vector2i(715, 375), "Native map picking must remain identical after resolution changes")
	write_frame(image, 4)
	surface.canvas.poll_original_frame()
	check(surface.viewport.size == Vector2i(960, 540), "Returning to Tactical must reduce the viewport again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(transport_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://local_game_data/transport-test"))
	print("FRAME_TRANSPORT_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
