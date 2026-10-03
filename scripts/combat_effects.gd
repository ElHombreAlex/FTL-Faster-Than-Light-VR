extends Node3D

const NATIVE_PRESENTATION_GRACE_MS := 300
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")
const MISS_CUE_DURATION := 1.0
const MAX_MISS_CUES := 24
static var impact_meshes: Dictionary = {}
static var glow_materials: Dictionary = {}
static var projectile_meshes: Dictionary = {}
static var solid_materials: Dictionary = {}

var shots: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var misses: Array[Dictionary] = []
var simulation_paused := false
var unit_beam_mesh: CylinderMesh


func spawn_shot(event: Dictionary, sender: Node3D, receiver: Node3D) -> void:
	var kind := str(event.get("kind", "laser"))
	var origin_ship := sender
	if event.has("origin_space") and int(event["origin_space"]) == int(receiver.get("enemy")):
		origin_ship = receiver
	if event.has("target_space") and int(event["target_space"]) == int(sender.get("enemy")):
		receiver = sender
	var start: Vector3 = sender.weapon_origin(int(event.get("weapon_slot", 0)))
	var drone_id := str(event.get("drone_id", ""))
	var drone: Node3D = _drone(origin_ship, drone_id)
	if drone != null:
		start = drone.muzzle_position(str(event.get("projectile_id", "")))
		drone.present_fire()
	elif event.has("origin_point"):
		start = origin_ship.to_global(origin_ship.pixel_point(event["origin_point"], 0.3 if not drone_id.is_empty() else 0.18))
	var end: Vector3 = receiver.room_target(int(event.get("target_room", 0)))
	if event.has("target") and not event["target"].is_empty():
		end = receiver.to_global(receiver.pixel_point(event["target"]))
	var outcome := str(event.get("outcome", "hull"))
	if outcome == "shield":
		end = receiver.shield_intercept(start, end)
	elif outcome == "miss":
		end = _miss_endpoint(start, end, receiver)
	var color := Color(0.3, 0.75, 1.0) if kind == "ion" else Color(1.0, 0.35, 0.12)
	if kind == "missile":
		color = Color(0.9, 0.9, 0.85)
	elif kind == "asteroid":
		color = Color(0.4, 0.42, 0.45)
	var drone_family := str(drone.family) if drone != null else ""
	if kind == "laser" and drone_family in ["defense", "anti_drone"]:
		color = Color("98e5aa") if drone_family == "defense" else Color("a9dfe9")
	var node := _projectile_visual(kind, color, not drone_id.is_empty())
	add_child(node)
	node.global_position = start
	var duration := maxf(0.01, float(event.get("duration", 0.7)))
	var beam_end: Vector3 = receiver.room_target(int(event.get("end_room", event.get("target_room", 0))))
	if event.has("end_point"):
		beam_end = receiver.to_global(receiver.pixel_point(event["end_point"]))
	if kind == "beam":
		if outcome == "shield":
			beam_end = receiver.shield_intercept(start, beam_end)
	elif kind == "bomb":
		node.visible = false
		# Bombs appear at their destination rather than crossing space.
	shots.append({"node": node, "start": start, "end": end, "beam_end": beam_end,
		"projectile_id": str(event.get("projectile_id", "")), "sender": sender,
		"created_ms": Time.get_ticks_msec(), "native_present": false,
		"visual_scale": maxf(0.1, (origin_ship if not drone_id.is_empty() else sender).global_basis.get_scale().abs().x),
		"live_progress": 0.0, "wanted_progress": 0.0, "missed": false, "miss_feedback": false,
		"end_point": event.get("end_point", {}),
		"origin_point": event.get("origin_point", {}), "origin_ship": origin_ship,
		"drone_id": drone_id, "launch_point": origin_ship.to_local(start),
		"target_point": event.get("target", {}), "beam_point": {},
		"slot": int(event.get("weapon_slot", 0)), "room": int(event.get("target_room", 0)),
		"time": 0.0, "duration": duration, "kind": kind, "outcome": outcome, "receiver": receiver})


