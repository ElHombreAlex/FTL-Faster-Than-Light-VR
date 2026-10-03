extends Node3D

const TILE := 0.18
const CrewModel = preload("res://scripts/voxel_crew.gd")
const WeaponModel = preload("res://scripts/voxel_weapon.gd")
const DroneModel = preload("res://scripts/voxel_drone.gd")
const Voxels = preload("res://scripts/voxel_mesh.gd")
const RoomHazards = preload("res://scripts/room_hazards.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")
static var system_icon_textures: Dictionary = {}
static var door_leaf_meshes: Dictionary = {}
var ship_name := ""
var enemy := false
var layout_data: Dictionary = {}
var layout_center := Vector2.ZERO
var room_points: Dictionary = {}
var mount_points: Array[Vector3] = []
var shield_shell: MeshInstance3D
var shield_radii := Vector3(1.8, 0.48, 1.1)
var shield_center := Vector3.ZERO
var shield_charge := 2
var shield_flash := 0.0
var simulation_paused := false
var crew_nodes: Dictionary = {}
var room_nodes: Dictionary = {}
var room_bounds: Dictionary = {}
var room_visibility: Dictionary = {}
var weapon_nodes: Array[Node3D] = []
var door_nodes: Dictionary = {}
var drone_nodes: Dictionary = {}
var drop_target_room := -1
var hull_voxel_count := 0
var shield_fit_points := PackedVector3Array()
var shield_fit_padding := 1.0
var live_data: Dictionary = {}
var inspect_rooms := false
var demo_crew_marker: Area3D
var native_shield_geometry: Dictionary = {}
var shield_state_cache := Vector2i(-1, -1)
var room_hazards: Node3D
var viewer_position := Vector3.ZERO
var viewer_position_valid := false


