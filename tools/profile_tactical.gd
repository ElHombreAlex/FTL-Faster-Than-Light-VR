extends SceneTree

var elapsed := 0.0
var sample_seconds := 10.0
var counts := {"screen": 0, "hud": 0}
var frame_times: Array[float] = []
var surfaces: Array[Node3D] = []
var output_name := "tactical-client-profile.json"
var full_main := false
var capture_ages: Array[float] = []
var process_times: Array[float] = []
var main: Node3D
var mock_tracker: XRControllerTracker


func _initialize() -> void:
	Engine.max_fps = 90
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--output="): output_name = value.trim_prefix("--output=")
		if value.begins_with("--seconds="): sample_seconds = float(value.trim_prefix("--seconds="))
		if value == "--full-main": full_main = true
	call_deferred("_run")


func _run() -> void:
	if full_main:
		main = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
		main.set_script(load("res://tools/profile_main.gd"))
		root.add_child(main)
		# Exercise the complete VR presentation and CPU update paths in a
		# desktop Vulkan viewport. This does not measure stereo headset FPS.
		main.xr_active = true
		main.initial_table_placed = true
		mock_tracker = XRControllerTracker.new()
		mock_tracker.type = XRServer.TRACKER_CONTROLLER
		mock_tracker.name = "left_hand"
		mock_tracker.set_pose("default", Transform3D(Basis.IDENTITY, Vector3(-0.4, 2.05, 2.0)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(mock_tracker)
		main._poll_bridge_state()
		surfaces.assign([main.map_surface, main.hud_surface])
	else:
		var camera := Camera3D.new()
		camera.position = Vector3(0, 0, 3)
		camera.current = true
		root.add_child(camera)
		for entry in [["screen", "screen_frame.png"], ["hud", "hud_frame.png"]]:
			var surface: Node3D = load("res://scripts/hud_surface.gd").new()
			surface.frame_file = entry[1]
			root.add_child(surface)
			surfaces.append(surface)
	for i in range(surfaces.size()):
		surfaces[i].canvas.texture_changed.connect(_count.bind("screen" if i == 0 else "hud"))
	await create_timer(1.0).timeout
	counts = {"screen": 0, "hud": 0}
	capture_ages.clear()
	if full_main:
		main.profile_poll_ms.clear()
		main.profile_process_ms.clear()
	var started := Time.get_ticks_usec()
	while elapsed < sample_seconds:
		var before := Time.get_ticks_usec()
		await process_frame
		frame_times.append(float(Time.get_ticks_usec() - before) / 1000.0)
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		elapsed = float(Time.get_ticks_usec() - started) / 1000000.0
	frame_times.sort()
	capture_ages.sort()
	process_times.sort()
	var report := {"seconds": elapsed, "screen_texture_updates": counts.screen,
		"hud_texture_updates": counts.hud, "screen_delivered_fps": counts.screen / elapsed,
		"hud_delivered_fps": counts.hud / elapsed, "client_fps": frame_times.size() / elapsed,
		"client_frame_ms_p95": frame_times[int(frame_times.size() * 0.95)],
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"full_main": full_main, "stereo_headset_measurement": false,
		"client_process_ms_p95": process_times[int(process_times.size() * 0.95)],
		"screen_capture_age_ms_p95": capture_ages[int(capture_ages.size() * 0.95)] if not capture_ages.is_empty() else -1.0,
		"screen_transport_size": str(surfaces[0].canvas.frame_image.get_size()) if surfaces[0].canvas.frame_image != null else "missing",
		"screen_viewport_size": str(surfaces[0].viewport.size)}
	if full_main:
		main.profile_poll_ms.sort()
		main.profile_process_ms.sort()
		report.native_poll_ms_p95 = main.profile_poll_ms[int(main.profile_poll_ms.size() * 0.95)]
		report.native_poll_ms_max = main.profile_poll_ms.back()
		report.main_cpu_ms_p95 = main.profile_process_ms[int(main.profile_process_ms.size() * 0.95)]
		report.main_cpu_ms_max = main.profile_process_ms.back()
	var file := FileAccess.open("res://local_game_data/" + output_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TACTICAL_CLIENT_PROFILE ", JSON.stringify(report))
	quit()


func _count(stream: String) -> void:
	counts[stream] += 1
	if stream == "screen" and not surfaces.is_empty() and surfaces[0].canvas.capture_time_unix > 0:
		capture_ages.append((Time.get_unix_time_from_system() - surfaces[0].canvas.capture_time_unix) * 1000.0)
