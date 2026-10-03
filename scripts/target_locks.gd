extends Node3D

# Mirror WeaponControl::RenderAimingWeapon: player-owned weapon.targets are the
# authority, including while the armed cursor is closed. Never use lastTargets
# or enemy weapon targeting, and never infer locks from projectile history.
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")
const NATIVE_PIXEL := 0.18 / 35.0
const HEIGHT := 0.195
const NORMAL := Color("ff4b19")
const AUTOFIRE := Color("ffdf00")
const INK := Color("080b10")
var locks: Dictionary = {}


func apply_snapshot(state: Dictionary, player_ship: Node3D, enemy_ship: Node3D) -> void:
	if not bool(state.get("ready", false)) or bool(state.get("transition", false)):
		clear()
		return
	var player: Variant = state.get("player", {})
	if not player is Dictionary or bool(player.get("destroyed", false)):
		clear()
		return
	var weapons: Variant = player.get("weapons", [])
	if not weapons is Array:
		clear()
		return
	var keep: Dictionary = {}
	for i in range(weapons.size()):
		var weapon: Variant = weapons[i]
		if not weapon is Dictionary:
			continue
		var slot := int(weapon.get("slot", i))
		var side := int(weapon.get("target_ship", -1))
		# Native self-aiming remains valid without an enemy (for healing bombs).
		# Only targets on the enemy require an active encounter.
		if side == 1 and not bool(state.get("combat", false)):
			continue
		var receiver := player_ship if side == 0 else enemy_ship if side == 1 else null
		var receiver_state: Variant = state.get("player" if side == 0 else "enemy", {})
		if slot < 0 or keep.has(slot) or not is_instance_valid(receiver) or not receiver.has_method("pixel_point"):
			continue
		if not receiver_state is Dictionary or receiver_state.is_empty() or bool(receiver_state.get("destroyed", false)):
			continue
		var targets: Variant = weapon.get("targets", [])
		if not targets is Array or targets.is_empty() or not _valid_point(targets[0]):
			continue
		var beam := str(weapon.get("kind", "")) == "beam"
		var pinpoint := beam and int(weapon.get("beam_length", 2)) == 1
		if beam and not pinpoint and (targets.size() < 2 or not _valid_point(targets[1])):
			continue
		var points: Array[Dictionary] = [targets[0]]
		if beam and not pinpoint:
			points.append(targets[1])
		var autofire := bool(weapon.get("autofire", false))
		var radius := maxf(0.0, float(weapon.get("target_radius", 0))) if not beam else 0.0
		var layout: Dictionary = receiver.get("layout_data")
		var signature := JSON.stringify([points, beam, pinpoint, autofire, radius, receiver.get_instance_id(), receiver.get("layout_center"), layout.get("x_offset", 0), layout.get("y_offset", 0)])
		if locks.has(slot) and locks[slot].signature != signature:
			_remove(slot)
		if not locks.has(slot):
			var node := Node3D.new()
			node.name = "WeaponLock%d" % (slot + 1)
			node.set_meta("weapon_slot", slot)
			node.set_meta("target_ship", side)
			node.set_meta("autofire", autofire)
			add_child(node)
			var color := AUTOFIRE if autofire else NORMAL
			var anchor: Vector3 = receiver.pixel_point(points[0], HEIGHT)
			if pinpoint:
				# Hyperspace uses the native tile center for length-one beams.
				anchor = receiver.pixel_point({"x": floorf(float(points[0].x) / 35.0) * 35.0 + 17.5,
					"y": floorf(float(points[0].y) / 35.0) * 35.0 + 17.5}, HEIGHT)
			var start := anchor
			if beam and not pinpoint:
				# Native targets[1] is the sweep start, targets[0] is its end.
				start = receiver.pixel_point(points[1], HEIGHT)
				_make_beam(node, start, anchor, color, slot)
			else:
				_make_reticle(node, anchor, slot, autofire)
				if radius > 0.0:
					_make_radius(node, anchor, radius * NATIVE_PIXEL, color)
			_finish_lines(node)
			locks[slot] = {"node": node, "receiver": receiver, "signature": signature,
				"start": start, "end": anchor, "beam": beam and not pinpoint, "radius": radius * NATIVE_PIXEL}
		keep[slot] = true
	for slot in locks.keys():
		if not keep.has(slot):
			_remove(slot)
	refresh_transforms()


func _valid_point(point: Variant) -> bool:
	if not point is Dictionary or not point.has("x") or not point.has("y"):
		return false
	return (point.x is int or point.x is float) and (point.y is int or point.y is float) and is_finite(float(point.x)) and is_finite(float(point.y))


func refresh_transforms() -> void:
	for slot in locks.keys():
		var lock: Dictionary = locks[slot]
		if not is_instance_valid(lock.receiver) or not is_instance_valid(lock.node):
			_remove(slot)
			continue
		var receiver: Node3D = lock.receiver
		var node: Node3D = lock.node
		node.global_transform = receiver.global_transform
		node.visible = receiver.is_visible_in_tree()


func _process(_delta: float) -> void:
	refresh_transforms()


func clear() -> void:
	for slot in locks.keys():
		_remove(slot)


func _remove(slot: int) -> void:
	if not locks.has(slot):
		return
	var node: Node3D = locks[slot].node
	if is_instance_valid(node):
		node.hide()
		remove_child(node)
		node.queue_free()
	locks.erase(slot)