func build(name: String, is_enemy: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	room_points.clear()
	mount_points.clear()
	room_nodes.clear()
	room_bounds.clear()
	room_visibility.clear()
	crew_nodes.clear()
	weapon_nodes.clear()
	door_nodes.clear()
	drone_nodes.clear()
	drop_target_room = -1
	hull_voxel_count = 0
	shield_fit_points.clear()
	shield_fit_padding = 1.0
	demo_crew_marker = null
	native_shield_geometry.clear()
	shield_state_cache = Vector2i(-1, -1)
	ship_name = name
	enemy = is_enemy
	var path := _data_path("%s.json" % name)
	var layout: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			layout = parsed
	if layout.is_empty():
		layout = _placeholder_layout()
	var rooms: Array = layout.get("rooms", [])
	var min_x := 10000.0
	var min_y := 10000.0
	var max_x := -10000.0
	var max_y := -10000.0
	for room in rooms:
		min_x = minf(min_x, float(room["x"]))
		min_y = minf(min_y, float(room["y"]))
		max_x = maxf(max_x, float(room["x"] + room["w"]))
		max_y = maxf(max_y, float(room["y"] + room["h"]))
	var center := Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
	layout_data = layout
	layout_center = center
	_make_hull(layout, center)
	for room in rooms:
		_make_room(room, center, str(layout.get("systems", {}).get(str(int(room["id"])), "")))
	if not enemy:
		_make_crew(rooms, center)
	_make_weapon_mounts(layout, center)
	_make_shield(layout)
	room_hazards = RoomHazards.new()
	room_hazards.name = "RoomHazards"
	room_hazards.build()
	add_child(room_hazards)


func _placeholder_layout() -> Dictionary:
	var rooms: Array = []
	for x in range(3):
		for y in range(2):
			rooms.append({"id": x * 2 + y, "x": x * 2, "y": y * 2, "w": 2, "h": 2})
	return {"rooms": rooms}


func _make_hull(layout: Dictionary, center: Vector2) -> void:
	var rect: Dictionary = layout.get("image_rect", {})
	var texture_path := _data_path("%s.png" % ship_name)
	if rect.is_empty() or not FileAccess.file_exists(texture_path):
		var block := MeshInstance3D.new()
		block.mesh = BoxMesh.new()
		block.scale = Vector3(1.8, 0.07, 1.15)
		block.material_override = _material(Color(0.28, 0.32, 0.43) if enemy else Color(0.28, 0.36, 0.52))
		add_child(block)
		return
	var image := Image.load_from_file(texture_path)
	if image == null:
		return
	_make_hull_depth(image, rect, center)
	var quad := QuadMesh.new()
	quad.size = Vector2(float(rect["w"]) / 35.0 * TILE, float(rect["h"]) / 35.0 * TILE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position = Vector3((float(rect["x"]) / 35.0 + float(rect["w"]) / 70.0 - center.x) * TILE,
		0.005, (float(rect["y"]) / 35.0 + float(rect["h"]) / 70.0 - center.y) * TILE)
	mesh.rotation_degrees.x = -90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)


func _make_hull_depth(image: Image, rect: Dictionary, center: Vector2) -> void:
	# Extrude the owned silhouette in colored, stepped armor. A MultiMesh keeps
	# thousands of hull blocks to one draw call per ship, with no external model.
	var step := 7
	# Map the extrusion through the same native image rectangle as the deck.
	# This also handles archives whose only available sprite is a cropped image.
	var image_scale := Vector2(float(rect["w"]) / image.get_width(), float(rect["h"]) / image.get_height())
	var opaque_cells: Array = []
	for py in range(0, image.get_height(), step):
		for px in range(0, image.get_width(), step):
			var cell_size := Vector2(mini(step, image.get_width() - px), mini(step, image.get_height() - py))
			var sample_x := mini(px + step / 2, image.get_width() - 1)
			var sample_y := mini(py + step / 2, image.get_height() - 1)
			var color := image.get_pixel(sample_x, sample_y)
			if color.a < 0.35:
				continue
			var edge := false
			for offset in [Vector2i(-step * 2, 0), Vector2i(step * 2, 0), Vector2i(0, -step * 2), Vector2i(0, step * 2)]:
				var sx: int = sample_x + offset.x
				var sy: int = sample_y + offset.y
				if sx < 0 or sy < 0 or sx >= image.get_width() or sy >= image.get_height() or image.get_pixel(sx, sy).a < 0.35:
					edge = true
			var height := 0.19 if edge else 0.32
			# Bright armor plates become a separate lower keel tier; the textured
			# deck remains above it and room floors retain their original layout.
			height += 0.035 if color.get_luminance() > 0.55 and not edge else 0.0
			var native_cell := cell_size * image_scale
			var point := Vector3((float(rect["x"]) + (px + cell_size.x * 0.5) * image_scale.x) / 35.0 * TILE - center.x * TILE,
				-height * 0.5 - 0.005, (float(rect["y"]) + (py + cell_size.y * 0.5) * image_scale.y) / 35.0 * TILE - center.y * TILE)
			var half_size := native_cell / 35.0 * TILE * 0.5
			for x_sign in [-1.0, 1.0]:
				for y_sign in [-1.0, 1.0]:
					for z_sign in [-1.0, 1.0]:
						shield_fit_points.append(point + Vector3(x_sign * half_size.x, y_sign * height * 0.5, z_sign * half_size.y))
			color = color.darkened(0.27)
			color.a = 1.0
			opaque_cells.append([point, height, color, native_cell / 35.0 * TILE])
	var block := BoxMesh.new()
	block.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = block
	multi.instance_count = opaque_cells.size()
	for i in range(opaque_cells.size()):
		multi.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(opaque_cells[i][3].x, opaque_cells[i][1], opaque_cells[i][3].y)), opaque_cells[i][0]))
		multi.set_instance_color(i, opaque_cells[i][2])
	var hull := MultiMeshInstance3D.new()
	hull.name = "ExtrudedHull"
	hull.multimesh = multi
	var material := _material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.82
	hull.material_override = material
	hull_voxel_count = opaque_cells.size()
	add_child(hull)


func _make_room(room: Dictionary, center: Vector2, system_name: String) -> void:
	var width := float(room["w"]) * TILE
	var depth := float(room["h"]) * TILE
	var location := Vector3((float(room["x"]) + float(room["w"]) / 2.0 - center.x) * TILE,
		0.065, (float(room["y"]) + float(room["h"]) / 2.0 - center.y) * TILE)
	room_points[int(room["id"])] = location + Vector3(0.0, 0.12, 0.0)
	var area := Area3D.new()
	area.set_meta("kind", "room")
	area.set_meta("ship", "enemy" if enemy else "player")
	area.set_meta("room_id", int(room["id"]))
	area.position = location
	add_child(area)
	room_nodes[int(room["id"])] = area
	room_bounds[int(room["id"])] = Rect2(Vector2(location.x - width * 0.5, location.z - depth * 0.5), Vector2(width, depth))
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			shield_fit_points.append(location + Vector3(x_sign * width * 0.5, 0.125, z_sign * depth * 0.5))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width * 0.97, 0.025, depth * 0.97)
	shape.shape = box
	area.add_child(shape)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(width * 0.97, 0.025, depth * 0.97)
	floor.mesh = floor_mesh
	floor.material_override = _material(Color(0.31, 0.35, 0.45) if enemy else Color(0.73, 0.74, 0.69))
	area.add_child(floor)
	_make_room_walls(room, area)
	_set_room_role(area, system_name)


