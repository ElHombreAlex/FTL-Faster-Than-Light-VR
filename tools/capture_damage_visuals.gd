extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const Effects = preload("res://scripts/combat_effects.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Presentation fixtures only. No bridge, game process, input or save writes.
	root.size = Vector2i(1400, 900)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101923")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d4e7f2")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.2
	root.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.15
	camera.position = Vector3(0.1, 1.8, 1.1)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var ship := ShipModel.new()
	root.add_child(ship)
	ship.build("__damage_fixture__", true)
	ship.inspect_rooms = true
	ship.set_process(false)
	var rooms: Array = []
	for id in range(6):
		rooms.append({"id": id, "visible": id != 3, "oxygen": 0 if id == 5 else 100,
			"breach_tiles": [{"x": 175, "y": 35 if id == 4 else 105}] if id >= 4 else []})
	ship.apply_live({"rooms": rooms, "room_systems": {"0": "shields", "1": "weapons", "2": "engines", "3": "oxygen"},
		"system_status": [{"room_id": 0, "health": 4, "max_health": 4, "health_visible": true, "health_detail_visible": true},
			{"room_id": 1, "health": 2, "max_health": 4, "repair_progress": 0.55, "health_visible": true, "health_detail_visible": true},
			{"room_id": 2, "health": 0, "max_health": 2, "health_visible": true, "health_detail_visible": true},
			{"room_id": 3, "health": 1, "max_health": 3, "health_visible": true, "health_detail_visible": false}]})
	ship.room_hazards.animate(0.38)
	var labels := Node3D.new()
	root.add_child(labels)
	for item in [["FULL", 0], ["REPAIRING", 1], ["DISABLED", 2], ["SENSOR FOG", 3], ["AIR ESCAPING", 4], ["VACUUM", 5]]:
		var area: Area3D = ship.room_nodes[item[1]]
		_world_label(labels, item[0], area.position + Vector3(0, 0.11, 0.0), 0.0012)
	var title := _caption("SYSTEM CONDITION / NATIVE REPAIR / BREACHES", Vector2(46, 35), 34)
	var footer := _caption("Native damage changes room and utility colours. Repaired systems clear them; fog hides breach locations.", Vector2(46, 840), 23)
	await _capture("damage_rooms_fixture.png")
	labels.hide()
	title.text = "VANILLA CROSS BREACH / OXYGEN-DRIVEN AIR"
	footer.text = "The opening stays at the native tile center. Escaping air stops when the room has no oxygen."
	camera.size = 0.52
	camera.position = ship.room_nodes[4].position + Vector3(0.20, 0.6, 0.6)
	camera.look_at(ship.room_nodes[4].position)
	await _capture("breach_cross_fixture.png")
	ship.queue_free()
	labels.queue_free()
	await process_frame
	var sender := ShipModel.new()
	root.add_child(sender)
	sender.build("__damage_fixture__", false)
	sender.set_process(false)
	sender.hide()
	sender.position = Vector3(-1.5, 0, 0)
	sender.scale = Vector3.ONE * 0.30
	var effects := Effects.new()
	root.add_child(effects)
	effects.set_process(false)
	var targets: Array[Node3D] = []
	for i in range(3):
		var receiver := ShipModel.new()
		root.add_child(receiver)
		receiver.build("__damage_fixture__", true)
		receiver.set_process(false)
		receiver.scale = Vector3.ONE * 0.30
		receiver.position = Vector3((i - 1) * 0.76, 0, 0)
		receiver.inspect_rooms = true
		receiver.apply_live({"rooms": [{"id": 0, "visible": true}], "shield": 2 if i == 1 else 0})
		targets.append(receiver)
		_world_label(root, ["HULL HIT", "SHIELD HIT", "EVADED"][i], receiver.position + Vector3(0, 0.40, 0), 0.0018)
	var point: Dictionary = {"x": 70, "y": 70}
	effects.resolve_live({"projectile_id": "fixture-hull", "outcome": "hull", "target": point}, targets[0])
	effects.resolve_live({"projectile_id": "fixture-shield", "outcome": "shield", "target": point}, targets[1])
	effects.spawn_shot({"kind": "missile", "outcome": "pending", "projectile_id": "fixture-miss", "target": point}, sender, targets[2])
	effects.update_live_projectiles([{"id": "fixture-miss", "progress": 0.93, "missed": true}])
	effects._process(0.06)
	camera.size = 1.45
	camera.position = Vector3(0.30, 2.3, 2.2)
	camera.look_at(Vector3(0, 0.1, 0))
	title.text = "ACTUAL OUTCOMES / DISTINCT FEEDBACK"
	footer.text = "Orange hull impact / blue shield absorption / passing missile and MISS. Evasion never creates an impact."
	await _capture("miss_outcomes_fixture.png")
	print("DAMAGE_VISUAL_CAPTURE PASS")
	quit()


func _capture(filename: String) -> void:
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://local_game_data/" + filename)
	root.get_texture().get_image().save_png(path)
	print("DAMAGE_VISUAL_CAPTURE ", path)


func _world_label(parent: Node, text: String, point: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiAssets.font("body")
	label.font_size = 32
	label.pixel_size = pixel_size
	label.modulate = Color("fff2c4")
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = point
	parent.add_child(label)


func _caption(text: String, point: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_override("font", UiAssets.font("body"))
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = Color("fff2c4")
	root.add_child(label)
	return label
