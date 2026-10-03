extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.xr_active = true
	scene.left_hand.transform = scene.camera.transform
	scene.nav_panel.transform = Transform3D(Basis.IDENTITY,Vector3(-0.3,-0.05,-1.05))
	scene.nav_panel.scale = Vector3.ONE * 0.6
	scene.nav_panel.visible = true
	scene.right_hand.transform = scene.camera.transform * Transform3D(Basis.IDENTITY,Vector3(0.25,-0.22,-0.3))
	# A simulated tracked ray uses the same drawing and picking path as XR.
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = "right_hand"
	tracker.set_pose("aim",scene.right_hand.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	for page in ["navigation","shortcuts","help","wheel"]:
		scene.wheel.visible = page == "wheel"
		if page == "wheel":
			scene._refresh_wheel()
			scene.wheel.global_transform = scene.camera.global_transform
			scene.wheel.global_position += -scene.camera.global_basis.z * 0.85 + scene.camera.global_basis.x * 0.30
			scene.wheel.choose(Vector2(0,1))
		scene.nav_page = page if page != "wheel" else "navigation"
		scene._refresh_navigation()
		scene.right_hand.look_at(scene.nav_panel.global_position,Vector3.UP)
		scene._update_pointer()
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://local_game_data/input-"+page+".png")
	XRServer.remove_tracker(tracker)
	quit()