func _make_room_walls(room: Dictionary, area: Area3D) -> void:
	var blocks: Array = []
	var color := Color("573b32") if enemy else Color("344450")
	for side in range(4):
		var horizontal := side < 2
		var count := int(room["w"] if horizontal else room["h"])
		for tile in range(count):
			var grid_x := int(room["x"]) + tile if horizontal else int(room["x"]) + (int(room["w"]) if side == 3 else 0)
			var grid_y := int(room["y"]) + (int(room["h"]) if side == 1 else 0) if horizontal else int(room["y"]) + tile
			var doorway := false
			for door in layout_data.get("doors", []):
				if int(door["x"]) == grid_x and int(door["y"]) == grid_y and bool(door["vertical"]) != horizontal:
					doorway = true
			var point := Vector3((grid_x + (0.5 if horizontal else 0.0) - layout_center.x) * TILE,
				0.065, (grid_y + (0.0 if horizontal else 0.5) - layout_center.y) * TILE) - area.position
			point.y = 0.063
			if doorway:
				for offset in [-1.0, 1.0]:
					var jamb := point + (Vector3(offset * 0.077, 0, 0) if horizontal else Vector3(0, 0, offset * 0.077))
					blocks.append(Voxels.block(jamb, Vector3(0.025, 0.10, 0.014) if horizontal else Vector3(0.014, 0.10, 0.025), color))
			else:
				blocks.append(Voxels.block(point, Vector3(TILE, 0.10, 0.014) if horizontal else Vector3(0.014, 0.10, TILE), color))
				blocks.append(Voxels.block(point + Vector3(0, 0.054, 0), Vector3(TILE, 0.01, 0.021) if horizontal else Vector3(0.021, 0.01, TILE), color.lightened(0.15)))
	var walls := Voxels.make(blocks)
	walls.name = "Walls"
	area.add_child(walls)


func _set_room_role(area: Area3D, role: String) -> void:
	if area.get_meta("system_role", "__unset") == role:
		return
	area.set_meta("system_role", role)
	for node_name in ["SystemIcon", "SystemRole"]:
		var old := area.get_node_or_null(node_name)
		if old != null:
			area.remove_child(old)
			old.queue_free()
	if role.is_empty():
		return
	var path := _data_path("ui/img/icons/s_%s.png" % role)
	if FileAccess.file_exists(path):
		if not system_icon_textures.has(path):
			var image := Image.load_from_file(path)
			if image != null:
				system_icon_textures[path] = ImageTexture.create_from_image(image)
		if system_icon_textures.has(path):
			var icon := MeshInstance3D.new()
			icon.name = "SystemIcon"
			var quad := QuadMesh.new()
			quad.size = Vector2(0.12, 0.12)
			icon.mesh = quad
			icon.rotation.x = -PI / 2.0
			icon.position.y = 0.022
			var material := StandardMaterial3D.new()
			material.albedo_texture = system_icon_textures[path]
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.albedo_color = Color("fff2c4") if enemy else Color("223844")
			icon.material_override = material
			area.add_child(icon)
	var label := Label3D.new()
	label.name = "SystemRole"
	label.font = UiAssets.font("body")
	label.outline_size = 0
	var names := {"pilot": "PILOT", "weapons": "WEAPONS", "shields": "SHIELDS", "engines": "ENGINES",
		"oxygen": "OXYGEN", "medbay": "MEDBAY", "doors": "DOORS", "sensors": "SENSORS", "drones": "DRONES",
		"teleporter": "TELEPORT", "cloaking": "CLOAK", "artillery": "ARTILLERY", "battery": "BATTERY",
		"clonebay": "CLONE BAY", "mind": "MIND", "hacking": "HACKING"}
	label.text = str(names.get(role, role.to_upper()))
	label.font_size = 32
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.pixel_size = 0.00075
	label.modulate = Color("fff2c4") if enemy else Color("223844")
	label.position = Vector3(0, 0.023, 0.09)
	label.rotation.x = -PI / 2.0
	area.add_child(label)


func set_drop_target(room_id: int = -1) -> void:
	if drop_target_room == room_id:
		return
	drop_target_room = room_id
	for id in room_nodes:
		var floor: MeshInstance3D = room_nodes[id].get_node("Floor")
		floor.material_override.albedo_color = Color(0.35, 0.95, 0.71) if id == room_id else floor.get_meta("normal_tint", Color(0.65, 0.7, 0.73))


