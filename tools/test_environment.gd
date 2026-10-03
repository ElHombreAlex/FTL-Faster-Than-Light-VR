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
	print("ENVIRONMENT_TESTS ", "PASS" if failures == 0 else "FAIL: %d" % failures)
	space.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
