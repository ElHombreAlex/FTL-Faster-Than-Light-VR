extends SceneTree

func _initialize() -> void:
	call_deferred("record")

func record() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.0).timeout
	if not scene.bridge_connected:
		push_error("Live bridge required for this recording")
		quit(1)
		return
	var directory := ProjectSettings.globalize_path("res://local_game_data/recording")
	DirAccess.make_dir_recursive_absolute(directory)
	for i in range(200):
		var progress := float(i) / 199.0
		# Move the encounter to inspect its actual geometry; HUD stays on camera.
		scene.tabletop_root.rotation.y = sin(progress * TAU) * 0.9
		if i == 80:
			scene.enemy_ship.inspect_rooms = true
			scene.enemy_ship.apply_live(scene.enemy_ship.live_data)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("frame-%04d.png" % i))
		await create_timer(0.1).timeout
	print("LIVE_RECORDING frames=200 fps=10 simulation_paused=", scene.paused)
	quit()