func room_ray_hit(from: Vector3, direction: Vector3, margin_m: float = 0.0) -> Dictionary:
	# Test the floor the player sees, rather than the taller crew/door colliders.
	# The ray parameter remains a WORLD distance through scaled ship transforms.
	if not is_visible_in_tree() or direction.length_squared() < 0.000001:
		return {}
	var normalized := direction.normalized()
	var local_from := to_local(from)
	var local_direction := global_basis.inverse() * normalized
	if absf(local_direction.y) < 0.000001:
		return {}
	var distance := (0.0775 - local_from.y) / local_direction.y
	if distance < 0.0 or distance > 20.0:
		return {}
	var point := local_from + local_direction * distance
	var floor_point := Vector2(point.x, point.z)
	var best_id := -1
	var best_edge_distance := INF
	for id in room_bounds:
		var rect: Rect2 = room_bounds[id]
		if rect.has_point(floor_point):
			best_id = id
			best_edge_distance = 0.0
			break
		if margin_m <= 0.0:
			continue
		var closest := floor_point.clamp(rect.position, rect.end)
		var closest_world := to_global(Vector3(closest.x, 0.0775, closest.y))
		var edge_distance := closest_world.distance_to(to_global(point))
		if edge_distance <= margin_m and edge_distance < best_edge_distance:
			best_id = id
			best_edge_distance = edge_distance
	if best_id < 0:
		return {}
	var selected_rect: Rect2 = room_bounds[best_id]
	# Keep rounded native mouse coordinates one pixel inside the chosen room.
	var native_pixel_padding := Vector2.ONE * TILE / 35.0
	var command_point := floor_point.clamp(selected_rect.position + native_pixel_padding, selected_rect.end - native_pixel_padding)
	return {"collider": room_nodes[best_id], "position": to_global(point), "distance": distance,
		"room_id": best_id, "ship": "enemy" if enemy else "player", "edge_margin": best_edge_distance > 0.0,
		"edge_distance": best_edge_distance, "room_position": to_global(Vector3(command_point.x, point.y, command_point.y)),
		"pixel": {"x": (command_point.x / TILE + layout_center.x + float(layout_data.get("x_offset", 0))) * 35.0,
			"y": (command_point.y / TILE + layout_center.y + float(layout_data.get("y_offset", 0))) * 35.0}}


func _apply_doors(doors: Array) -> void:
	var present: Dictionary = {}
	for data in doors:
		var id := str(data["id"])
		present[id] = true
		if not door_nodes.has(id):
			var area := Area3D.new()
			area.set_meta("kind", "door")
			area.set_meta("door_id", data["id"])
			area.set_meta("ship", "enemy" if enemy else "player")
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.15, 0.15, 0.04)
			collider.shape = shape
			area.add_child(collider)
			add_child(area)
			door_nodes[id] = area
		var door: Area3D = door_nodes[id]
		# iBlast reports the actual native blast-door strength, including crew
		# bonuses. Old snapshots can fall back to the installed doors level.
		var tier := clampi(int(data.get("blast", maxi(0, int(data.get("level", live_data.get("door_level", 1))) - 1))), 0, 3)
		if door.get_meta("blast_tier", -1) != tier:
			door.set_meta("blast_tier", tier)
			door.remove_meta("tint")
			for side in [-1.0, 1.0]:
				var leaf_name := "Left" if side < 0 else "Right"
				var previous := door.get_node_or_null(leaf_name)
				if previous != null:
					door.remove_child(previous)
					previous.queue_free()
				var leaf := _make_door_leaf(tier)
				leaf.name = leaf_name
				leaf.position.x = side * (0.031 + float(door.get_meta("opening", 0.0)) * 0.065)
				door.add_child(leaf)
		door.position = pixel_point(data, 0.13)
		door.rotation.y = PI / 2.0 if bool(data.get("vertical", false)) else 0.0
		door.visible = not enemy or (inspect_rooms and (_room_visible(int(data.get("room_a", -1))) or _room_visible(int(data.get("room_b", -1)))))
		door.collision_layer = 1 if door.visible and not enemy and bool(data.get("controllable", false)) else 0
		door.set_meta("open", bool(data.get("open", false)))
		door.set_meta("native", data)
		var tint := Color.WHITE
		if bool(data.get("hacked", false)):
			tint = Color("ac70ca")
		elif bool(data.get("locked", false)) or bool(data.get("ionized", false)):
			tint = Color("eab166")
		elif float(data.get("health", 1)) < float(data.get("max_health", 1)):
			tint = Color("ea7166")
		if door.get_meta("tint", Color(-1, -1, -1)) != tint:
			door.set_meta("tint", tint)
			for name in ["Left", "Right"]:
				door.get_node(name).material_override.albedo_color = tint
	for id in door_nodes.keys():
		if not present.has(id):
			door_nodes[id].queue_free()
			door_nodes.erase(id)


