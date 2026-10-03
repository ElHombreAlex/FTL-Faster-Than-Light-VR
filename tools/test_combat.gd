extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var player: Node3D = scene.player_ship
	var enemy: Node3D = scene.enemy_ship
	var effects: Node3D = scene.combat_effects
	player.set_process(false)
	enemy.set_process(false)
	effects.set_process(false)
	_check(player.global_basis.x.normalized().dot(Vector3.RIGHT) > 0.99, "Player bow must face enemy")
	_check((-enemy.global_basis.z).normalized().dot(Vector3.LEFT) > 0.99, "Enemy bow must face player")
	_check(scene.hud_surface.get_parent() == scene.camera, "HUD must follow the tracked headset")
	for ship in [player, enemy]:
		_check(ship.weapon_origin(0).is_equal_approx(ship.to_global(ship.mount_points[0])), "Mount must use the ship world transform")
		_check(ship.room_target(0).is_equal_approx(ship.to_global(ship.room_points[0])), "Target room must use the ship world transform")
		ship.set_shields(0)
		_check(not ship.shield_shell.visible, "Empty shields must disappear")
		ship.set_shields(0, 5)
		_check(ship.shield_shell.visible, "Super shields must remain visible")
		ship.set_shields(2)
	var from: Vector3 = player.weapon_origin(0)
	var target: Vector3 = enemy.room_target(0)
	var hit: Vector3 = enemy.shield_intercept(from, target)
	var normalized: Vector3 = (enemy.to_local(hit) - enemy.shield_center) / enemy.shield_radii
	_check(absf(normalized.length() - 1.0) < 0.001, "Shield hit must lie on the rotated ellipsoid")
	_check(from.distance_to(hit) < from.distance_to(target), "Shield must intercept before the target room")
	for source in ["player", "enemy"]:
		var sender: Node3D = player if source == "player" else enemy
		var receiver: Node3D = enemy if source == "player" else player
		scene._present_shot({"source": source, "kind": "laser", "target_room": 0, "outcome": "hull", "duration": 1.0})
		var shot: Dictionary = effects.shots.back()
		_check(Vector3(shot["start"]).is_equal_approx(sender.weapon_origin(0)), "Shot must originate at sender weapon")
		_check(Vector3(shot["end"]).is_equal_approx(receiver.room_target(0)), "Shot must terminate at receiver room")
		var node: MeshInstance3D = shot["node"]
		effects._process(0.5)
		_check(node.global_position.is_equal_approx(Vector3(shot["start"]).lerp(shot["end"], 0.5)), "Projectile must travel between ships")
		effects.simulation_paused = true
		var paused_position := node.global_position
		effects._process(0.4)
		_check(node.global_position.is_equal_approx(paused_position), "Pause must freeze projectiles")
		effects.simulation_paused = false
		effects._process(0.6)
		_check(effects.shots.is_empty(), "Finished projectile must be removed")
		_check(not effects.impacts.is_empty(), "Hull hit must produce an impact")
		effects.simulation_paused = true
		var flash: MeshInstance3D = effects.impacts.back()["node"]
		var flash_scale := flash.scale
		effects._process(0.4)
		_check(flash.scale == flash_scale, "Pause must freeze impact flashes")
		effects.simulation_paused = false
		effects._process(0.3)
	var impact_count: int = effects.impacts.size()
	scene._present_shot({"source": "player", "kind": "laser", "outcome": "miss", "duration": 0.1})
	effects._process(0.2)
	_check(effects.impacts.size() == impact_count, "Miss must not produce a hull impact")
	scene._present_shot({"source": "enemy", "kind": "bomb", "outcome": "hull", "duration": 1.0})
	_check(not effects.shots.back()["node"].visible, "Bomb must teleport rather than fly through space")
	effects._process(1.1)
	scene._present_shot({"source": "player", "kind": "beam", "outcome": "shield", "target_room": 0, "end_room": 4, "duration": 1.0})
	effects._process(0.5)
	var beam: Dictionary = effects.shots.back()
	var mesh: ImmediateMesh = beam["node"].mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices[0].is_equal_approx(effects.to_local(player.weapon_origin(0))), "Beam must connect to sender mount")
	var core: MeshInstance3D = beam["node"].get_node("BeamCore")
	var swept_endpoint: Vector3 = Vector3(beam["end"]).lerp(beam["beam_end"], 0.5)
	_check(core.global_position.is_equal_approx((player.weapon_origin(0) + swept_endpoint) * 0.5), "Visible beam cylinder must follow its exact native sweep line")
	_check(absf(core.global_basis.y.length() - player.weapon_origin(0).distance_to(swept_endpoint)) < 0.001, "Beam transform must preserve its emitter and target positions")
	_check(core.mesh == beam["node"].get_node("BeamGlow").mesh and core.mesh.height == 1.0, "Beam layers must reuse immutable unit geometry")
	var mesh_changes := {"count": 0}
	core.mesh.changed.connect(func(): mesh_changes["count"] += 1)
	effects._process(0.1)
	_check(mesh_changes["count"] == 0, "A live sweep must not rebuild shared beam geometry")
	var endpoint: Vector3 = beam["beam_end"]
	_check(absf(((enemy.to_local(endpoint) - enemy.shield_center) / enemy.shield_radii).length() - 1.0) < 0.001, "Blocked beam must stay on shield")
	effects._process(0.6)
	_check(enemy.shield_flash > 0.0, "Shield impact must flash")
	effects._process(0.3)
	scene._present_shot({"source": "player", "kind": "laser", "outcome": "pending", "projectile_id": "live-miss", "target_room": 0})
	effects.update_live_projectiles([{"id": "live-miss", "progress": 0.7, "missed": true}])
	effects._process(0.1)
	_check(Vector3(effects.shots.back()["end"]).distance_to(enemy.room_target(0)) > 0.4, "Native miss trajectory must survive endpoint updates")
	effects.update_live_projectiles([])
	effects._process(0.3)
	effects.update_live_projectiles([])
	scene._present_shot({"source": "player", "kind": "beam", "outcome": "pending", "projectile_id": "live-beam", "target_room": 0, "end_point": {"x": 100, "y": 180}})
	var beam_point := {"x": 80, "y": 170}
	effects.update_live_projectiles([{"id": "live-beam", "progress": 0.65, "beam_point": beam_point}])
	effects._process(0.1)
	var live_beam: Dictionary = effects.shots.back()
	var live_mesh: ImmediateMesh = live_beam["node"].mesh
	var live_vertices: PackedVector3Array = live_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(live_vertices[1].is_equal_approx(effects.to_local(enemy.to_global(enemy.pixel_point(beam_point)))), "Live beam must follow FTL's current sweep position")
	effects.resolve_live({"projectile_id": "live-beam", "outcome": "beam", "target": beam_point}, enemy)
	_check(effects.shots.size() == 1, "First beam room hit must not delete a continuing sweep")
	effects.update_live_projectiles([])
	effects._process(0.4)
	effects.update_live_projectiles([])
	for kind in ["laser", "missile", "ion", "asteroid"]:
		effects.spawn_shot({"source": "player", "kind": kind, "outcome": "hull", "duration": 1.0, "target_room": 0}, player, enemy)
		var refined: Dictionary = effects.shots.back()
		effects._process(0.5)
		var refined_node: MeshInstance3D = refined["node"]
		var direction: Vector3 = Vector3(refined["end"]) - Vector3(refined["start"])
		_check((-refined_node.global_basis.z).normalized().dot(direction.normalized()) > 0.999, "Projectile model must point from sender toward receiver")
		_check(refined_node.global_position.is_equal_approx(Vector3(refined["start"]).lerp(refined["end"], 0.5)), "Refined geometry must preserve authoritative travel timing")
		effects._process(0.6)
	# A combat drone can be owned by the player while physically orbiting the
	# enemy. A defense drone can instead target a missile in its own space.
	var drone_origin := {"x": 90, "y": 130}
	var drone_target := {"x": 170, "y": 120}
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "defense",
		"origin_point": drone_origin, "origin_space": 1, "target": drone_target,
		"target_space": 1}, player, enemy)
	effects.update_live_projectiles([{"id": "defense", "progress": 0.4}])
	effects._process(0.1)
	var defense: Dictionary = effects.shots.back()
	_check(Vector3(defense["start"]).is_equal_approx(enemy.to_global(enemy.pixel_point(drone_origin))), "Boarding drone fire must originate in its current native space")
	_check(Vector3(defense["end"]).is_equal_approx(enemy.to_global(enemy.pixel_point(drone_target))), "Defense drone fire must target the actual native space and point")
	# A paused native projectile remains frozen even beyond the presentation
	# grace. A stale fire record must expire despite simulation time standing still.
	effects.simulation_paused = true
	var paused_native_node: MeshInstance3D = defense["node"]
	var paused_native_position := paused_native_node.global_position
	var paused_native_time: float = defense["time"]
	var paused_impact_count: int = effects.impacts.size()
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "paused-phantom"}, player, enemy)
	effects.update_live_projectiles([{"id": "defense", "progress": 0.4}])
	_check(effects.shots.size() == 2, "A newly received fire record must retain a short snapshot grace")
	var grace_start_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - grace_start_ms < 360:
		await process_frame
	effects._process(1.0)
	effects.update_live_projectiles([{"id": "defense", "progress": 0.4}])
	_check(effects.shots.size() == 1 and effects.shots[0]["projectile_id"] == "defense", "Paused never-observed fire must expire using monotonic presentation time")
	_check(paused_native_node.global_position == paused_native_position and defense["time"] == paused_native_time, "A genuinely active paused projectile must remain frozen beyond the grace")
	effects.update_live_projectiles([])
	_check(effects.shots.is_empty(), "A previously observed projectile must disappear immediately when native state removes it during pause")
	_check(effects.impacts.size() == paused_impact_count, "Stale projectile cleanup must not invent a hit")
	effects.spawn_shot({"kind": "beam", "outcome": "pending", "projectile_id": "paused-beam"}, player, enemy)
	effects.update_live_projectiles([{"id": "paused-beam", "progress": 0.4}])
	effects.resolve_live({"projectile_id": "paused-beam", "outcome": "beam", "target": beam_point}, enemy)
	_check(effects.shots.size() == 1, "A paused beam tile hit must retain the native continuing sweep")
	print("COMBAT_TESTS ", "PASS" if failures == 0 else "FAIL: %d" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