func _process(delta: float) -> void:
	# Miss labels remain attached to the encounter if the table is moved during
	# pause; only their presentation lifetime and drift freeze with simulation.
	for i in range(misses.size() - 1, -1, -1):
		var cue: Dictionary = misses[i]
		if not is_instance_valid(cue["receiver"]) or not is_instance_valid(cue["node"]):
			if is_instance_valid(cue["node"]):
				cue["node"].queue_free()
			misses.remove_at(i)
			continue
		if not simulation_paused:
			cue["time"] += delta
		var age := clampf(float(cue["time"]) / MISS_CUE_DURATION, 0.0, 1.0)
		var label: Label3D = cue["node"]
		label.global_position = cue["receiver"].to_global(Vector3(cue["local_point"]) + Vector3.UP * (0.28 + age * 0.12))
		label.modulate.a = minf(1.0, (1.0 - age) * 3.0)
		if age >= 1.0:
			label.queue_free()
			misses.remove_at(i)
	for i in range(impacts.size() - 1, -1, -1):
		if not simulation_paused:
			impacts[i]["time"] += delta
		var flash: MeshInstance3D = impacts[i]["node"]
		var age := float(impacts[i]["time"]) / 0.22
		flash.scale = Vector3.ONE * maxf(0.01, 1.0 - age)
		var ring := flash.get_node_or_null("ImpactRing") as MeshInstance3D
		if ring != null:
			ring.scale = Vector3.ONE * (1.0 + age * 3.0)
		if float(impacts[i]["time"]) >= 0.22:
			flash.queue_free()
			impacts.remove_at(i)
	for i in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		if not simulation_paused:
			shot["time"] += delta
		# Recompute endpoints after the user moves/rotates/scales the encounter.
		shot["visual_scale"] = maxf(0.1, (shot["origin_ship"] if not shot["drone_id"].is_empty() else shot["sender"]).global_basis.get_scale().abs().x)
		if not shot["drone_id"].is_empty():
			# Moving an orbiting drone cannot drag the launch point of a bullet.
			# A continuing beam is the one native effect attached to its emitter.
			var drone: Node3D = _drone(shot["origin_ship"], shot["drone_id"])
			shot["start"] = drone.muzzle_position(shot["projectile_id"]) if shot["kind"] == "beam" and drone != null else shot["origin_ship"].to_global(shot["launch_point"])
		else:
			shot["start"] = shot["sender"].weapon_origin(shot["slot"])
		if shot["drone_id"].is_empty() and not shot["origin_point"].is_empty():
			shot["start"] = shot["origin_ship"].to_global(shot["origin_ship"].pixel_point(shot["origin_point"]))
		if shot["outcome"] == "pending":
			shot["end"] = shot["receiver"].room_target(shot["room"])
			if not shot["target_point"].is_empty():
				shot["end"] = shot["receiver"].to_global(shot["receiver"].pixel_point(shot["target_point"]))
			if shot["missed"]:
				shot["end"] = _miss_endpoint(shot["start"], shot["end"], shot["receiver"])
			if not shot["end_point"].is_empty():
				shot["beam_end"] = shot["receiver"].to_global(shot["receiver"].pixel_point(shot["end_point"]))
		var progress := clampf(float(shot["time"]) / float(shot["duration"]), 0.0, 1.0)
		if shot["outcome"] == "pending":
			if not simulation_paused:
				shot["live_progress"] = lerpf(shot["live_progress"], shot["wanted_progress"], minf(1.0, delta * 20.0))
			progress = shot["live_progress"]
		var node: MeshInstance3D = shot["node"]
		if shot["kind"] == "beam":
			var beam_target: Vector3 = Vector3(shot["end"]).lerp(shot["beam_end"], progress)
			if not shot["beam_point"].is_empty():
				beam_target = shot["receiver"].to_global(shot["receiver"].pixel_point(shot["beam_point"]))
			var line: ImmediateMesh = node.mesh
			line.clear_surfaces()
			line.surface_begin(Mesh.PRIMITIVE_LINES)
			line.surface_add_vertex(to_local(shot["start"]))
			line.surface_add_vertex(to_local(beam_target))
			line.surface_end()
			node.position = Vector3.ZERO
			# Keep the precise native sweep line, then surround it with real 3D
			# cylinders so its width remains visible in stereo at oblique angles.
			_segment(node.get_node("BeamCore"), shot["start"], beam_target, (0.007 if not shot["drone_id"].is_empty() else 0.012) * shot["visual_scale"])
			_segment(node.get_node("BeamGlow"), shot["start"], beam_target, (0.018 if not shot["drone_id"].is_empty() else 0.032) * shot["visual_scale"])
		elif shot["kind"] != "bomb":
			node.global_position = Vector3(shot["start"]).lerp(shot["end"], progress)
			var direction: Vector3 = Vector3(shot["end"]) - Vector3(shot["start"])
			if direction.length_squared() > 0.000001:
				var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
				node.global_basis = Basis.looking_at(direction.normalized(), up).scaled(Vector3.ONE * shot["visual_scale"])
		if progress >= 1.0 and shot["outcome"] != "pending":
			if shot["outcome"] == "shield":
				shot["receiver"].flash_shield()
			if shot["outcome"] not in ["miss", "pending"]:
				_impact(shot["beam_end"] if shot["kind"] == "beam" else shot["end"], shot["kind"], shot["outcome"] == "shield")
			elif shot["outcome"] == "miss":
				_show_shot_miss(shot)
			node.queue_free()
			shots.remove_at(i)


