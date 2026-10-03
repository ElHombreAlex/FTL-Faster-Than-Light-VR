extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://local_game_data/live_preview.png"))
	print("LIVE_RENDER ready=", scene.bridge_connected, " crew=", scene.player_ship.crew_nodes.size())
	quit()
