extends Node3D

const Voxels = preload("res://scripts/voxel_mesh.gd")
const MAX_HAZARDS := 128
static var shared_visuals: Dictionary = {}
var flame_outer: MultiMeshInstance3D
var flame_inner: MultiMeshInstance3D
var breaches: MultiMeshInstance3D
var air_streams: MultiMeshInstance3D
var fire_points: Array[Vector3] = []
var breach_points: Array[Vector3] = []
var animation_time := 0.0
var native_signature := ""


func build() -> void:
	# Shared meshes and materials: no particles, lights, or per-frame mesh rebuilds.
	flame_outer = _batch("FireOuter", [
		Voxels.block(Vector3(0, 0.016, 0), Vector3(0.074, 0.032, 0.061), Color("df4225")),
		Voxels.block(Vector3(0.010, 0.049, 0.005), Vector3(0.051, 0.035, 0.043), Color("ff842f")),
		Voxels.block(Vector3(-0.008, 0.079, 0), Vector3(0.024, 0.027, 0.026), Color("ffb64a")),
		Voxels.block(Vector3(0.020, 0.098, 0.004), Vector3(0.015, 0.020, 0.013), Color("ffd978"))], true)
	flame_inner = _batch("FireInner", [
		Voxels.block(Vector3(0, 0.019, 0), Vector3(0.038, 0.037, 0.039), Color("ffde80")),
		Voxels.block(Vector3(-0.004, 0.045, 0), Vector3(0.019, 0.028, 0.022), Color("fff1b3"))], true)
	var breach_blocks := [Voxels.block(Vector3(0, 0.0, 0), Vector3(0.085, 0.003, 0.085), Color("090f17"))]
	for i in range(8):
		var angle := i * TAU / 8.0
		var radius := 0.046 if i % 2 == 0 else 0.049
		breach_blocks.append(Voxels.block(Vector3(cos(angle) * radius, 0.003, sin(angle) * radius),
			Vector3(0.025, 0.011, 0.021), Color("9a8b77") if i % 2 == 0 else Color("566772")))
	breaches = _batch("HullBreaches", breach_blocks, false)
	air_streams = _batch("BreachAir", [
		Voxels.block(Vector3(-0.018, 0.029, 0), Vector3(0.004, 0.040, 0.004), Color("6c9caa")),
		Voxels.block(Vector3(0.008, 0.044, -0.010), Vector3(0.004, 0.035, 0.004), Color("9ac4cc")),
		Voxels.block(Vector3(0.016, 0.063, 0.014), Vector3(0.004, 0.029, 0.004), Color("6c9caa"))], true)


func _batch(node_name: String, blocks: Array, emissive: bool) -> MultiMeshInstance3D:
	if not shared_visuals.has(node_name):
		var source: MeshInstance3D = Voxels.make(blocks)
		var material: StandardMaterial3D = source.material_override
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = emissive
		material.emission = Color("ffab60") if node_name.begins_with("Fire") else Color("527a8b")
		material.emission_energy_multiplier = 0.22
		shared_visuals[node_name] = {"mesh": source.mesh, "material": material}
		source.free()
	var batch := MultiMeshInstance3D.new()
	batch.name = node_name
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = shared_visuals[node_name].mesh
	batch.material_override = shared_visuals[node_name].material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	return batch


func set_live(ship: Node3D, data: Dictionary) -> void:
	var fires: Array[Vector3] = []
	var holes: Array[Vector3] = []
	for room in data.get("rooms", []):
		if bool(ship.enemy) and (not bool(ship.inspect_rooms) or not bool(room.get("visible", false))):
			continue
		for point in room.get("fire_tiles", []):
			if fires.size() < MAX_HAZARDS:
				fires.append(ship.pixel_point(point, 0.082))
		for point in room.get("breach_tiles", []):
			if holes.size() < MAX_HAZARDS:
				holes.append(ship.pixel_point(point, 0.082))
	var signature := str(fires) + ":" + str(holes)
	if signature == native_signature:
		return
	native_signature = signature
	fire_points = fires
	breach_points = holes
	flame_outer.multimesh.instance_count = fires.size()
	flame_inner.multimesh.instance_count = fires.size()
	breaches.multimesh.instance_count = holes.size()
	air_streams.multimesh.instance_count = holes.size()
	for i in range(holes.size()):
		breaches.multimesh.set_instance_transform(i, Transform3D(Basis().rotated(Vector3.UP, (i % 4) * PI / 2.0), holes[i]))
	_render_animation()


func animate(delta: float) -> void:
	if fire_points.is_empty() and breach_points.is_empty():
		return
	animation_time += delta
	_render_animation()


func _render_animation() -> void:
	for i in range(fire_points.size()):
		var phase := animation_time * 8.5 + i * 2.7
		var outer := Basis().rotated(Vector3.UP, (i % 4) * PI / 2.0)
		outer = Basis(outer.x * (0.92 + sin(phase) * 0.07), outer.y * (0.87 + sin(phase + 0.8) * 0.16), outer.z)
		flame_outer.multimesh.set_instance_transform(i, Transform3D(outer, fire_points[i]))
		flame_inner.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, 0.88 + sin(phase + 1.7) * 0.18, 1.0)), fire_points[i]))
	for i in range(breach_points.size()):
		var phase := fposmod(animation_time * 0.7 + i * 0.19, 1.0)
		air_streams.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, 0.6 + phase * 0.6, 1.0)), breach_points[i] + Vector3.UP * phase * 0.025))