func resolve_live(event: Dictionary, receiver: Node3D) -> void:
	var projectile_id := str(event.get("projectile_id", ""))
	var point: Vector3 = receiver.to_global(receiver.pixel_point(event.get("target", {})))
	if event.get("outcome", "") == "beam":
		_impact(point, "beam")
		return
	var kind := str(event.get("kind", "laser"))
	var miss_already_shown := false
	for i in range(shots.size() - 1, -1, -1):
		if shots[i]["projectile_id"] == projectile_id:
			if event.get("outcome", "") == "miss":
				# Evasion is reported at the native collision decision. The shot
				# may still be flying; native snapshots decide when it disappears.
				shots[i]["missed"] = true
				_show_shot_miss(shots[i])
				return
			kind = str(shots[i]["kind"])
			miss_already_shown = bool(shots[i].get("miss_feedback", false))
			if not event.has("target"):
				point = shots[i]["end"]
			if event.get("outcome", "") == "shield":
				point = receiver.shield_intercept(shots[i]["start"], point)
			shots[i]["node"].queue_free()
			shots.remove_at(i)
	if event.get("outcome", "") == "shield":
		receiver.flash_shield()
	if event.get("outcome", "") in ["shield", "hull"]:
		_impact(point, kind, event.get("outcome", "") == "shield")
	elif event.get("outcome", "") == "miss" and not miss_already_shown:
		_miss_feedback(point, receiver, projectile_id)


func update_live_projectiles(projectiles: Array) -> void:
	var present: Dictionary = {}
	for projectile in projectiles:
		present[str(projectile["id"])] = projectile
	for i in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		if shot["outcome"] != "pending":
			continue
		if present.has(shot["projectile_id"]):
			var projectile: Dictionary = present[shot["projectile_id"]]
			shot["native_present"] = true
			shot["wanted_progress"] = float(projectile.get("progress", 0))
			shot["missed"] = shot["missed"] or bool(projectile.get("missed", false))
			if shot["missed"]:
				_show_shot_miss(shot)
			shot["beam_point"] = projectile.get("beam_point", {})
		elif shot["native_present"] or shot["missed"] or Time.get_ticks_msec() - int(shot["created_ms"]) >= NATIVE_PRESENTATION_GRACE_MS:
			# Native absence ends a known projectile immediately. Newly delivered
			# fire records without an outcome get a short snapshot grace. A native
			# miss followed by absence has already completed its real lifecycle;
			# the grace clock keeps working while gameplay is paused.
			shot["node"].queue_free()
			shots.remove_at(i)