func _make_door_leaf(tier: int) -> MeshInstance3D:
	if not door_leaf_meshes.has(tier):
		# All native strength tiers fit the same jamb opening. Reinforcement
		# remains shallow and inset rather than stacking oversized outer frames.
		var blocks := [Voxels.block(Vector3.ZERO, Vector3(0.059, 0.092, 0.015), Color("bac9d0")),
			Voxels.block(Vector3(0, -0.035, 0), Vector3(0.057, 0.008, 0.019), Color("6d858d"))]
		for z in [-0.0085, 0.0085]:
			blocks.append(Voxels.block(Vector3(0, 0.020, z), Vector3(0.033, 0.008, 0.003), Color("4c8792")))
		if tier > 0:
			for z in [-0.010, 0.010]:
				blocks.append(Voxels.block(Vector3(0, -0.006, z), Vector3(0.047, 0.048, 0.005), Color("82959d")))
		if tier > 1:
			for z in [-0.0135, 0.0135]:
				for y in [-0.023, 0.007]:
					blocks.append(Voxels.block(Vector3(0, y, z), Vector3(0.046, 0.006, 0.003), Color("b0ad92")))
		if tier > 2:
			for z in [-0.0135, 0.0135]:
				for x in [-0.021, 0.021]:
					blocks.append(Voxels.block(Vector3(x, -0.008, z), Vector3(0.004, 0.043, 0.003), Color("b0ad92")))
				blocks.append(Voxels.block(Vector3(0, 0.032, z), Vector3(0.014, 0.005, 0.003), Color("8f9e9c")))
		var source: MeshInstance3D = Voxels.make(blocks)
		door_leaf_meshes[tier] = source.mesh
		source.free()
	var leaf := MeshInstance3D.new()
	leaf.mesh = door_leaf_meshes[tier]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	leaf.material_override = material
	return leaf


func _apply_drones(drones: Array) -> void:
	var present: Dictionary = {}
	for data in drones:
		if not bool(data.get("is_space", false)) or not bool(data.get("deployed", false)) or bool(data.get("dead", false)):
			continue
		var id := str(data["id"])
		present[id] = true
		if not drone_nodes.has(id):
			var model := DroneModel.new()
			model.build(data)
			add_child(model)
			drone_nodes[id] = model
			model.position = pixel_point(data, 0.3)
			model.rotation.y = -deg_to_rad(float(data.get("angle", 0)))
		var drone: Node3D = drone_nodes[id]
		drone.set_live(data)
		# Positions come from the native drone's current space, regrouped by the
		# bridge; attack drones therefore orbit the receiver, not their owner.
		drone.set_meta("target", pixel_point(data, 0.3))
		# FTL's current_angle wraps at 360 (native CustomDrones.cpp).
		drone.set_meta("target_angle", -deg_to_rad(float(data.get("angle", 0))))
	for id in drone_nodes.keys():
		if not present.has(id):
			drone_nodes[id].queue_free()
			drone_nodes.erase(id)


func _make_crew(rooms: Array, center: Vector2) -> void:
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[min(rooms.size() - 1, 2)]
	var marker := _make_miniature({"id": "crew_1", "name": "Crew", "species": "human", "x": 0, "y": 0})
	demo_crew_marker = marker
	marker.position = Vector3((float(room["x"]) + 0.5 - center.x) * TILE, 0.19,
		(float(room["y"]) + 0.5 - center.y) * TILE)


func _make_weapon_mounts(layout: Dictionary, center: Vector2) -> void:
	var rect: Dictionary = layout.get("image_rect", {"x": 0, "y": 0})
	for mount in layout.get("weapon_mounts", []):
		var point := Vector3((float(rect["x"]) + float(mount["x"])) / 35.0 * TILE - center.x * TILE,
			0.14, (float(rect["y"]) + float(mount["y"])) / 35.0 * TILE - center.y * TILE)
		mount_points.append(point)
		var gun := WeaponModel.new()
		gun.position = point
		gun.rotation.y = 0.0 if str(mount.get("rotate", "false")) == "true" else PI / 2.0
		gun.build({"kind": "laser", "powered": false})
		add_child(gun)
		weapon_nodes.append(gun)
	if mount_points.is_empty():
		mount_points.append(Vector3(0.5, 0.14, 0.0))