func _make_reticle(parent: Node3D, point: Vector3, slot: int, autofire: bool) -> void:
	var suffix := "_yellow" if autofire else ""
	var path := "img/misc/crosshairs_placed%d%s.png" % [slot + 1, suffix]
	var texture: Texture2D = UiAssets.texture(path)
	if texture != null:
		var quad := QuadMesh.new()
		quad.size = texture.get_size() * NATIVE_PIXEL
		var mesh := MeshInstance3D.new()
		mesh.name = "NativeReticle"
		mesh.mesh = quad
		mesh.position = point
		mesh.rotation_degrees.x = -90.0
		var material := _material(Color.WHITE)
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = material
		parent.add_child(mesh)
		return
	# Owner-local assets are optional in source-only installs. Preserve the native
	# circle, four crosshair ticks, slot number and autofire colour procedurally.
	var color := AUTOFIRE if autofire else NORMAL
	var ring_radius := 16.0 * NATIVE_PIXEL
	for i in range(32):
		var a := float(i) * TAU / 32.0
		var b := float(i + 1) * TAU / 32.0
		_line(parent, point + Vector3(cos(a), 0, sin(a)) * ring_radius,
			point + Vector3(cos(b), 0, sin(b)) * ring_radius, color, 1.7 * NATIVE_PIXEL)
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		_line(parent, point + direction * 10.0 * NATIVE_PIXEL, point + direction * 22.0 * NATIVE_PIXEL, color, 1.7 * NATIVE_PIXEL)
	_slot_label(parent, slot, point + Vector3(0, 0.007, 23.0 * NATIVE_PIXEL), color)


func _make_beam(parent: Node3D, start: Vector3, end: Vector3, color: Color, slot: int) -> void:
	_line(parent, start, end, color, 1.8 * NATIVE_PIXEL)
	var direction := (end - start).normalized()
	if start.distance_to(end) > 0.002:
		var across := Vector3(-direction.z, 0, direction.x)
		var tip := start.lerp(end, 0.72)
		var length := minf(8.0 * NATIVE_PIXEL, start.distance_to(end) * 0.20)
		_line(parent, tip, tip - direction * length + across * length * 0.55, color, 1.8 * NATIVE_PIXEL)
		_line(parent, tip, tip - direction * length - across * length * 0.55, color, 1.8 * NATIVE_PIXEL)
	for point in [start, end]:
		_line(parent, point - Vector3.RIGHT * 5.0 * NATIVE_PIXEL, point + Vector3.RIGHT * 5.0 * NATIVE_PIXEL, color, 1.8 * NATIVE_PIXEL)
		_line(parent, point - Vector3.BACK * 5.0 * NATIVE_PIXEL, point + Vector3.BACK * 5.0 * NATIVE_PIXEL, color, 1.8 * NATIVE_PIXEL)
	_slot_label(parent, slot, start + Vector3(0, 0.009, 11.0 * NATIVE_PIXEL), color)


func _make_radius(parent: Node3D, point: Vector3, radius: float, color: Color) -> void:
	var disk := CylinderMesh.new()
	disk.top_radius = radius
	disk.bottom_radius = radius
	disk.height = 0.001
	disk.radial_segments = 48
	var mesh := MeshInstance3D.new()
	mesh.name = "FlakRadius"
	mesh.mesh = disk
	mesh.position = point - Vector3.UP * 0.007
	var material := _material(Color(color, 0.17))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 7
	mesh.material_override = material
	parent.add_child(mesh)


func _slot_label(parent: Node3D, slot: int, point: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = "WeaponSlot"
	label.text = str(slot + 1)
	label.font = UiAssets.font("body")
	label.font_size = 14
	label.pixel_size = NATIVE_PIXEL * 0.75
	label.modulate = color
	label.outline_modulate = INK
	label.outline_size = 3
	label.no_depth_test = true
	label.render_priority = 10
	label.position = point
	label.rotation_degrees.x = -90.0
	parent.add_child(label)


func _line(parent: Node3D, start: Vector3, end: Vector3, color: Color, width: float) -> void:
	if start.distance_to(end) < 0.00001:
		return
	var lines: Array = parent.get_meta("lines", [])
	lines.append([start, end, color, width])
	parent.set_meta("lines", lines)


func _finish_lines(parent: Node3D) -> void:
	var lines: Array = parent.get_meta("lines", [])
	if lines.is_empty():
		return
	# One surface for all endpoint, arrow and fallback-reticle strokes.
	var geometry := ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for outline in [true, false]:
		for line: Array in lines:
			var start: Vector3 = line[0]
			var end: Vector3 = line[1]
			var direction := (end - start).normalized()
			var width: float = line[3]
			var across := Vector3(-direction.z, 0, direction.x) * width * (1.0 if outline else 0.5)
			var offset := Vector3.UP * (0.0 if outline else 0.001)
			if outline:
				start -= direction * width * 0.5
				end += direction * width * 0.5
			geometry.surface_set_color(INK if outline else line[2])
			for vertex in [start - across, end - across, end + across, start - across, end + across, start + across]:
				geometry.surface_add_vertex(vertex + offset)
	geometry.surface_end()
	var mesh := MeshInstance3D.new()
	mesh.name = "LockLines"
	mesh.mesh = geometry
	var material := _material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	parent.add_child(mesh)
	parent.remove_meta("lines")


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 8
	return material
