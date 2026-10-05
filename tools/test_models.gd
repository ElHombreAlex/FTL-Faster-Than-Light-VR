extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const CrewModel = preload("res://scripts/voxel_crew.gd")
const WeaponModel = preload("res://scripts/voxel_weapon.gd")
const DroneModel = preload("res://scripts/voxel_drone.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")
const HullBar = preload("res://scripts/enemy_hull_bar.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _signature(node: Node) -> String:
	var result := ""
	if node is MeshInstance3D:
		var arrays: Array = node.mesh.surface_get_arrays(0)
		result += str(arrays[Mesh.ARRAY_VERTEX])
	for child in node.get_children():
		result += _signature(child)
	return result


func _run() -> void:
	var signatures: Dictionary = {}
	for race in CrewModel.SPECIES:
		var model := CrewModel.new()
		root.add_child(model)
		model.build(race)
		var signature := _signature(model)
		_check(not signatures.has(signature), "%s must have its own geometry, not a recolor" % race)
		signatures[signature] = true
		var poses: Dictionary = {}
		for state in ["work", "repair", "run", "fight"]:
			model.set_state({"working": state == "work", "repairing": state == "repair", "running": state == "run", "fighting": state == "fight"})
			model.animation_time = 0.31
			model.animate(0.11)
			var pose := str(model.arms[0].rotation) + str(model.arms[1].rotation) + str(model.torso.position) + str(model.torso.rotation)
			_check(model.animation_state == state, "%s must select native %s animation" % [race, state])
			_check(not poses.has(pose), "%s %s must have a distinct animated pose" % [race, state])
			poses[pose] = true
			_check(model.tool.visible == (state == "repair"), "Repair tool must only appear during repairs")
		model.queue_free()
	var drone_signatures: Dictionary = {}
	for family in ["combat", "beam", "defense", "hacking", "shield", "boarding", "anti_drone", "repair", "battle", "ion_boarder"]:
		var drone := DroneModel.new()
		root.add_child(drone)
		var exterior: bool = family not in ["repair", "battle", "ion_boarder"]
		var native := {"kind": family, "name": family.to_upper() + "_1", "species": family, "is_space": exterior, "powered": true, "deployed": true}
		drone.build(native)
		_check(drone.family == family, "Native %s drone identifiers must choose the matching model" % family)
		var signature := _signature(drone)
		_check(not drone_signatures.has(signature), "%s drones must have unique three-dimensional geometry rather than a recolor" % family)
		drone_signatures[signature] = true
		var duplicate := DroneModel.new()
		root.add_child(duplicate)
		duplicate.build(native)
		_check(duplicate.body.mesh == drone.body.mesh and duplicate.body.material_override == drone.body.material_override, "Matching drones must reuse immutable body mesh and material resources")
		_check(drone.body.mesh.get_aabb().size.y > 0.025, "Drone geometry must have visible depth")
		drone.set_live({"deployed": true, "powered": false})
		_check(not drone.emitter.visible and not drone.thruster.visible, "Unpowered drones must not display active exhaust or emitter glow")
		drone.set_live({"deployed": true, "powered": true, "firing": true, "fighting": true, "repairing": not exterior})
		_check(drone.emitter.material_override.emission_energy_multiplier == 1.5, "Only native firing or fighting must brighten the emitter")
		if not exterior:
			drone.animate(0.2)
			_check(not is_zero_approx(drone.tool.rotation.x), "Native interior drone activity must animate its tool")
		drone.set_live({"deployed": true, "dead": true})
		_check(not drone.visible, "Dead native drones must disappear")
		duplicate.queue_free()
		drone.queue_free()
	_check(DroneModel.model_family({"is_space": false, "species": "battle", "name": "Robot de combat"}) == "battle", "Interior drone family must use native species even with a localized crew name")
	_check(DroneModel.model_family({"is_space": false, "species": "repair", "name": "Board Master"}) == "repair", "A renamed interior drone must not override its authoritative native species")
	var mk_one := DroneModel.new()
	var mk_two := DroneModel.new()
	root.add_child(mk_one)
	root.add_child(mk_two)
	mk_one.build({"name": "COMBAT_1", "deployed": true})
	mk_two.build({"name": "COMBAT_2", "deployed": true})
	_check(_signature(mk_one) != _signature(mk_two), "Native combat Mk II must have a visibly distinct double-barrel assembly")
	mk_one.queue_free()
	mk_two.queue_free()
	var weapon_signatures: Dictionary = {}
	for kind in ["laser", "ion", "beam", "missile", "bomb", "flak"]:
		var weapon := WeaponModel.new()
		root.add_child(weapon)
		weapon.build({"kind": kind, "powered": true, "charge": 2, "cooldown": 2})
		var signature := _signature(weapon)
		_check(not weapon_signatures.has(signature), "%s must have a distinctive weapon model" % kind)
		weapon_signatures[signature] = true
		_check(is_equal_approx(weapon.charge_fill.scale.x, 0.11), "Native full charge must fill the visible top-mounted charging strip")
		weapon.set_live({"powered": true, "charge": 3, "cooldown": 12})
		_check(is_equal_approx(weapon.charge, 0.25) and is_equal_approx(weapon.charge_fill.scale.x, 0.0275), "Native elapsed cooldown must drive quarter charge without invented progression")
		var mesh_id := weapon.charge_fill.mesh.get_instance_id()
		weapon.animate(0.5)
		_check(is_equal_approx(weapon.charge, 0.25) and weapon.charge_fill.mesh.get_instance_id() == mesh_id, "Weapon animation must preserve native charge and reuse its indicator mesh")
		weapon.set_live({"powered": false, "charge_fraction": 0.8})
		_check(not weapon.emitter.visible and not weapon.charge_fill.visible, "Unpowered weapons must not display a charging or ready glow")
		weapon.set_live({"powered": true, "firing": true})
		weapon.animate(0.01)
		_check(weapon.body.position.x < 0, "%s native firing must trigger recoil" % kind)
		weapon.queue_free()
	var charge_weapon := WeaponModel.new()
	root.add_child(charge_weapon)
	charge_weapon.build({"kind": "laser", "name": "CHARGE_LASER_2", "powered": true, "charge_fraction": 0.4, "charge_max": 4, "charge_level": 2})
	_check(charge_weapon.charge_pips.size() == 4 and charge_weapon.charge_level == 2, "AE charge weapons must show actual stored shot count separately from cooldown")
	_check(charge_weapon.charge_pips[0].material_override.albedo_color == Color("92e87d") and charge_weapon.charge_pips[2].material_override.albedo_color == Color("2a4245"), "Only natively stored charge pips may light up")
	charge_weapon.queue_free()
	var hull_bar := HullBar.new()
	root.add_child(hull_bar)
	hull_bar.build()
	hull_bar.set_state({"hull": 7, "hull_max": 20})
	_check(hull_bar.visible and hull_bar.hull == 7 and hull_bar.hull_max == 20, "Enemy life bar must display the actual native hull values")
	hull_bar.set_state({"hull": 8, "hull_max": 15})
	_check(is_equal_approx(hull_bar.hull_cell_rect(0).size.x, 45.0) and is_equal_approx(hull_bar.hull_cell_rect(14).position.x, 706.0), "Fifteen native hull units must fill the contour as fifteen individual pips")
	hull_bar.position = Vector3(1, 0.4, -1)
	var viewer := Vector3(0, 1.6, 0)
	hull_bar.face_viewer(viewer)
	_check(hull_bar.global_basis.z.dot((viewer - hull_bar.global_position).normalized()) > 0.99, "Enemy hull plate must face the viewer rather than the floor")
	hull_bar.set_state({"hull": 0, "hull_max": 20, "destroyed": true})
	_check(not hull_bar.visible, "Destroyed or absent ships must not retain a phantom enemy life bar")
	hull_bar.queue_free()
	# A cropped fallback texture must extrude through the same native rectangle
	# as its visible deck, including a partially filled final sampling cell.
	var mapped_hull := ShipModel.new()
	root.add_child(mapped_hull)
	var image := Image.create(10, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	mapped_hull._make_hull_depth(image, {"x": -3, "y": 9, "w": 30, "h": 14}, Vector2.ZERO)
	var mapped_multi: MultiMesh = mapped_hull.get_node("ExtrudedHull").multimesh
	_check(mapped_multi.instance_count == 2, "Partial silhouette cells must retain their native extent")
	# The headless dummy renderer does not retain MultiMesh transforms. Check
	# their measured corner geometry, which the model keeps for shield fitting.
	var first_center := (mapped_hull.shield_fit_points[0] + mapped_hull.shield_fit_points[7]) * 0.5
	var first_width: float = mapped_hull.shield_fit_points[7].x - mapped_hull.shield_fit_points[0].x
	var last_width: float = mapped_hull.shield_fit_points[15].x - mapped_hull.shield_fit_points[8].x
	_check(is_equal_approx(first_center.x, 7.5 / 35.0 * ShipModel.TILE) and is_equal_approx(first_center.z, 16.0 / 35.0 * ShipModel.TILE), "Voxel centers must use the deck's native texture scale and offset")
	_check(is_equal_approx(first_width, 21.0 / 35.0 * ShipModel.TILE) and is_equal_approx(last_width, 9.0 / 35.0 * ShipModel.TILE), "Hull voxel widths must follow the original image mapping without extending the last cell")
	mapped_hull.queue_free()
	var ship := ShipModel.new()
	root.add_child(ship)
	ship.build("kestral", false)
	_check(ship.room_nodes[0].get_meta("system_role", "") == "pilot", "Initial blueprint roles must use canonical integer room IDs from JSON")
	_check(ship.hull_voxel_count > 500, "Owned ship art must produce a detailed solid 3D silhouette")
	_check(ship.get_node("ExtrudedHull").multimesh.instance_count == ship.hull_voxel_count, "Hull armor must use one batched MultiMesh")
	# Recorded from the current owned native Kestrel GetBaseEllipse; verify the
	# presentation shell also contains the newly added depth, not only its deck.
	ship._apply_shield_shape({"center": {"x": 232, "y": 175}, "a": 350, "b": 220})
	for point in ship.shield_fit_points:
		_check(((point - ship.shield_center) / ship.shield_radii).length_squared() <= 1.001, "The fitted shield must contain hull and room-wall corners, including the keel")
	_check(ship.shield_fit_padding <= 1.12 and ship.shield_radii.y < 1.0, "A fitted shield must cover the ship with limited footprint padding and compact height")
	var room_id: int = ship.room_nodes.keys()[0]
	var room_data := {"id": room_id, "oxygen": 100, "visible": true}
	var crew := {"id": "model-test", "species": "engi", "name": "Test", "room": room_id, "x": 510, "y": 90, "controllable": true, "working": true, "owner": 0}
	var door := {"id": 10000, "x": 400, "y": 100, "vertical": true, "open": false, "controllable": true}
	var drone := {"id": "space-test", "name": "DEFENSE_1", "kind": "defense", "is_space": true, "deployed": true, "powered": true, "x": 350, "y": 200, "angle": 3.0}
	ship.apply_live({"rooms": [room_data], "room_systems": {str(room_id): "shields"}, "crew": [crew], "doors": [door], "drones": [drone]})
	var room: Area3D = ship.room_nodes[room_id]
	_check(room.get_node_or_null("SystemIcon") != null, "System rooms must use the user's original vanilla icons")
	_check(room.get_node("SystemRole").text == "SHIELDS", "Room floor must show its installed role")
	_check(room.get_node("SystemRole").font == UiAssets.font("body") and ship.crew_nodes["model-test"].get_node("Name").font == UiAssets.font("body"), "Crew names and room roles must use the owner-local native FTL font")
	_check(ship.crew_nodes["model-test"].get_node("Model").animation_state == "work", "Live native manning must drive working animation")
	_check(ship.crew_nodes["model-test"].get_node("Model").arms[0].rotation.x > 0.7, "A crew actor first observed during pause must receive its native activity pose immediately")
	_check(ship.door_nodes["10000"].get_meta("kind") == "door", "Native door must be a selectable VR target")
	_check(ship.door_nodes["10000"].position.is_equal_approx(ship.pixel_point(door, 0.13)), "Door must use native pixel center and layout offsets")
	_check(ship.drone_nodes["space-test"].position.is_equal_approx(ship.pixel_point(drone, 0.3)), "Drone must use its native position in its current space")
	_check(is_equal_approx(ship.drone_nodes["space-test"].rotation.y, -deg_to_rad(3.0)), "Native small drone angles must remain degrees, without a radians discontinuity")
	var base_door_signature := _signature(ship.door_nodes["10000"].get_node("Left"))
	door["blast"] = 1
	ship.apply_live({"rooms": [room_data], "doors": [door]})
	var armored_door_signature := _signature(ship.door_nodes["10000"].get_node("Left"))
	_check(armored_door_signature != base_door_signature, "Blast-door strength must visibly add armor instead of simply recoloring")
	door["blast"] = 2
	ship.apply_live({"rooms": [room_data], "doors": [door]})
	_check(_signature(ship.door_nodes["10000"].get_node("Left")) != armored_door_signature, "Improved blast doors must show another distinct armor tier")
	var improved_signature := _signature(ship.door_nodes["10000"].get_node("Left"))
	door["blast"] = 3
	ship.apply_live({"rooms": [room_data], "doors": [door]})
	var strong_leaf: MeshInstance3D = ship.door_nodes["10000"].get_node("Left")
	_check(_signature(strong_leaf) != improved_signature, "Crew-boosted native door strength must retain a subtle distinct rail pattern")
	var door_bounds := strong_leaf.mesh.get_aabb()
	_check(door_bounds.size.z <= 0.03001 and door_bounds.size.x <= 0.05901 and absf(strong_leaf.position.x) + door_bounds.size.x * 0.5 <= 0.0645, "Highest-tier closed leaves must fit the original jamb and stay shallow")
	var hazard_point := {"x": 510, "y": 90, "damage": 80}
	room_data["fire_tiles"] = [hazard_point]
	room_data["breach_tiles"] = [{"x": 545, "y": 90, "damage": 20}]
	room_data["fires"] = 1
	ship.apply_live({"rooms": [room_data], "crew": [crew], "doors": [door], "drones": [drone]})
	_check(ship.room_hazards.fire_points.size() == 1 and ship.room_hazards.breach_points.size() == 1, "Native hazards must create flame and breach geometry at actual tile positions")
	_check(ship.room_hazards.fire_points[0].is_equal_approx(ship.pixel_point(hazard_point, 0.082)), "Fire visuals must share the native crew/room coordinate mapping")
	_check(ship.room_hazards.flame_outer.multimesh.instance_count == 1, "Hazards must use one batched mesh rather than per-tile particles and lights")
	ship._process(0.1)
	var closed_x: float = ship.door_nodes["10000"].get_node("Left").position.x
	door["open"] = true
	ship.apply_live({"rooms": [room_data], "crew": [crew], "doors": [door], "drones": [drone]})
	ship._process(0.2)
	_check(ship.door_nodes["10000"].get_node("Left").position.x < closed_x - 0.05, "Native open state must slide doors apart")
	ship.set_drop_target(room_id)
	_check(room.get_node("Floor").material_override.albedo_color == Color(0.35, 0.95, 0.71), "Crew drop must highlight the target room")
	ship.set_drop_target()
	_check(room.get_node("Floor").material_override.albedo_color != Color(0.35, 0.95, 0.71), "Releasing crew must restore the room's oxygen/fire tint")
	ship.simulation_paused = true
	var before: float = ship.crew_nodes["model-test"].get_node("Model").animation_time
	var hazard_before: float = ship.room_hazards.animation_time
	var recoil_before: float = ship.weapon_nodes[0].recoil
	ship._process(0.2)
	_check(ship.crew_nodes["model-test"].get_node("Model").animation_time == before, "Native pause must freeze crew animations")
	_check(ship.room_hazards.animation_time == hazard_before and ship.weapon_nodes[0].recoil == recoil_before, "Native pause must freeze fire, breach-air, and weapon presentation")
	# Viewer facing is only deck yaw, so tilted/scaled tables keep actors upright.
	ship.position = Vector3(2.0, 0.7, -1.0)
	ship.rotation = Vector3(0.17, 0.7, -0.13)
	ship.scale = Vector3(0.35, 0.4, 0.5)
	var actor: Node3D = ship.crew_nodes["model-test"]
	var actor_model: Node3D = actor.get_node("Model")
	for state in ["work", "repair", "fight", "idle"]:
		actor_model.set_state({"working": state == "work", "repairing": state == "repair", "fighting": state == "fight"})
		var local_view := actor.position + Vector3(1.5, 3.2, 0.8)
		ship.set_viewer_position(ship.to_global(local_view))
		for i in range(90): ship._process(1.0 / 90.0)
		var expected := atan2(-1.5, -0.8)
		_check(absf(wrapf(actor_model.rotation.y - expected, -PI, PI)) < 0.014, "Paused %s crew must face the viewer in the transformed deck plane" % state)
		_check(is_zero_approx(actor_model.rotation.x) and is_zero_approx(actor_model.rotation.z), "Viewer-facing crew must not pitch or roll as billboards")
		_check(actor_model.animation_time == before, "Viewer updates must not advance native paused activity")
	var yaw_before: float = actor_model.rotation.y
	ship.set_viewer_position(ship.to_global(actor.position + Vector3(0, 4, 0)))
	ship._process(0.1)
	_check(actor_model.rotation.y == yaw_before, "A viewer directly over crew must not produce an unstable yaw")
	actor_model.set_state({"running": true})
	actor.set_meta("target", actor.position + Vector3(0.25, 0, 0))
	ship._process(0.02)
	_check(is_equal_approx(actor_model.rotation.y, -PI / 2.0), "Running crew must follow actual native movement instead of the viewer")
	ship.rotation = Vector3.ZERO
	ship.scale = Vector3.ONE
	ship.apply_live({"rooms": [room_data], "room_systems": {}, "crew": [], "doors": [], "drones": []})
	_check(room.get_node_or_null("SystemRole") == null, "Empty rooms must show no meaningless floor numbers")
	_check(ship.drone_nodes.is_empty() and ship.door_nodes.is_empty(), "Expired native doors/drones must be removed")
	_check(ship.room_hazards.fire_points.size() == 1, "Existing native fire tiles must remain visible while paused")
	room_data["fire_tiles"] = []
	room_data["breach_tiles"] = []
	room_data["fires"] = 0
	ship.apply_live({"rooms": [room_data]})
	_check(ship.room_hazards.fire_points.is_empty() and ship.room_hazards.breach_points.is_empty(), "Native repair must remove hazards immediately, even during pause")
	ship.position = Vector3(2, 0.7, -1)
	ship.rotation.y = 0.7
	ship.scale = Vector3(0.35, 0.4, 0.5)
	var center := room.position
	center.y = 0.0775
	var floor_world := ship.to_global(center)
	var ray_from := floor_world + Vector3.UP
	var hit := ship.room_ray_hit(ray_from, Vector3.DOWN)
	_check(not hit.is_empty() and hit.room_id == room_id, "Room picking must find the actual floor on rotated and scaled ships")
	_check(hit.position.is_equal_approx(floor_world) and is_equal_approx(hit.distance, 1.0), "Room ray result must preserve WORLD distance and the visible floor height")
	_check(ship.pixel_point(hit.pixel, 0.0775).is_equal_approx(center), "Room floor rays must map back to exact native ship pixels")
	var bounds: Rect2 = ship.room_bounds[room_id]
	var beyond := Vector3(bounds.end.x + 0.015 / ship.global_basis.x.length(), 0.0775, bounds.get_center().y)
	var edge_from := ship.to_global(beyond) + Vector3.UP
	_check(ship.room_ray_hit(edge_from, Vector3.DOWN).is_empty(), "Strict room picking must reject rays outside the ship")
	var near_edge := ship.room_ray_hit(edge_from, Vector3.DOWN, 0.02)
	_check(not near_edge.is_empty() and near_edge.room_id == room_id and near_edge.edge_margin, "Friendly drop tolerance must use a small WORLD edge margin")
	_check(bounds.has_point(Vector2(ship.pixel_point(near_edge.pixel).x, ship.pixel_point(near_edge.pixel).z)), "Tolerant room drops must clamp native commands back inside the selected room")
	_check(ship.room_ray_hit(edge_from + ship.global_basis.x.normalized() * 0.03, Vector3.DOWN, 0.02).is_empty(), "Room drop tolerance must reject positions beyond its WORLD margin")
	_check(ship.room_ray_hit(ray_from, Vector3.RIGHT, 0.02).is_empty(), "Parallel floor rays must not pick unrelated rooms")
	ship.position = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	ship.scale = Vector3.ONE
	ship.set_shields(2, 0, false)
	_check(ship.shield_shell.visible, "Charged native shields must be visible")
	ship.set_shields(2, 0, true)
	_check(not ship.shield_shell.visible and ship.shield_charge == 2, "Native shield shutdown must hide the shell even when cached charge is unchanged")
	ship.set_shields(2, 0, false)
	_check(ship.shield_shell.visible, "Ending native shield shutdown must restore the shell without a charge transition")
	ship.set_shields(0, 0)
	_check(not ship.shield_shell.visible, "Depleted native shields must not retain a phantom shell")
	ship.set_shields(0, 5)
	_check(ship.shield_shell.visible, "Native super shields must remain visible without normal shield charge")
	var artillery := [
		{"slot": 0, "kind": "ion", "name": "BOSS_ION", "mount": {"x": 75, "y": 110}, "mount_rotate": false, "mount_mirror": true, "powered": true, "charge_fraction": 0.25},
		{"slot": 2, "kind": "laser", "name": "BOSS_LASER", "mount": {"x": 270, "y": 155}, "mount_rotate": true, "mount_mirror": false, "powered": true, "charge_fraction": 0.75},
		{"slot": 5, "kind": "missile", "name": "BOSS_MISSILE", "mount": {"x": 365, "y": 210}, "mount_rotate": false, "mount_mirror": false, "powered": false},
		{"slot": 7, "kind": "beam", "name": "BOSS_BEAM", "mount": {"x": 440, "y": 290}, "mount_rotate": true, "mount_mirror": true, "powered": true, "charge_fraction": 1.0}]
	ship.apply_live({"artillery": artillery, "weapons": [], "rooms": [room_data], "crew": [crew]})
	_check(ship.artillery_nodes.size() == 4 and not ship.weapon_nodes[0].visible, "Flagship artillery must create four models while ordinary native weapon equipment remains empty")
	for row in artillery:
		var gun: Node3D = ship.artillery_nodes[row.slot]
		var rect: Dictionary = ship.layout_data.image_rect
		var expected := Vector3((float(rect.x) + float(row.mount.x)) / 35.0 * ship.TILE - ship.layout_center.x * ship.TILE,
			0.14, (float(rect.y) + float(row.mount.y)) / 35.0 * ship.TILE - ship.layout_center.y * ship.TILE)
		_check(gun.position.is_equal_approx(expected) and ship.artillery_origin(row.slot).is_equal_approx(expected), "Artillery native mounts must use the image rectangle once, independently of sparse native slot IDs")
		_check(is_equal_approx(gun.rotation.y, 0.0 if row.mount_rotate else PI / 2.0) and is_equal_approx(gun.scale.z, -1.0 if row.mount_mirror else 1.0), "Artillery must retain native mount rotation and mirroring")
	_check(is_equal_approx(ship.artillery_nodes[2].charge, 0.75) and not ship.artillery_nodes[5].emitter.visible, "Native artillery cooldown and power must drive its visual state")
	var native_hull: MultiMeshInstance3D = ship.get_node("ExtrudedHull")
	var original_hull_material: StandardMaterial3D = native_hull.material_override
	var original_hazard_material: StandardMaterial3D = ship.room_hazards.flame_outer.material_override
	var cloak_state := {"artillery": artillery, "rooms": [room_data], "room_systems": {str(room_id): "shields"}, "crew": [crew], "cloaked": true, "cloak_progress": 1.0}
	ship.apply_live(cloak_state)
	_check(native_hull.material_override != original_hull_material and is_equal_approx(native_hull.material_override.albedo_color.a, 0.375), "Cloaking must fade hull materials in the Vulkan mobile renderer")
	_check(is_equal_approx(original_hull_material.albedo_color.a, 1.0) and original_hull_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Cloaking must leave original hull materials unmodified")
	_check(ship.room_hazards.flame_outer.material_override != original_hazard_material and ship.room_hazards.shared_visuals.FireOuter.material == original_hazard_material, "Cloaking must isolate immutable shared hazard materials from other ships")
	_check(ship.crew_nodes["model-test"].collision_layer == 1 and ship.crew_nodes["model-test"].get_node("Name").visible and room.get_node("SystemIcon").visible, "Cloaking must preserve controllable crew colliders and native targeting labels")
	room_data["oxygen"] = 0
	ship.apply_live(cloak_state)
	var cloak_floor: StandardMaterial3D = room.get_node("Floor").material_override
	_check(is_equal_approx(cloak_floor.albedo_color.a, 0.5) and cloak_floor.albedo_color.r > 0.9, "Native room tint updates must continue through cloaked material copies")
	cloak_state["cloaked"] = false
	cloak_state["cloak_progress"] = 0.5
	ship.apply_live(cloak_state)
	_check(is_equal_approx(native_hull.material_override.albedo_color.a, 0.6875), "Cloak fade-out must use native progress without inventing an animation clock")
	cloak_state["cloak_progress"] = 0.0
	ship.apply_live(cloak_state)
	_check(native_hull.material_override == original_hull_material and ship.room_hazards.flame_outer.material_override == original_hazard_material, "Uncloaking must restore the exact original material resources")
	cloak_state.erase("cloak_progress")
	cloak_state["cloaked"] = true
	ship.apply_live(cloak_state)
	ship._process(0.125)
	_check(is_equal_approx(ship.cloak_strength, 0.5) and is_equal_approx(native_hull.material_override.albedo_color.a, 0.6875), "Boolean native cloak state must ease the visible material fade when progress is unavailable")
	ship._process(0.125)
	_check(is_equal_approx(native_hull.material_override.albedo_color.a, 0.375), "Boolean cloak activation must reach the native fully cloaked hull alpha")
	cloak_state["cloaked"] = false
	ship.apply_live(cloak_state)
	ship._process(0.25)
	_check(native_hull.material_override == original_hull_material, "Boolean cloak deactivation must restore opaque hull geometry")
	ship.apply_live({"artillery": [artillery[0]]})
	_check(ship.artillery_nodes.size() == 1 and ship.artillery_nodes.has(0), "Destroyed or removed native artillery must disappear immediately")
	ship.apply_live({})
	_check(ship.artillery_nodes.is_empty(), "Absent native artillery must not leave phantom Flagship weapons")
	for asset in ["auto_assault", "fed_scout__fed_scout_pirate", "rebel_long", "energy_fighter_pirate"]:
		var opponent := ShipModel.new()
		root.add_child(opponent)
		opponent.build(asset, true)
		opponent.inspect_rooms = true
		var id: int = opponent.room_nodes.keys()[0]
		# Native geometry is authoritative, including enemy layout alignment
		# and any layout x/y offsets already applied to ship pixel coordinates.
		var native_shape := {"center": {"x": 110, "y": 160}, "a": 200, "b": 270}
		opponent.apply_live({"rooms": [{"id": id, "visible": false, "oxygen": 0, "fire_tiles": [hazard_point], "breach_tiles": [hazard_point]}], "room_systems": {str(id): "weapons"}, "crew": [], "shield_shape": native_shape, "shield": 2})
		var native_center: Vector3 = opponent.pixel_point(native_shape.center, opponent.shield_center.y)
		_check(opponent.shield_center.is_equal_approx(native_center), "%s must use the native ellipse center, without adding image alignment twice" % asset)
		_check(is_equal_approx(opponent.shield_radii.x, 200.0 / 35.0 * opponent.TILE * opponent.shield_fit_padding) and is_equal_approx(opponent.shield_radii.z, 270.0 / 35.0 * opponent.TILE * opponent.shield_fit_padding), "%s must derive its shield semiaxes from native geometry with measured visual padding" % asset)
		_check(opponent.shield_fit_padding >= 1.035 and opponent.shield_fit_padding <= 1.12, "Shield footprint fitting must remain limited instead of hiding coordinate errors")
		_check(opponent.room_nodes[id].get_node("SystemIcon").visible and opponent.room_nodes[id].get_node("SystemRole").visible, "Enemy utility icons must remain visible for targeting under sensor fog")
		_check(opponent.room_hazards.fire_points.is_empty() and opponent.room_hazards.breach_points.is_empty(), "Hidden enemy rooms must not reveal hazard tile positions through sensor fog")
		_check(opponent.room_hazards.flame_outer.multimesh.mesh == ship.room_hazards.flame_outer.multimesh.mesh, "Hazards across ships must reuse immutable mesh resources")
		opponent.queue_free()
	print("MODEL_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures, " species=8 animations=4 weapon_types=6 drone_families=10 deck_facing=paused+transformed door_tiers=4 hull_voxels=", ship.hull_voxel_count)
	ship.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