func _make_shield(layout: Dictionary) -> void:
	var ellipse: Array = layout.get("ellipse", [350, 220, 0, 0])
	shield_radii = Vector3(float(ellipse[0]) / 35.0 * TILE, 0.48, float(ellipse[1]) / 35.0 * TILE)
	shield_center = Vector3(0.0, 0.06, 0.0)
	var rect: Dictionary = layout.get("image_rect", {})
	if not rect.is_empty():
		# A preview without live FTL uses the hull center. The live snapshot
		# replaces this with GetBaseEllipse; layout ELLIPSE offsets cannot be
		# added to the image center because they use the native graph alignment.
		shield_center.x = (float(rect["x"]) + float(rect["w"]) / 2.0) / 35.0 * TILE - layout_center.x * TILE
		shield_center.z = (float(rect["y"]) + float(rect["h"]) / 2.0) / 35.0 * TILE - layout_center.y * TILE
	shield_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	shield_shell.mesh = sphere
	shield_radii = _fit_shield_volume(shield_radii)
	shield_shell.position = shield_center
	shield_shell.scale = shield_radii
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/shield.gdshader")
	shield_shell.material_override = material
	add_child(shield_shell)
	set_shields(2)


func set_shields(charge: int, super_shield: int = 0) -> void:
	shield_charge = maxi(charge, 0)
	if shield_shell == null:
		return
	var current := Vector2i(shield_charge, super_shield)
	if current == shield_state_cache:
		return
	shield_state_cache = current
	shield_shell.visible = shield_charge > 0 or super_shield > 0
	var material: ShaderMaterial = shield_shell.material_override
	material.set_shader_parameter("shield_color", Color(0.23, 0.95, 0.35) if super_shield > 0 else Color(0.18, 0.58, 1.0))
	material.set_shader_parameter("strength", clampf(shield_charge / 4.0, 0.25, 1.0))


func _apply_shield_shape(shape: Dictionary) -> void:
	if shape.is_empty() or shape == native_shield_geometry or shield_shell == null:
		return
	var center: Dictionary = shape.get("center", {})
	var radius_x := float(shape.get("a", 0))
	var radius_z := float(shape.get("b", 0))
	if center.is_empty() or radius_x <= 0.0 or radius_z <= 0.0:
		return
	# GetBaseEllipse is in the same native ship-local pixel space as crew,
	# rooms and doors. Enemy layout ELLIPSE offsets include native alignment
	# adjustments; adding them to the hull image center a second time was wrong.
	native_shield_geometry = shape.duplicate(true)
	shield_center = pixel_point(center, 0.06)
	shield_radii = Vector3(radius_x / 35.0 * TILE, 0.48, radius_z / 35.0 * TILE)
	shield_radii = _fit_shield_volume(shield_radii)
	shield_shell.position = shield_center
	shield_shell.scale = shield_radii


func _fit_shield_volume(native_radii: Vector3) -> Vector3:
	# Keep the native X/Z center and near-native footprint. The 2D game's
	# ellipse needs vertical clearance for the newly extruded keel and walls.
	# Measure actual model corners rather than sizing a bubble by ship class.
	var max_radial := 0.0
	var minimum_y := INF
	var maximum_y := -INF
	for point in shield_fit_points:
		var delta := point - shield_center
		var radial := Vector2(delta.x / native_radii.x, delta.z / native_radii.z).length()
		max_radial = maxf(max_radial, radial)
		minimum_y = minf(minimum_y, point.y)
		maximum_y = maxf(maximum_y, point.y)
	if not shield_fit_points.is_empty():
		# Native FTL has no height axis. Center that presentation axis between
		# the keel and the deck, with room for miniature heads above the walls.
		shield_center.y = (minimum_y + maximum_y + 0.06) * 0.5
	# At most 12% footprint padding: a bad native coordinate transform must
	# remain detectable instead of being hidden by an enormous shell.
	shield_fit_padding = minf(1.12, maxf(1.035, max_radial * 1.035))
	var fitted := Vector3(native_radii.x * shield_fit_padding, native_radii.y, native_radii.z * shield_fit_padding)
	for point in shield_fit_points:
		var delta := point - shield_center
		var radial_squared := pow(delta.x / fitted.x, 2) + pow(delta.z / fitted.z, 2)
		if radial_squared < 0.9999:
			var required_height := absf(delta.y) / sqrt(1.0 - radial_squared)
			fitted.y = maxf(fitted.y, required_height * 1.02)
	return fitted


