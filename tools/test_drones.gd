extends SceneTree

const DroneModel = preload("res://scripts/voxel_drone.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	for family in ["combat", "beam", "defense"]:
		var first := DroneModel.new()
		var second := DroneModel.new()
		root.add_child(first)
		root.add_child(second)
		first.build({"name": family.to_upper() + "_1", "kind": family, "deployed": true})
		second.build({"name": family.to_upper() + "_2", "kind": family, "deployed": true})
		_check(first.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != second.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Every native %s Mk II must have distinct armor or emitter geometry" % family)
		first.queue_free()
		second.queue_free()
	var idle := DroneModel.new()
	var active := DroneModel.new()
	root.add_child(idle)
	root.add_child(active)
	var data := {"name": "COMBAT_2", "kind": "combat", "deployed": true, "powered": true}
	idle.build(data)
	active.build(data)
	_check(idle.thruster.mesh == active.thruster.mesh and idle.emitter.mesh == active.emitter.mesh,
		"Matching drone glow surfaces must reuse geometry as well as their armored body")
	var idle_material := idle.emitter.material_override
	active.present_fire()
	_check(idle.emitter.material_override == idle_material and is_equal_approx(idle_material.emission_energy_multiplier, 0.25),
		"A native fire flash must not brighten another drone through a shared mutable material")
	_check(is_equal_approx(active.emitter.material_override.emission_energy_multiplier, 1.5), "An actual native fire record must visibly brighten its own emitter")
	active.animate(0.04)
	_check(active.body.position.x < 0.0, "An actual native shot must produce a short recoil pose")
	active.animate(0.25)
	_check(is_zero_approx(active.body.position.x) and active.emitter.material_override == idle_material,
		"A completed native fire flash must return to the shared idle pose and glow")
	var changes := {"count": 0}
	var track_change := func(): changes["count"] += 1
	for part in [active.body, active.thruster, active.emitter]:
		part.mesh.changed.connect(track_change)
	for i in range(90):
		active.animate(1.0 / 90.0)
	_check(changes["count"] == 0, "Drone animation must update transforms without rebuilding shared mesh geometry")
	for part in [active.body, active.thruster, active.emitter]:
		part.mesh.changed.disconnect(track_change)
	active.rotation = Vector3(0.2, -1.0, 0.1)
	active.scale = Vector3.ONE * 0.6
	var local_muzzle: Vector3 = active.to_local(active.muzzle_position("42"))
	_check(is_equal_approx(local_muzzle.x, 0.135) and is_equal_approx(local_muzzle.y, 0.003) and is_equal_approx(absf(local_muzzle.z), 0.018),
		"The native firing muzzle must retain the model's local barrel point through tilt and scale")
	idle.queue_free()
	active.queue_free()
	print("DRONE_TESTS ", "PASS" if failures == 0 else "FAIL: %d" % failures,
		" mk2_families=3 shared_geometry=body+exhaust+emitter independent_glow=true immutable_meshes=true")
	await process_frame
	quit(0 if failures == 0 else 1)