func _impact(point: Vector3, kind: String = "laser", shield: bool = false) -> void:
	var flash := MeshInstance3D.new()
	var sphere_key := "large" if kind in ["missile", "bomb"] else "small"
	if not impact_meshes.has(sphere_key):
		var sphere := SphereMesh.new()
		sphere.radius = 0.04 if sphere_key == "large" else 0.025
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 10
		sphere.rings = 5
		impact_meshes[sphere_key] = sphere
	flash.mesh = impact_meshes[sphere_key]
	var color := Color(0.32, 0.73, 1.0) if shield or kind == "ion" else Color(1.0, 0.78, 0.28)
	flash.material_override = _glow(color)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new()
	ring.name = "ImpactRing"
	if not impact_meshes.has("ring"):
		var torus := TorusMesh.new()
		torus.inner_radius = 0.024
		torus.outer_radius = 0.028
		torus.rings = 16
		torus.ring_segments = 6
		impact_meshes["ring"] = torus
	ring.mesh = impact_meshes["ring"]
	ring.material_override = _glow(Color(color, 0.45), true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(ring)
	if kind in ["missile", "bomb"]:
		for i in range(6):
			var spark := _box(Vector3(0.007, 0.007, 0.025), Color(1.0, 0.38, 0.05))
			var direction := Vector3(cos(i * TAU / 6.0), 0.3, sin(i * TAU / 6.0))
			spark.position = direction * 0.04
			spark.basis = Basis.looking_at(direction, Vector3.UP)
			flash.add_child(spark)
	add_child(flash)
	flash.global_position = point
	impacts.append({"node": flash, "time": 0.0, "outcome": "shield" if shield else "hull", "kind": kind})


func _miss_endpoint(start: Vector3, target: Vector3, receiver: Node3D) -> Vector3:
	var direction := (target - start).normalized()
	var up := receiver.global_basis.y.normalized()
	var tangent := direction.cross(up).normalized()
	var scale := maxf(0.1, receiver.global_basis.get_scale().abs().x)
	# This is an outcome illustration, never collision detection. The native
	# evasion flag allows a clear passing trajectory without creating a hit.
	return target + (tangent * 0.30 + up * 0.22 + direction * 1.1) * scale


func _show_shot_miss(shot: Dictionary) -> void:
	if shot["miss_feedback"]:
		return
	shot["miss_feedback"] = true
	var receiver: Node3D = shot["receiver"]
	var point: Vector3 = receiver.room_target(shot["room"])
	if not shot["target_point"].is_empty():
		point = receiver.to_global(receiver.pixel_point(shot["target_point"]))
	_miss_feedback(point, receiver, shot["projectile_id"])


func _miss_feedback(point: Vector3, receiver: Node3D, projectile_id: String) -> void:
	# An impact record and its 10 Hz missed flag can arrive in either order.
	# Keep one cue per native projectile while the short feedback is visible.
	for cue in misses:
		if not projectile_id.is_empty() and cue["projectile_id"] == projectile_id:
			return
	if misses.size() >= MAX_MISS_CUES:
		misses[0]["node"].queue_free()
		misses.pop_front()
	var label := Label3D.new()
	label.name = "NativeMiss"
	label.text = "MISS"
	label.font = UiAssets.font("body")
	label.font_size = 50
	label.pixel_size = 0.0028 * maxf(0.1, receiver.global_basis.get_scale().abs().x)
	label.modulate = Color("fff2c4")
	label.outline_modulate = Color("1b2532")
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test = false
	add_child(label)
	var local_point: Vector3 = receiver.to_local(point)
	label.global_position = receiver.to_global(local_point + Vector3.UP * 0.28)
	misses.append({"node": label, "receiver": receiver, "local_point": local_point,
		"time": 0.0, "projectile_id": projectile_id})


func _drone(ship: Node3D, drone_id: String) -> Node3D:
	if drone_id.is_empty() or (drone_id.is_valid_int() and drone_id.to_int() < 0):
		return null
	var nodes: Variant = ship.get("drone_nodes")
	if nodes is Dictionary and nodes.has(drone_id) and is_instance_valid(nodes[drone_id]):
		return nodes[drone_id]
	return null


func _projectile_visual(kind: String, color: Color, drone_shot: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _glow(color)
	match kind:
		"beam":
			node.mesh = ImmediateMesh.new()
			if unit_beam_mesh == null:
				unit_beam_mesh = CylinderMesh.new()
				unit_beam_mesh.height = 1.0
				unit_beam_mesh.top_radius = 1.0
				unit_beam_mesh.bottom_radius = 1.0
				unit_beam_mesh.radial_segments = 8
			for part in ["BeamCore", "BeamGlow"]:
				var cylinder := MeshInstance3D.new()
				cylinder.name = part
				cylinder.mesh = unit_beam_mesh
				cylinder.material_override = _glow(Color(1.0, 0.94, 0.67) if part == "BeamCore" else Color(1.0, 0.35, 0.1, 0.2), part == "BeamGlow")
				cylinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(cylinder)
		"missile":
			node.mesh = _box_mesh(Vector3(0.075, 0.065, 0.19))
			node.material_override = _solid(Color(0.72, 0.76, 0.79))
			var nose := MeshInstance3D.new()
			if not projectile_meshes.has("missile_nose"):
				var pyramid := CylinderMesh.new()
				pyramid.top_radius = 0.0
				pyramid.bottom_radius = 0.052
				pyramid.height = 0.072
				pyramid.radial_segments = 4
				projectile_meshes["missile_nose"] = pyramid
			nose.mesh = projectile_meshes["missile_nose"]
			nose.position.z = -0.128
			nose.rotation.x = -PI / 2.0
			nose.material_override = _solid(Color(0.73, 0.17, 0.08))
			node.add_child(nose)
			for axis in [Vector3.RIGHT, Vector3.UP]:
				var fin := _box(Vector3(0.14, 0.012, 0.065) if axis == Vector3.RIGHT else Vector3(0.012, 0.12, 0.065), Color(0.27, 0.3, 0.33), false)
				fin.position.z = 0.068
				node.add_child(fin)
			var exhaust := _box(Vector3(0.035, 0.035, 0.12), Color(1.0, 0.36, 0.08, 0.65))
			exhaust.position.z = 0.145
			node.add_child(exhaust)
		"ion":
			var ion_radius := 0.032 if drone_shot else 0.052
			var ion_key := "drone_ion" if drone_shot else "ion"
			if not projectile_meshes.has(ion_key):
				var sphere := SphereMesh.new()
				sphere.radius = ion_radius
				sphere.height = ion_radius * 2.0
				sphere.radial_segments = 8
				sphere.rings = 4
				projectile_meshes[ion_key] = sphere
			node.mesh = projectile_meshes[ion_key]
			for axis in [0, 1]:
				var ring := MeshInstance3D.new()
				if not projectile_meshes.has(ion_key + "_ring"):
					var torus := TorusMesh.new()
					torus.inner_radius = ion_radius * 1.27
					torus.outer_radius = ion_radius * 1.5
					torus.rings = 12
					torus.ring_segments = 4
					projectile_meshes[ion_key + "_ring"] = torus
				ring.mesh = projectile_meshes[ion_key + "_ring"]
				ring.rotation.x = PI / 2.0 if axis == 0 else 0.0
				ring.material_override = _glow(Color(0.15, 0.6, 1.0, 0.6), true)
				ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(ring)
		"asteroid":
			if not projectile_meshes.has("asteroid"):
				var sphere := SphereMesh.new()
				sphere.radius = 0.2
				sphere.height = 0.34
				sphere.radial_segments = 7
				sphere.rings = 4
				projectile_meshes["asteroid"] = sphere
			node.mesh = projectile_meshes["asteroid"]
			node.material_override = _solid(color)
		_:
			node.mesh = _box_mesh(Vector3(0.020, 0.020, 0.09) if drone_shot else Vector3(0.028, 0.028, 0.26))
			node.material_override = _glow(Color(1.0, 0.93, 0.72))
			var trail := _box(Vector3(0.042, 0.042, 0.16) if drone_shot else Vector3(0.066, 0.066, 0.39), Color(color, 0.27))
			trail.position.z = 0.038 if drone_shot else 0.07
			node.add_child(trail)
	return node


func _box(size: Vector3, color: Color, luminous: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(size)
	node.material_override = _glow(color, color.a < 1.0) if luminous else _solid(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:" + str(size)
	if not projectile_meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		projectile_meshes[key] = mesh
	return projectile_meshes[key]


func _glow(color: Color, additive: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + ":" + str(additive)
	if glow_materials.has(key):
		return glow_materials[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	if additive:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_materials[key] = material
	return material


func _solid(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if solid_materials.has(key):
		return solid_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	solid_materials[key] = material
	return material


func _segment(node: MeshInstance3D, start: Vector3, end: Vector3, radius: float) -> void:
	var direction := end - start
	var length := direction.length()
	node.visible = length > 0.00001
	if not node.visible:
		return
	var axis := direction / length
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var side := reference.cross(axis).normalized()
	# A shared unit cylinder stays immutable. Transforming it avoids rebuilding
	# two procedural meshes on every beam sweep frame.
	node.global_basis = Basis(side * radius, axis * length, side.cross(axis) * radius)
	node.global_position = (start + end) * 0.5