func flash_shield() -> void:
	shield_flash = 1.0


func set_viewer_position(world_position: Vector3) -> void:
	viewer_position = world_position
	viewer_position_valid = true


func _process(delta: float) -> void:
	if not simulation_paused:
		shield_flash = maxf(0.0, shield_flash - delta * 3.0)
	if shield_shell != null:
		var material: ShaderMaterial = shield_shell.material_override
		material.set_shader_parameter("hit_flash", shield_flash)
	var local_viewer := to_local(viewer_position) if viewer_position_valid else Vector3.ZERO
	for id in crew_nodes:
		var miniature: Node3D = crew_nodes[id]
		var model: Node3D = miniature.get_node("Model")
		if miniature.has_meta("target"):
			var movement: Vector3 = Vector3(miniature.get_meta("target")) - miniature.position
			miniature.position = miniature.position.lerp(miniature.get_meta("target"), minf(1.0, delta * 18.0))
			if model is CrewModel:
				model.face_movement(movement)
		if model is CrewModel and viewer_position_valid:
			# The inverse ship transform handles rotated, scaled and tilted
			# tables. Viewer yaw follows presentation even when FTL is paused.
			model.face_viewer(local_viewer - miniature.position, delta)
		if not simulation_paused:
			model.animate(delta)
	if not simulation_paused:
		for weapon in weapon_nodes:
			weapon.animate(delta)
		for drone in drone_nodes.values():
			drone.animate(delta)
		if is_instance_valid(room_hazards):
			room_hazards.animate(delta)
	for drone in drone_nodes.values():
		# Smooth native 10 Hz samples without extrapolating an orbit or target.
		drone.position = drone.position.lerp(drone.get_meta("target", drone.position), minf(1.0, delta * 18.0))
		drone.rotation.y = lerp_angle(drone.rotation.y, float(drone.get_meta("target_angle", drone.rotation.y)), minf(1.0, delta * 18.0))
	for door in door_nodes.values():
		var opening := float(door.get_meta("opening", 0.0))
		opening = move_toward(opening, 1.0 if door.get_meta("open", false) else 0.0, delta * 8.0)
		door.set_meta("opening", opening)
		door.get_node("Left").position.x = -0.031 - opening * 0.065
		door.get_node("Right").position.x = 0.031 + opening * 0.065


func pixel_point(point: Dictionary, height: float = 0.18) -> Vector3:
	return Vector3((float(point.get("x", 0)) / 35.0 - float(layout_data.get("x_offset", 0)) - layout_center.x) * TILE,
		height, (float(point.get("y", 0)) / 35.0 - float(layout_data.get("y_offset", 0)) - layout_center.y) * TILE)


