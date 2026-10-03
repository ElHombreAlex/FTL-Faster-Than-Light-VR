extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var ship := ShipModel.new()
	root.add_child(ship)
	ship.build("__damage_fixture__", true)
	ship.set_process(false)
	ship.inspect_rooms = true
	var id: int = ship.room_nodes.keys()[0]
	var room := {"id": id, "visible": true, "oxygen": 100.0}
	var system := {"room_id": id, "health": 4, "max_health": 4}
	var state := {"rooms": [room], "room_systems": {str(id): "shields"}, "system_status": [system]}
	var original_state := JSON.stringify(state)
	ship.apply_live(state)
	_check(JSON.stringify(state) == original_state, "Presentation must not mutate the native game snapshot")
	var area: Area3D = ship.room_nodes[id]
	var floor: MeshInstance3D = area.get_node("Floor")
	var healthy_tint: Color = floor.material_override.albedo_color
	_check(not area.has_node("SystemCondition"), "Healthy rooms must not contain system health bars or numbers")
	system.health = 2
	ship.apply_live(state)
	var damaged_tint: Color = floor.material_override.albedo_color
	_check(damaged_tint != healthy_tint, "Authoritative damage must still change the room colour after removing health bars")
	_check(area.get_node("SystemRole").modulate == Color("ffad44"), "Partial damage must give the installed utility an amber cue")
	system.repair_progress = 0.35
	ship.apply_live(state)
	_check(not area.has_node("SystemCondition"), "Partial repairs must not recreate floor bars or repair counters")
	system.health = 0
	ship.apply_live(state)
	_check(floor.material_override.albedo_color != damaged_tint and area.get_node("SystemRole").modulate == Color("f26043"), "Destroyed systems must have a distinct red room and utility cue")
	ship.simulation_paused = true
	system.health = 3
	ship.apply_live(state)
	_check(floor.material_override.albedo_color != damaged_tint and area.get_node("SystemRole").modulate == Color("ffad44"), "Native repairs must update damage colour even during pause")
	system.health = 4
	ship.apply_live(state)
	_check(floor.material_override.albedo_color == healthy_tint and area.get_node("SystemRole").modulate == Color("fff2c4"), "Full native repair must immediately clear every damage colour")
	system.health_detail_visible = false
	ship.apply_live(state)
	_check(not area.has_node("SystemCondition"), "Revealed or hidden exact health must never create floor bars")
	system.erase("health_detail_visible")
	room.visible = false
	system.health = 1
	ship.apply_live(state)
	_check(area.get_node("SystemRole").modulate == Color("fff2c4"), "Sensor fog must not reveal private health through icon colour")
	_check(floor.material_override.albedo_color == Color(0.12, 0.14, 0.17), "Undisclosed enemy damage must retain the native fog floor tint")
	system.health_visible = true
	ship.apply_live(state)
	_check(area.get_node("SystemRole").modulate == Color("ffad44"), "Native public damage may tint a hidden utility without revealing exact health")
	var coarse_tint: Color = floor.material_override.albedo_color
	system.health = 3
	ship.apply_live(state)
	_check(floor.material_override.albedo_color == coarse_tint, "Coarse public condition colours must not leak exact remaining enemy system levels")
	system.health = 1
	system.health_detail_visible = true
	ship.apply_live(state)
	_check(not area.has_node("SystemCondition"), "Even explicitly revealed enemy health must not recreate removed bars")
	ship.inspect_rooms = false
	ship.apply_live(state)
	_check(not area.get_node("SystemRole").visible, "Closed enemy hull must hide the system utility label")
	ship.inspect_rooms = true
	room.visible = true
	var tile := {"x": 35.0, "y": 35.0}
	room.breach_tiles = [tile]
	ship.apply_live(state)
	var hazards: Node3D = ship.room_hazards
	_check(hazards.breach_points.size() == 1 and hazards.breach_points[0].is_equal_approx(ship.pixel_point(tile, 0.082)), "Breach cross must use the actual native tile center")
	_check(hazards.air_streams.multimesh.instance_count == 1, "An oxygenated native breach must emit escaping air")
	var breach_mesh: Mesh = hazards.breaches.multimesh.mesh
	var arrays: Array = breach_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var black_vertices := 0
	for i in range(vertices.size()):
		if colors[i].is_equal_approx(Color("020407")):
			black_vertices += 1
			_check(absf(vertices[i].x) <= 0.01751 or absf(vertices[i].z) <= 0.01751, "Black breach geometry must have a cross silhouette, with empty diagonal corners")
	_check(black_vertices == 72 and breach_mesh.get_aabb().size.x < ShipModel.TILE and breach_mesh.get_aabb().size.z < ShipModel.TILE, "Breach opening must fit a native floor tile and use only two crossed black prisms")
	var paused_time: float = hazards.animation_time
	ship._process(0.5)
	_check(hazards.animation_time == paused_time, "Paused breach air must not advance animation")
	room.oxygen = 0.0
	ship.apply_live(state)
	_check(hazards.breach_points.size() == 1 and hazards.air_streams.multimesh.instance_count == 0, "A vacuum room must retain its breach but stop escaping air")
	room.visible = false
	ship.apply_live(state)
	_check(hazards.breach_points.is_empty() and hazards.air_streams.multimesh.instance_count == 0, "System damage visibility must not reveal private breach locations under fog")
	room.visible = true
	room.breach_tiles = []
	ship.apply_live(state)
	_check(hazards.breaches.multimesh.instance_count == 0 and hazards.air_streams.multimesh.instance_count == 0, "Native breach repair must remove hole and air immediately during pause")
	var other := ShipModel.new()
	root.add_child(other)
	other.build("__damage_fixture__", false)
	other.set_process(false)
	other.apply_live(state)
	_check(not other.room_nodes[id].has_node("SystemCondition"), "Player rooms must also omit system health bars")
	_check(other.room_hazards.breaches.multimesh.mesh == breach_mesh, "Breach crosses across ships must reuse one shared mesh")
	state.system_status = []
	ship.apply_live(state)
	_check(area.get_node("SystemRole").modulate == Color("fff2c4") and not area.has_node("SystemCondition"), "Missing native health must clear stale damage colour without showing counters")
	print("DAMAGE_VISUAL_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	ship.queue_free()
	other.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
