extends SceneTree

const BEAMS := 12
const SAMPLES := 120


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 90
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.4, 4.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var effects: Node3D = load("res://scripts/combat_effects.gd").new()
	stage.add_child(effects)
	var results := {}
	for mode in ["mutable_mesh", "unit_transform"]:
		var phase := Node3D.new()
		stage.add_child(phase)
		var segments: Array[MeshInstance3D] = []
		var changed := {"count": 0}
		var watched := {}
		for i in range(BEAMS):
			var beam: MeshInstance3D = effects._projectile_visual("beam", Color.ORANGE)
			phase.add_child(beam)
			for child in beam.get_children():
				var segment := child as MeshInstance3D
				if mode == "mutable_mesh":
					segment.mesh = segment.mesh.duplicate()
				segments.append(segment)
				if not watched.has(segment.mesh.get_instance_id()):
					watched[segment.mesh.get_instance_id()] = true
					segment.mesh.changed.connect(func(): changed["count"] += 1)
		var total_us := 0
		for frame in range(SAMPLES + 20):
			if frame == 20:
				changed["count"] = 0
			var start_us := Time.get_ticks_usec()
			for i in range(segments.size()):
				var start := Vector3(-1.5, float(i / 2) * 0.025 - 0.2, 0.0)
				var end := Vector3(1.5, sin(frame * 0.027 + i * 0.01) * 0.65, cos(frame * 0.023) * 0.28)
				var radius := 0.004 if i % 2 == 0 else 0.012
				if mode == "mutable_mesh":
					_mutable_segment(segments[i], start, end, radius)
				else:
					effects._segment(segments[i], start, end, radius)
			if frame >= 20:
				total_us += Time.get_ticks_usec() - start_us
			await process_frame
			await RenderingServer.frame_post_draw
		results[mode] = {"cpu_update_us_per_frame": float(total_us) / SAMPLES,
			"mesh_resource_changes": changed["count"], "mesh_resources": watched.size()}
		phase.queue_free()
		await process_frame
	print("BEAM_BENCHMARK beams=", BEAMS, " samples=", SAMPLES, " ", JSON.stringify(results))
	quit()


func _mutable_segment(node: MeshInstance3D, start: Vector3, end: Vector3, radius: float) -> void:
	var direction := end - start
	var length := direction.length()
	var axis := direction / length
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var side := reference.cross(axis).normalized()
	node.global_basis = Basis(side, axis, side.cross(axis))
	node.global_position = (start + end) * 0.5
	var mesh := node.mesh as CylinderMesh
	mesh.height = length
	mesh.top_radius = radius
	mesh.bottom_radius = radius