func apply_live(data: Dictionary) -> void:
	live_data = data
	room_visibility.clear()
	for room in data.get("rooms", []):
		room_visibility[int(room["id"])] = bool(room.get("visible", false))
	# Replace the demonstration marker with actual crew; ids remain stable per run.
	if is_instance_valid(demo_crew_marker):
		remove_child(demo_crew_marker)
		demo_crew_marker.queue_free()
		demo_crew_marker = null
	var present: Dictionary = {}
	for crew in data.get("crew", []):
		var id := str(crew["id"])
		present[id] = true
		if not crew_nodes.has(id):
			crew_nodes[id] = _make_miniature(crew)
		var miniature: Area3D = crew_nodes[id]
		miniature.set_meta("target", pixel_point(crew, 0.085))
		miniature.visible = not enemy or (inspect_rooms and _room_visible(int(crew["room"])))
		miniature.set_meta("controllable", bool(crew.get("controllable", false)))
		miniature.collision_layer = 1 if miniature.visible and bool(crew.get("controllable", false)) else 0
		var label: Label3D = miniature.get_node("Name")
		label.text = str(crew["name"]) + (" *" if crew.get("selected", false) else "")
		label.modulate = Color(1.0, 0.4, 0.3) if int(crew.get("owner", 0)) != 0 else Color.WHITE
		var model: Node3D = miniature.get_node("Model")
		if model is CrewModel:
			var race: String = CrewModel.canonical_species(str(crew.get("species", "human")))
			if model.species != race and CrewModel.SPECIES.has(race):
				model.build(race)
			model.set_state(crew)
		else:
			model.set_live(crew)
	for id in crew_nodes.keys():
		if not present.has(id):
			crew_nodes[id].queue_free()
			crew_nodes.erase(id)
	for room in data.get("rooms", []):
		var id := int(room["id"])
		if not room_nodes.has(id):
			continue
		var area: Area3D = room_nodes[id]
		if data.has("room_systems"):
			_set_room_role(area, str(data.get("room_systems", {}).get(str(id), "")))
		for visual in area.get_children():
			if visual is VisualInstance3D:
				visual.visible = not enemy or inspect_rooms
				# Installed systems remain useful targeting information in vanilla
				# FTL when enemy crew / oxygen are obscured by the sensor fog.
		var floor_mesh: MeshInstance3D = area.get_node("Floor")
		var oxygen := float(room.get("oxygen", 100)) / 100.0
		var tint := Color(0.9, 0.22, 0.08) if int(room.get("fires", 0)) > 0 else Color(0.65, 0.7, 0.73).lerp(Color(0.95, 0.38, 0.4), 1.0 - oxygen)
		if enemy and not bool(room.get("visible", false)):
			tint = Color(0.12, 0.14, 0.17)
		floor_mesh.set_meta("normal_tint", tint)
		if id == drop_target_room:
			tint = Color(0.35, 0.95, 0.71)
		if floor_mesh.material_override.albedo_color != tint:
			floor_mesh.material_override.albedo_color = tint
	var weapons: Array = data.get("weapons", [])
	for slot in range(weapon_nodes.size()):
		weapon_nodes[slot].visible = slot < weapons.size()
		if slot < weapons.size():
			var weapon: Node3D = weapon_nodes[slot]
			if weapon.kind != WeaponModel.canonical_kind(str(weapons[slot].get("kind", "laser"))) or weapon.weapon_name != str(weapons[slot].get("name", "")):
				weapon.build(weapons[slot])
			weapon.set_live(weapons[slot])
	_apply_doors(data.get("doors", []))
	_apply_drones(data.get("drones", []))
	if is_instance_valid(room_hazards):
		room_hazards.set_live(self, data)
	_apply_shield_shape(data.get("shield_shape", {}))
	set_shields(int(data.get("shield", 0)), int(data.get("super_shield", 0)))


func _room_visible(id: int) -> bool:
	return bool(room_visibility.get(id, false))


func _make_miniature(crew: Dictionary) -> Area3D:
	var miniature := Area3D.new()
	miniature.set_meta("kind", "crew")
	miniature.set_meta("crew_id", str(crew["id"]))
	miniature.set_meta("ship", "enemy" if enemy else "player")
	miniature.position = pixel_point(crew, 0.085)
	add_child(miniature)
	var collision := CollisionShape3D.new()
	var hitbox := CapsuleShape3D.new()
	hitbox.radius = 0.05
	hitbox.height = 0.18
	collision.shape = hitbox
	collision.position.y = 0.075
	miniature.add_child(collision)
	var model: Node3D
	if bool(crew.get("is_drone", false)):
		model = DroneModel.new()
		var drone_data := crew.duplicate()
		drone_data["is_space"] = false
		model.build(drone_data)
	else:
		model = CrewModel.new()
		model.build(str(crew.get("species", "human")))
	model.name = "Model"
	miniature.add_child(model)
	var label := Label3D.new()
	label.name = "Name"
	label.font = UiAssets.font("body")
	label.outline_size = 0
	label.text = str(crew["name"])
	label.font_size = 32
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.pixel_size = 0.001
	label.position.y = 0.18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	miniature.add_child(label)
	return miniature


func weapon_origin(slot: int) -> Vector3:
	return to_global(mount_points[posmod(slot, mount_points.size())])


func room_target(room_id: int) -> Vector3:
	return to_global(room_points.get(room_id, Vector3(0.0, 0.18, 0.0)))


func shield_intercept(from: Vector3, target: Vector3) -> Vector3:
	var local_start := (to_local(from) - shield_center) / shield_radii
	var local_end := (to_local(target) - shield_center) / shield_radii
	var direction := local_end - local_start
	var a := direction.dot(direction)
	var b := 2.0 * local_start.dot(direction)
	var c := local_start.dot(local_start) - 1.0
	var discriminant := b * b - 4.0 * a * c
	if a < 0.00001 or discriminant < 0.0:
		return target
	var t := (-b - sqrt(discriminant)) / (2.0 * a)
	if t < 0.0 or t > 1.0:
		return target
	return from.lerp(target, t)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _data_path(file_name: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://local_game_data/%s" % file_name)
	return OS.get_executable_path().get_base_dir().path_join("local_game_data").path_join(file_name)
