extends SceneTree

const ShipModel = preload("res://scripts/ship_model.gd")
const TargetLocks = preload("res://scripts/target_locks.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var encounter := Node3D.new()
	root.add_child(encounter)
	var player := ShipModel.new()
	encounter.add_child(player)
	player.build("__target_locks_fixture__", false)
	player.set_process(false)
	var enemy := ShipModel.new()
	encounter.add_child(enemy)
	enemy.build("__target_locks_fixture__", true)
	enemy.set_process(false)
	enemy.layout_data.x_offset = 2
	enemy.layout_data.y_offset = 1
	var renderer := TargetLocks.new()
	root.add_child(renderer)
	var laser := {"slot": 0, "kind": "laser", "target_ship": 1, "autofire": false,
		"targets": [{"x": 105, "y": 70}, {"x": 175, "y": 140}]}
	var beam := {"slot": 1, "kind": "beam", "beam_length": 100, "target_ship": 1, "autofire": true,
		"targets": [{"x": 245, "y": 140}, {"x": 105, "y": 70}]}
	var flak := {"slot": 2, "kind": "flak", "target_ship": 1, "target_radius": 30,
		"targets": [{"x": 175, "y": 70}]}
	var state := {"ready": true, "combat": true, "paused": true, "weapon_selected": -1,
		"targeting": {"active": false}, "player": {"weapons": [laser, beam, flak]},
		"enemy": {"rooms": [{"id": 0, "visible": false}], "weapons": [laser]}}
	var original := JSON.stringify(state)
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.size() == 3, "Native locks must persist after the armed cursor closes, including during pause")
	_check(JSON.stringify(state) == original, "Target lock presentation must never mutate the game snapshot")
	var local_target: Vector3 = enemy.pixel_point(laser.targets[0], TargetLocks.HEIGHT)
	_check(renderer.locks[0].end.is_equal_approx(local_target), "Native target conversion must remove layout offsets")
	_check(Vector2(local_target.x, local_target.z).is_equal_approx(enemy.room_bounds[0].get_center()), "The lock must remain centered on the native room")
	_check(renderer.locks[0].node.get_child_count() <= 2, "Charged weapon extra points must not invent reticles absent from the native aiming renderer")
	_check(renderer.locks[1].start.is_equal_approx(enemy.pixel_point(beam.targets[1], TargetLocks.HEIGHT))
		and renderer.locks[1].end.is_equal_approx(enemy.pixel_point(beam.targets[0], TargetLocks.HEIGHT)), "Beam direction must use native targets[1] to targets[0]")
	var radius_mesh: MeshInstance3D = renderer.locks[2].node.get_node("FlakRadius")
	_check(is_equal_approx(radius_mesh.mesh.top_radius, 30.0 * ShipModel.TILE / 35.0), "Flak circle must use the actual native spread radius")
	_check(renderer.locks[1].node.get_meta("autofire") and renderer.locks[1].node.get_node("WeaponSlot").modulate == TargetLocks.AUTOFIRE,
		"Autofire must use the native yellow cue")
	var retained_id: int = renderer.locks[0].node.get_instance_id()
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks[0].node.get_instance_id() == retained_id, "Identical snapshots must retain existing lock geometry")
	encounter.position = Vector3(1.7, 0.4, -1.2)
	encounter.rotation_degrees = Vector3(17, 39, -12)
	encounter.scale = Vector3(0.65, 1.2, 0.83)
	enemy.position = Vector3(0.23, 0.17, -0.48)
	enemy.rotation_degrees = Vector3(-8, -23, 14)
	renderer.refresh_transforms()
	_check(renderer.locks[0].node.to_global(renderer.locks[0].end).is_equal_approx(enemy.to_global(local_target)),
		"Locks must follow moving, rotated and nonuniformly scaled ships without waiting for a new snapshot")
	_check(renderer.locks[1].node.global_transform.is_equal_approx(enemy.global_transform), "Beam endpoint geometry must follow the same ship transform")
	enemy.hide()
	renderer.refresh_transforms()
	_check(not renderer.locks[0].node.visible, "Hidden ships must hide their locks immediately")
	enemy.show()
	renderer.refresh_transforms()
	_check(renderer.locks[0].node.visible, "Visible native locks must return with their ship")
	laser.targets = [{"x": 175, "y": 140}]
	laser.autofire = true
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks[0].node.get_instance_id() != retained_id and renderer.locks[0].node.get_meta("autofire"),
		"Native retargeting and autofire colour changes must replace stale geometry immediately")
	laser.targets = []
	renderer.apply_snapshot(state, player, enemy)
	_check(not renderer.locks.has(0) and renderer.locks.size() == 2, "Clearing one native target must remove only that weapon's lock")
	state.player.weapons = []
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "Enemy weapon intent must never create a lock on either ship")
	var self_bomb := {"slot": 0, "kind": "bomb", "target_ship": 0, "targets": [{"x": 35, "y": 35}]}
	state.player.weapons = [self_bomb]
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks[0].receiver == player, "A player-owned bomb must honor its actual friendly target ship")
	state.combat = false
	state.player.weapons = [self_bomb, beam]
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.size() == 1 and renderer.locks.has(0) and renderer.locks[0].receiver == player,
		"A native self-target bomb must retain its lock without an enemy, while enemy targets disappear")
	state.combat = true
	state.player.weapons = [self_bomb]
	self_bomb.target_ship = -1
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "Invalid native target ship IDs must clear previous locks")
	state.player.weapons = [beam]
	beam.targets = [{"x": 245, "y": 140}]
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "A partially placed real beam must not show a fabricated second endpoint")
	beam.beam_length = 1
	beam.targets = [{"x": 241, "y": 136}]
	renderer.apply_snapshot(state, player, enemy)
	_check(not renderer.locks[1].beam and renderer.locks[1].end.is_equal_approx(enemy.pixel_point({"x": 227.5, "y": 122.5}, TargetLocks.HEIGHT)),
		"Pinpoint beams must use the native tile center and a placed reticle")
	beam.targets = [{"x": NAN, "y": 140}]
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "Nonfinite native coordinates must not reach render geometry")
	beam.targets = [{"x": 245, "y": 140}]
	for gate in ["combat", "ready"]:
		state[gate] = false
		renderer.apply_snapshot(state, player, enemy)
		_check(renderer.locks.is_empty(), "An ended encounter or inactive game must remove every lock")
		state[gate] = true
	state.transition = true
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "Jump transition must remove old encounter locks")
	state.transition = false
	state.enemy.destroyed = true
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.is_empty(), "Native enemy destruction must remove its locks")
	state.enemy.destroyed = false
	renderer.apply_snapshot(state, player, enemy)
	_check(renderer.locks.size() == 1, "Current native target state must recreate a valid lock")
	enemy.queue_free()
	await process_frame
	renderer.refresh_transforms()
	_check(renderer.locks.is_empty(), "Freed receivers must remove locks without accessing their transforms")
	# Exercise the source-only fallback even when owned slot 1–4 art is present.
	var fallback := Node3D.new()
	root.add_child(fallback)
	renderer._make_reticle(fallback, Vector3.ZERO, 8, false)
	renderer._finish_lines(fallback)
	_check(fallback.get_node("LockLines").mesh.get_surface_count() == 1 and fallback.get_child_count() == 2,
		"Procedural reticles must batch all strokes into one surface and retain the weapon slot cue")
	fallback.queue_free()
	encounter.queue_free()
	renderer.queue_free()
	await process_frame
	if failures == 0 and OS.get_cmdline_user_args().has("--capture"):
		await _capture_fixture()
	print("TARGET_LOCK_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _capture_fixture() -> void:
	# Renderer-only oracle: no native process, game commands, input or save writes.
	root.size = Vector2i(1400, 900)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101923")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d4e7f2")
	environment.ambient_light_energy = 0.85
	world.environment = environment
	root.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.45
	camera.position = Vector3(0, 2.0, 1.35)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var enemy := ShipModel.new()
	root.add_child(enemy)
	enemy.build("__target_locks_fixture__", true)
	enemy.set_process(false)
	enemy.inspect_rooms = true
	var rooms: Array = []
	for id in range(6):
		rooms.append({"id": id, "visible": id != 2})
	enemy.apply_live({"rooms": rooms})
	var renderer := TargetLocks.new()
	root.add_child(renderer)
	var state := {"ready": true, "combat": true, "player": {"weapons": [
		{"slot": 0, "kind": "laser", "target_ship": 1, "targets": [{"x": 35, "y": 35}]},
		{"slot": 1, "kind": "laser", "autofire": true, "target_ship": 1, "targets": [{"x": 105, "y": 35}]},
		{"slot": 2, "kind": "flak", "target_ship": 1, "target_radius": 32, "targets": [{"x": 175, "y": 35}]},
		{"slot": 3, "kind": "beam", "beam_length": 140, "target_ship": 1, "targets": [{"x": 175, "y": 105}, {"x": 35, "y": 105}]}]},
		"enemy": {"rooms": rooms}}
	renderer.apply_snapshot(state, null, enemy)
	var title := _caption("NATIVE WEAPON TARGET LOCKS", Vector2(40, 32), 34)
	var footer := _caption("Red: single volley   /   Yellow: autofire   /   Circle: flak spread   /   Beam: actual sweep direction", Vector2(40, 837), 22)
	await _capture("target_locks_fixture.png")
	enemy.position = Vector3(0.12, 0.03, 0.05)
	enemy.rotation_degrees = Vector3(13, 31, -9)
	enemy.scale = Vector3(1.2, 0.8, 1.08)
	renderer.refresh_transforms()
	camera.size = 1.75
	title.text = "LOCKS FOLLOW THE MOVED AND SCALED SHIP"
	footer.text = "Room locks and both beam endpoints remain attached during pause. Sensor fog reveals no crew or system details."
	await _capture("target_locks_transformed_fixture.png")
	state.player.weapons = []
	renderer.apply_snapshot(state, null, enemy)
	title.text = "NATIVE TARGET CLEAR REMOVES ALL LOCKS"
	footer.text = "Weapon target lists are authoritative; cleared targets disappear immediately."
	await _capture("target_locks_cleared_fixture.png")


func _capture(filename: String) -> void:
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://local_game_data/" + filename)
	root.get_texture().get_image().save_png(path)
	print("TARGET_LOCK_CAPTURE ", path)


func _caption(text: String, point: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_override("font", UiAssets.font("body"))
	label.add_theme_font_size_override("font_size", size)
	label.modulate = Color("fff2c4")
	root.add_child(label)
	return label
