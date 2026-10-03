extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var space: Node3D = load("res://scripts/space_environment.gd").new()
	root.add_child(space)
	space.build()
	space.set_process(false)
	_check(space.star_positions.size() == 1696, "Two star shells must cover the sky")
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var count := 0
		for point in space.star_positions:
			if Vector3(point).normalized().dot(axis) > 0.8:
				count += 1
		_check(count > 100, "Every direction must contain stars, including overhead and behind")
	var meshes := 0
	for child in space.get_children():
		if child is MultiMeshInstance3D:
			meshes += 1
	_check(meshes == 3, "Starfield must batch its geometry into three draw calls")
	var star_nodes: Array[MultiMeshInstance3D] = []
	var star_meshes: Array[MultiMesh] = []
	for child in space.get_children():
		if child is MultiMeshInstance3D:
			star_nodes.append(child)
			star_meshes.append(child.multimesh)
			_check(child.material_override == space.star_material, "Star shells must share one persistent stretch material")
	for kind in ["asteroid", "sun", "storm", "nebula", "pulsar", "clear"]:
		space.apply_state({"hazard": kind, "paused": false})
		_check(space.hazard == kind, "Environment must follow the native hazard")
		_check(space.hazard_root.get_child_count() < 40, "Hazard geometry must stay bounded")
		if kind != "clear":
			_check(space.hazard_root.get_child_count() > 0, "Each active hazard must have a 3D presentation")
		else:
			_check(space.hazard_root.get_child_count() == 0, "Old hazard geometry must be removed at a clear beacon")
	space.apply_state({"hazard": "asteroid", "paused": true})
	var rock: Node3D = space.rocks[0]["node"]
	var location := rock.position
	space._process(0.5)
	_check(rock.position == location, "Pause must freeze nearby asteroid motion")
	space.apply_state({"hazard": "asteroid", "paused": false})
	space._process(0.5)
	_check(rock.position != location, "Unpaused asteroid field must have parallax motion")
	# A charged drive, the map, and pending startup events are not departures.
	for stationary in [
		{"hazard": "clear", "navigation": {"jump": true}, "map_open": true},
		{"hazard": "clear", "transition": true, "event_pending": true, "paused": true},
		{"hazard": "clear", "event_open": true, "dialog": {"id": "startup"}},
	]:
		space.apply_state(stationary)
		space._process(0.4)
		_check(not space.jump_active and space.jump_stretch == 0.0, "Stationary native UI must not fake a jump")
	space.set_travel_direction(Vector3(0.0, 7.0, -3.0))
	_check(space.travel_direction.is_equal_approx(Vector3.FORWARD), "Travel follows the ship bow projected onto the horizontal plane")
	space.set_travel_direction(Vector3.UP)
	_check(space.travel_direction.is_equal_approx(Vector3.FORWARD), "An invalid vertical heading must preserve the last travel direction")
	space.apply_state({"hazard": "asteroid", "jumping": true, "paused": true, "frozen": true})
	var departure_rock: Node3D = space.rocks[0]["node"]
	var departure_location := departure_rock.position
	space._process(0.1)
	_check(space.jump_active and space.jump_stretch > 0.0, "Native travel must stretch stars even while simulation is paused")
	_check(not space.hazard_root.visible, "Old beacon hazards must be hidden during travel")
	_check(departure_rock.position == departure_location, "Hidden old beacon hazards must not advance during travel")
	space._process(0.4)
	_check(space.jump_stretch == 1.0, "A sustained native jump must reach full star stretch")
	space.set_travel_direction(Vector3(-4.0, 0.0, 0.0))
	_check(Vector3(space.star_material.get_shader_parameter("travel_direction")).is_equal_approx(Vector3.LEFT), "Streaks must follow the supplied ship heading, including reversed travel")
	space.apply_state({"hazard": "sun", "jumping": true, "event_open": true, "paused": true})
	_check(not space.jump_active and space.jump_stretch == 0.0, "Arrival dialog must restore stars immediately")
	_check(space.hazard_root.visible and space.hazard == "sun", "Arrival must show the new beacon's native hazard")
	space.apply_state({"hazard": "sun", "jumping": true, "event_open": false})
	space._process(0.3)
	_check(space.jump_stretch == 0.0, "Closing an arrival dialog must not restart a lingering native jump animation")
	space.apply_state({"hazard": "clear", "jumping": false})
	space.apply_state({"hazard": "clear", "jumping": true})
	space._process(0.4)
	_check(space.jump_stretch == 1.0, "The next real departure must animate after the previous arrival")
	space.apply_state({"hazard": "nebula", "jumping": false, "event_open": false})
	_check(space.jump_stretch == 0.0 and space.hazard_root.visible, "A beacon without an arrival dialog must also end native travel")
	space.apply_state({"jumping": true, "ready": false, "ui_mode": "menu"})
	space._process(0.4)
	_check(space.jump_stretch == 0.0, "A native menu snapshot must not show travel")
	for i in range(star_nodes.size()):
		_check(star_nodes[i].multimesh == star_meshes[i], "Jump transitions must preserve the star MultiMesh resources")
		_check(star_nodes[i].material_override == space.star_material, "Jump transitions must preserve the shared star material")
	print("ENVIRONMENT_TESTS ", "PASS" if failures == 0 else "FAIL: %d" % failures)
	space.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
