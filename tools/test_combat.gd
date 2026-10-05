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
	_check(scene.hud_surface.get_parent() == scene, "Gameplay HUD must support spatial placement without inheriting head motion")
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
	var miss_count: int = effects.misses.size()
	_check(miss_count > 0 and effects.misses.back()["node"].text == "MISS", "A native evasion must visibly say MISS without an impact")
	effects.update_live_projectiles([{"id": "live-miss", "progress": 0.7, "missed": true}])
	effects.resolve_live({"projectile_id": "live-miss", "outcome": "miss", "target": {"x": 80, "y": 170}}, enemy)
	_check(effects.misses.size() == miss_count and effects.shots.size() == 1, "Miss snapshots and native outcomes must produce one cue and preserve a still-live passing projectile")
	effects._process(0.1)
	_check(Vector3(effects.shots.back()["end"]).distance_to(enemy.room_target(0)) > 0.4, "Native miss trajectory must survive endpoint updates")
	_check(effects.impacts.is_empty() and enemy.shield_flash > 0.0, "A miss must not add a hull impact or reset an existing shield state")
	effects.simulation_paused = true
	var miss_age: float = effects.misses.back()["time"]
	effects._process(0.5)
	_check(effects.misses.back()["time"] == miss_age, "Native pause must freeze evasion feedback")
	effects.simulation_paused = false
	effects.update_live_projectiles([])
	effects._process(0.3)
	effects.update_live_projectiles([])
	effects._process(1.1)
	_check(effects.misses.is_empty(), "Evasion feedback must clear after its short presentation lifetime")
	effects.resolve_live({"projectile_id": "already-dead-miss", "outcome": "miss", "target": {"x": 80, "y": 170}}, enemy)
	_check(effects.misses.size() == 1 and effects.impacts.is_empty(), "Native misses that vanish between snapshots must still display feedback without invented damage")
	effects.resolve_live({"projectile_id": "actual-hull", "outcome": "hull", "target": {"x": 80, "y": 170}}, enemy)
	effects.resolve_live({"projectile_id": "actual-shield", "outcome": "shield", "target": {"x": 80, "y": 170}}, enemy)
	_check(effects.impacts[-2]["outcome"] == "hull" and effects.impacts[-1]["outcome"] == "shield", "Hull and shield feedback must retain distinct actual native outcomes")
	_check(effects.impacts[-2]["node"].material_override.albedo_color != effects.impacts[-1]["node"].material_override.albedo_color, "Hull and shield flashes must use visibly different colors")
	effects._process(1.1)
	# A projectile can fire, miss, and die between native snapshots. Its real
	# outcome must end the unseen flight immediately, even while paused.
	effects.simulation_paused = true
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "gap-miss"}, player, enemy)
	effects.resolve_live({"projectile_id": "gap-miss", "outcome": "miss", "target": {"x": 80, "y": 170}}, enemy)
	effects.update_live_projectiles([])
	_check(effects.shots.is_empty() and effects.misses.size() == 1 and effects.impacts.is_empty(), "Native missed fire absent from its first snapshot must clear immediately with one MISS cue and no invented hit")
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "fresh-live-miss"}, player, enemy)
	effects.resolve_live({"projectile_id": "fresh-live-miss", "outcome": "miss", "target": {"x": 80, "y": 170}}, enemy)
	effects.update_live_projectiles([{"id": "fresh-live-miss", "progress": 0.75, "missed": true}])
	_check(effects.shots.size() == 1 and effects.shots[0]["projectile_id"] == "fresh-live-miss", "A native miss before its first snapshot must preserve the projectile when the same snapshot still reports it alive")
	effects.update_live_projectiles([])
	effects.simulation_paused = false
	effects._process(1.1)
	# Legacy radial-distance snapshots used to fall after a miss passed its
	# target. Both those snapshots and reordered modern ones must stay forward.
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "forward-miss",
		"target": {"x": 80, "y": 170}}, player, enemy)
	effects.update_live_projectiles([{"id": "forward-miss", "progress": 0.76}])
	effects._process(0.1)
	var forward_miss: Dictionary = effects.shots.back()
	var forward_node: MeshInstance3D = forward_miss["node"]
	var before_miss := forward_node.global_position
	effects.resolve_live({"projectile_id": "forward-miss", "outcome": "miss", "target": {"x": 80, "y": 170}}, enemy)
	effects._process(0.0)
	_check(forward_node.global_position.is_equal_approx(before_miss), "A late native miss decision must keep the projectile at its already presented point")
	effects.update_live_projectiles([{"id": "forward-miss", "progress": 0.94, "missed": true}])
	effects._process(0.1)
	var passed_position := forward_node.global_position
	var forward_direction: Vector3 = (Vector3(forward_miss["target_end"]) - Vector3(forward_miss["start"])).normalized()
	for backwards_progress in [0.81, 0.63, 0.5]:
		effects.update_live_projectiles([{"id": "forward-miss", "progress": backwards_progress, "missed": true}])
		effects._process(0.1)
		_check(forward_node.global_position.is_equal_approx(passed_position), "Legacy or reordered progress must never boomerang an already presented native miss")
	var duplicate_count: int = effects.shots.size()
	effects.spawn_shot({"kind": "laser", "outcome": "pending", "projectile_id": "forward-miss"}, player, enemy)
	_check(effects.shots.size() == duplicate_count and effects.shots.back()["node"] == forward_node, "Duplicate native fire must retain one original projectile without resetting its progress")
	effects.update_live_projectiles([{"id": "forward-miss", "progress": 1.3, "missed": true}])
	effects._process(0.1)
	_check((forward_node.global_position - passed_position).dot(forward_direction) > 0.2 and forward_miss["live_progress"] > 1.0, "A missed native projectile must continue forward beyond the target instead of stopping or returning")
	var before_pause := forward_node.global_position
	effects.simulation_paused = true
	effects.update_live_projectiles([{"id": "forward-miss", "progress": 1.4, "missed": true}])
	effects._process(0.5)
	_check(forward_node.global_position.is_equal_approx(before_pause), "Paused passing misses must remain frozen")
	var effects_before_absence: int = effects.impacts.size()
	effects.update_live_projectiles([])
	_check(effects.shots.is_empty() and effects.impacts.size() == effects_before_absence, "Native absence must remove a passing miss immediately without fabricated collision feedback")
	effects.simulation_paused = false
	effects._process(1.1)
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
	effects.update_live_projectiles([])
	effects.simulation_paused = false
	effects._process(0.3)
	# A player-owned drone is physically modeled in the receiver's native space.
	# Attach a fire record to that exact muzzle before testing orbital motion and
	# independent pause versus encounter transforms.
	enemy._apply_drones([{"id": "88001", "name": "COMBAT_2", "kind": "combat", "is_space": true,
		"powered": true, "deployed": true, "x": 90, "y": 130, "angle": 35.0}])
	var actual_drone: Node3D = enemy.drone_nodes["88001"]
	var native_drone_event := {"kind": "laser", "outcome": "pending", "projectile_id": "drone-native",
		"drone_id": "88001", "origin_space": 1, "origin_point": drone_origin,
		"target_space": 1, "target": drone_target}
	var muzzle: Vector3 = actual_drone.muzzle_position("drone-native")
	effects.spawn_shot(native_drone_event, player, enemy)
	effects.update_live_projectiles([{"id": "drone-native", "progress": 0.25}])
	effects._process(0.1)
	var drone_shot: Dictionary = effects.shots.back()
	_check(Vector3(drone_shot["start"]).is_equal_approx(muzzle), "Native drone fire must originate at the visible muzzle in its current render space")
	_check(drone_shot["node"].mesh.get_aabb().size.z < 0.1, "Drone bullets must remain sized for their small native emitters")
	actual_drone.position += Vector3(0.2, 0, 0.1)
	effects._process(0.1)
	_check(Vector3(drone_shot["start"]).is_equal_approx(muzzle), "Later orbital drone movement must not move a bullet's original launch point")
	var launch_local: Vector3 = enemy.to_local(muzzle)
	var paused_progress: float = drone_shot["live_progress"]
	effects.simulation_paused = true
	enemy.position += Vector3(0.3, 0.1, -0.2)
	enemy.rotation += Vector3(0.15, 0.2, 0.08)
	enemy.scale = Vector3.ONE * 0.7
	effects._process(0.5)
	_check(Vector3(drone_shot["start"]).is_equal_approx(enemy.to_global(launch_local)), "Paused drone shots must follow encounter position, tilt and scale without advancing their native flight")
	_check(is_equal_approx(drone_shot["live_progress"], paused_progress), "Repositioning a paused encounter must preserve native projectile progress")
	_check(is_equal_approx(drone_shot["node"].global_basis.x.length(), enemy.global_basis.x.length()), "An orbiting drone's projectile size must follow its physical render space rather than its owner ship")
	effects.update_live_projectiles([])
	effects.simulation_paused = false
	var beam_event := native_drone_event.duplicate()
	beam_event.merge({"kind": "beam", "projectile_id": "drone-beam", "end_point": {"x": 200, "y": 130}}, true)
	effects.spawn_shot(beam_event, player, enemy)
	effects.update_live_projectiles([{"id": "drone-beam", "progress": 0.5, "beam_point": drone_target}])
	actual_drone.position += Vector3(0.1, 0, -0.05)
	effects._process(0.1)
	var drone_beam: Dictionary = effects.shots.back()
	_check(Vector3(drone_beam["start"]).is_equal_approx(actual_drone.muzzle_position("drone-beam")), "A continuing native drone beam must remain attached to its actual visible emitter")
	_check(drone_beam["node"].get_node_or_null("BeamCore") != null and drone_beam["node"].mesh is ImmediateMesh, "A native beam drone must render a sweep, never an invented laser bullet")
	var drone_beam_core: MeshInstance3D = drone_beam["node"].get_node("BeamCore")
	_check(drone_beam_core.global_position.is_equal_approx((drone_beam["start"] + enemy.to_global(enemy.pixel_point(drone_target))) * 0.5), "The native beam's exact live endpoint and muzzle must bound its visible geometry")
	effects.update_live_projectiles([{"id": "drone-beam", "progress": 1.0, "beam_point": drone_target}])
	effects._process(0.1)
	_check(effects.shots.size() == 1, "Native progress at one must not delete a still-present beam or invent its outcome")
	effects.update_live_projectiles([])
	var fallback_event := native_drone_event.duplicate()
	fallback_event.merge({"drone_id": "-1", "projectile_id": "negative-native"}, true)
	enemy.drone_nodes["-1"] = actual_drone
	effects.spawn_shot(fallback_event, player, enemy)
	_check(Vector3(effects.shots.back()["start"]).is_equal_approx(enemy.to_global(enemy.pixel_point(drone_origin, 0.3))), "An ambiguous negative native drone id must use its real native point at drone height")
	enemy.drone_nodes.erase("-1")
	effects.update_live_projectiles([{"id": "negative-native", "progress": 0.3}])
	effects.update_live_projectiles([])
	var first_bullet: MeshInstance3D = effects._projectile_visual("laser", Color.ORANGE, true)
	var second_bullet: MeshInstance3D = effects._projectile_visual("laser", Color.ORANGE, true)
	_check(first_bullet.mesh == second_bullet.mesh and first_bullet.get_child(0).mesh == second_bullet.get_child(0).mesh, "Repeated drone shots must reuse both core and trail geometry")
	first_bullet.free()
	second_bullet.free()
	# The Flagship uses native artillery slots, not the ship's ordinary weapon
	# list. Sparse slots after a phase change must not wrap onto a regular mount.
	enemy._apply_artillery([{"slot": 1, "name": "ARTILLERY_LASER", "kind": "laser", "powered": true,
		"mount": {"x": 150, "y": 110}, "charge_fraction": 0.4},
		{"slot": 3, "name": "ARTILLERY_BEAM", "kind": "beam", "powered": true,
		"mount": {"x": 280, "y": 130}, "charge_fraction": 0.8}])
	_check(enemy.artillery_nodes.has(1) and enemy.artillery_nodes.has(3) and not enemy.artillery_nodes.has(0), "Sparse native artillery identities must retain their own models")
	var artillery_origin: Vector3 = enemy.artillery_origin(3)
	effects.spawn_shot({"kind": "beam", "outcome": "pending", "projectile_id": "flagship-beam",
		"artillery_slot": 3, "weapon_slot": 0, "target_room": 0}, enemy, player)
	effects.update_live_projectiles([{"id": "flagship-beam", "progress": 0.5, "beam_point": drone_target}])
	effects._process(0.1)
	var artillery_beam: Dictionary = effects.shots.back()
	_check(Vector3(artillery_beam["start"]).is_equal_approx(artillery_origin) and not artillery_origin.is_equal_approx(enemy.weapon_origin(0)), "Flagship fire must originate at its exact native artillery slot instead of ordinary weapon zero")
	var artillery_core: MeshInstance3D = artillery_beam["node"].get_node("BeamCore")
	_check(artillery_core.global_position.is_equal_approx((artillery_origin + player.to_global(player.pixel_point(drone_target))) * 0.5), "Flagship artillery sweep must connect its actual barrel to the native live target point")
	effects.simulation_paused = true
	enemy.position += Vector3(0.2, 0.1, -0.15)
	enemy.rotation.y += 0.25
	effects._process(0.1)
	_check(Vector3(artillery_beam["start"]).is_equal_approx(enemy.artillery_origin(3)), "Artillery emitter must follow paused encounter transforms without switching weapon slots")
	effects.update_live_projectiles([])
	effects.simulation_paused = false
	enemy._apply_artillery([{"slot": 3, "name": "ARTILLERY_BEAM", "kind": "beam", "powered": true,
		"mount": {"x": 280, "y": 130}, "charge_fraction": 0.9}])
	_check(enemy.artillery_nodes.size() == 1 and enemy.artillery_nodes.has(3), "An absent artillery slot must be removed when the Flagship changes phase")
	print("COMBAT_TESTS ", "PASS" if failures == 0 else "FAIL: %d" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
