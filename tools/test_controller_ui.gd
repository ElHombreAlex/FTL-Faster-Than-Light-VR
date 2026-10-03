extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func rendered() -> void:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw


func pixel_world(panel: Node3D, pixel: Vector2) -> Vector3:
	return panel.to_global(Vector3((pixel.x / 1150.0 - .5) * .92,(.5 - pixel.y / 900.0) * .72,.012))


func run() -> void:
	_verify_bindings()
	_verify_native_fonts()
	var camera := Camera3D.new()
	camera.position = Vector3(0,0,3)
	camera.current = true
	root.add_child(camera)
	var panel: Node3D = load("res://scripts/controller_panel.gd").new()
	root.add_child(panel)
	var menu := [{"label":"JUMP","position":Vector2(-.22,.235)}, {"label":"SHIP","position":Vector2(.22,.235)}, {"label":"SHORTCUTS","position":Vector2(-.22,.155)}, {"label":"TACTICAL VIEW","position":Vector2(.22,.155)}, {"label":"CONTROLS / HELP","position":Vector2(-.22,.075)}, {"label":"RECENTER","position":Vector2(.22,.075)}]
	panel.set_navigation("NAVIGATION",menu,true)
	var revision: int = panel.content_revision
	panel.set_navigation("NAVIGATION",menu.duplicate(true),true)
	check(panel.content_revision == revision,"An unchanged controller page must not schedule another viewport render")
	check(panel.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,"The themed navigation panel must render on demand")
	await rendered()
	panel.viewport.get_texture().get_image().save_png("res://local_game_data/controller-navigation-theme.png")
	var player := {"system_status":[
		{"key":"shields","id":0,"allocated":3,"max_power":4,"damaged":1,"ionized":0,"powerable":true},
		{"key":"engines","id":1,"allocated":2,"max_power":5,"damaged":0,"ionized":0,"powerable":true},
		{"key":"weapons","id":3,"allocated":3,"max_power":4,"damaged":0,"ionized":0,"powerable":true},
		{"key":"oxygen","id":2,"allocated":1,"max_power":1,"damaged":0,"ionized":0,"powerable":true},
		{"key":"mind","id":14,"allocated":0,"max_power":3,"damaged":0,"ionized":2,"powerable":true},
		{"key":"doors","id":8,"allocated":0,"max_power":3,"damaged":0,"ionized":0,"powerable":false}],
		"reactor":{"available":7,"total":16,"used":9,"battery_available":0,"battery_total":0}}
	panel.set_power(player)
	check(panel.power_rows.size() == 5 and panel.selected_system().id == 0,"The power page must display installed powerable systems and preserve native system IDs")
	revision = panel.content_revision
	player.crew = [{"name":"Moving crew"}]
	panel.set_power(player)
	check(panel.content_revision == revision,"Unrelated crew movement must not redraw the system power page")
	panel.step_selection(-1)
	check(panel.selected_system().key == "mind","X must wrap to the previous installed powerable system")
	panel.step_selection(1)
	check(panel.selected_system().key == "shields","Y must wrap back to the next system")
	panel.select_system("weapons")
	check(panel.selected_system().allocated == 3 and panel.selected_system().max_power == 4,"Selected system power values must come from the native live schema")
	panel.select_system("missing")
	check(panel.selected_system().key == "weapons","A missing system must not replace the valid selection")
	panel.global_transform = Transform3D(Basis.from_euler(Vector3(-.5,.3,.1)).scaled(Vector3.ONE * .6),Vector3(.4,.9,-.7))
	var rect: Rect2 = panel.power_card_rect(4)
	var point := pixel_world(panel,rect.get_center())
	var hit: Dictionary = panel.ray_hit(point + panel.global_basis.z.normalized(),-panel.global_basis.z.normalized())
	check(hit.get("system_key","") == "mind" and hit.position.distance_to(point) < .0001,"Rotated and scaled power cards must be pointable without native frame pixels or physics collisions")
	hit = panel.ray_hit(panel.to_global(Vector3(0,.345,1)),-panel.global_basis.z.normalized())
	check(not hit.is_empty() and hit.system_key == "","Blank panel/header areas must block the world without changing selection")
	panel.visible = false
	check(panel.ray_hit(point + panel.global_basis.z.normalized(),-panel.global_basis.z.normalized()).is_empty(),"A hidden power page must not intercept the controller ray")
	panel.visible = true
	panel.global_transform = Transform3D.IDENTITY
	await rendered()
	var power_image: Image = panel.viewport.get_texture().get_image()
	power_image.save_png("res://local_game_data/controller-system-power-theme.png")
	# Changing power schedules exactly one real render and changes GPU pixels.
	var before: Color = power_image.get_pixel(276,217)
	player.system_status[0].allocated = 0
	revision = panel.content_revision
	panel.set_power(player)
	check(panel.content_revision == revision + 1,"A live allocation change must request one power-page render")
	await rendered()
	check(panel.viewport.get_texture().get_image().get_pixel(276,217) != before,"Native power changes must update the visible GPU power bars")
	# Native updates may reorder rows; retain stable key selection.
	player.system_status.reverse()
	panel.set_power(player)
	check(panel.selected_system().key == "weapons","Native row reordering must preserve the selected system")
	# Actual native QA: a Zoltan in Oxygen gives allocated=0, bonus=1,
	# effective=1. Battery is separate from allocated in GetEffectivePower.
	var source_player := {"system_status":[
		{"key":"oxygen","id":2,"allocated":0,"bonus_power":1,"battery_power":0,"effective_power":1,"max_power":1,"power_cap":1,"powerable":true},
		{"key":"weapons","id":3,"allocated":1,"bonus_power":1,"battery_power":2,"effective_power":4,"max_power":5,"damaged":1,"power_cap":4,"powerable":true},
		{"key":"engines","id":1,"allocated":1,"effective_power":1,"max_power":3,"power_cap":2,"ionized":true,"locked":true,"powerable":true},
		{"key":"hacking","id":15,"allocated":1,"effective_power":1,"max_power":2,"power_cap":2,"hacked":2,"powerable":true}],
		"reactor":{"available":7,"total":16,"used":9,"battery_available":0,"battery_total":2}}
	panel.set_power(source_player)
	panel.select_system("oxygen")
	await rendered()
	var source_image: Image = panel.viewport.get_texture().get_image()
	source_image.save_png("res://local_game_data/controller-system-power-sources.png")
	check(source_image.get_pixel(269,213).to_html(false) == "fffa5a","A zero-reactor Oxygen system powered by a Zoltan must render a native yellow bonus pip")
	check(panel.selected_system().allocated == 0 and panel.selected_system().bonus_power == 1 and panel.selected_system().effective_power == 1,"Drawing effective power must preserve raw native selected-row power fields")
	check(panel.reactor.available == 7 and panel.reactor.used == 9,"Zoltan and battery display must not debit, recompute or double count native reactor availability")
	check(source_image.get_pixel(269,319).to_html(false) == "7fff74","Reactor-supplied system power must retain its green pip")
	check(source_image.get_pixel(294,319).to_html(false) == "7fff74" and source_image.get_pixel(282,318).to_html(false) == "e66e1e","Battery pips must have the native green inner pip and distinct orange outline")
	check(source_image.get_pixel(344,319).to_html(false) == "fffa5a","Bonus power must follow allocated and battery pips, without counting battery twice")
	check(source_image.get_pixel(369,319).to_html(false) == "ed6260","Damaged capacity must remain red after powered-source pips")
	check(source_image.get_pixel(719,213).to_html(false) == "85e7ed","Ion-locked allocated power must use the native cyan status color")
	check(source_image.get_pixel(757,212).to_html(false) == "85e7ed","Power capped cells must retain a cyan outline rather than appear available")
	check(source_image.get_pixel(719,319).to_html(false) == "cf46fd","Hacked allocated power must use the native purple status color")
	# The effective-power numerator is authoritative even when raw allocated is 0.
	# Compare its rendered numeric region against the otherwise identical 0/1 case.
	var powered_count: Image = source_image.get_region(Rect2i(537,206,50,15))
	source_player.system_status[0].effective_power = 0
	source_player.system_status[0].bonus_power = 0
	panel.set_power(source_player)
	await rendered()
	check(powered_count.get_data() != panel.viewport.get_texture().get_image().get_region(Rect2i(537,206,50,15)).get_data(),"The visible power count must show native effective 1/1 instead of raw allocated 0/1")
	var wheel: Node3D = load("res://scripts/shortcut_wheel.gd").new()
	root.add_child(wheel)
	wheel.set_entries([{"label":"BURST LASER II","enabled":true},{"label":"ARTEMIS","enabled":true},{"label":"EMPTY","enabled":false},{"label":"EMPTY","enabled":false},{"label":"COMBAT DRONE","enabled":true},{"label":"BEAM DRONE","enabled":true}],"WEAPONS\nDRONES")
	wheel.choose(Vector2(0,1))
	revision = wheel.content_revision
	wheel.choose(Vector2(0,.9))
	check(wheel.selected == 0 and wheel.content_revision == revision,"A stable wheel sector must not rerender every joystick sample")
	wheel.choose(Vector2(1,0))
	check(wheel.selected == 2,"The themed wheel must retain clockwise 1-8 native slot ordering")
	wheel.choose(Vector2.ZERO)
	check(wheel.selected == -1,"The wheel center must continue to cancel")
	wheel.choose(Vector2(0,1))
	wheel.visible = true
	await rendered()
	wheel.viewport.get_texture().get_image().save_png("res://local_game_data/controller-action-wheel-theme.png")
	var help: Node3D = load("res://scripts/controller_help.gd").new()
	root.add_child(help)
	await rendered()
	help.viewport.get_texture().get_image().save_png("res://local_game_data/controller-help-theme.png")
	check(help.canvas.font == load("res://scripts/ftl_ui_assets.gd").font("body"),"Help callouts must use the actual vanilla UI font")
	var keyboard: Node3D = load("res://scripts/rename_keyboard.gd").new()
	root.add_child(keyboard)
	keyboard.set_entry({"active":true,"id":"crew1","kind":"CREW","text":"Elisabeth","cursor":9})
	check(keyboard.title.get_theme_font("font") == load("res://scripts/ftl_ui_assets.gd").font("header") and keyboard.value_label.get_theme_font("font") == load("res://scripts/ftl_ui_assets.gd").font("body"),"Rename keyboard and name entry must use actual native fonts")
	var q_point := Vector3((74.0 / 1000.0 - .5) * .86,(.5 - 188.0 / 454.0) * .39,0)
	var q_hit: Dictionary = keyboard.ray_hit(q_point + Vector3(0,0,1),Vector3(0,0,-1))
	check(q_hit.get("text","") == "Q" and keyboard.activate(q_hit).get("op","") == "insert","Restyling the keyboard must preserve QWERTY key picking and scoped text operations")
	await rendered()
	keyboard.viewport.get_texture().get_image().save_png("res://local_game_data/controller-keyboard-theme.png")
	var hull_bar: Node3D = load("res://scripts/enemy_hull_bar.gd").new()
	root.add_child(hull_bar)
	hull_bar.build()
	hull_bar.set_state({"hull":30,"hull_max":30,"name":"REBEL FIGHTER"})
	await rendered()
	var full_hull: Image = hull_bar.viewport.get_texture().get_image()
	check(full_hull.get_pixel(690,74).g > .9 and full_hull.get_pixel(690,74).r < .6,"Full enemy hull must use the actual vanilla segmented-mask fill")
	hull_bar.set_state({"hull":18,"hull_max":30,"name":"REBEL FIGHTER"})
	await rendered()
	var partial_hull: Image = hull_bar.viewport.get_texture().get_image()
	partial_hull.save_png("res://local_game_data/controller-enemy-hull-theme.png")
	check(partial_hull.get_pixel(690,74).g < .5 and partial_hull.get_pixel(120,74).g > .9,"Native enemy hull changes must shorten the visible health fill and preserve remaining hull cells")
	check(partial_hull.get_pixel(400,8).a == 0,"The enemy hull display must retain transparent space around the native contour without a generic banner")
	check(load("res://scripts/ftl_ui_assets.gd").texture("img/statusUI/top_hull.png") != null,"The hull contour must come from owner-local vanilla art")
	hull_bar.set_state({})
	check(not hull_bar.visible,"Enemy hull display must disappear when native enemy state is absent")
	await _verify_world_font_render()
	panel.queue_free()
	wheel.queue_free()
	help.queue_free()
	keyboard.queue_free()
	hull_bar.queue_free()
	await process_frame
	print("CONTROLLER_UI_TESTS ","PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func _verify_bindings() -> void:
	var path := "res://openxr_action_map.tres"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--action-map="): path = argument.trim_prefix("--action-map=")
	var map: OpenXRActionMap = load(path)
	check(map != null,"The controller action map must parse as an OpenXRActionMap")
	if map == null: return
	var profile: OpenXRInteractionProfile = map.find_interaction_profile("/interaction_profiles/valve/frame_controller_valve")
	check(profile != null,"The explicit Steam Frame interaction profile must exist")
	if profile == null: return
	var paths: Dictionary = {}
	for binding in profile.get_bindings():
		var name: String = binding.get_action().resource_name
		if not paths.has(name): paths[name] = []
		paths[name].append(binding.get_binding_path())
	var required := {
		"tactical_button":"/user/hand/left/input/dpad_down/click",
		"power_remove":"/user/hand/left/input/bumper/click",
		"power_previous":"/user/hand/right/input/x/click",
		"power_next":"/user/hand/right/input/y/click",
		"page_left":"/user/hand/left/input/dpad_left/click",
		"page_right":"/user/hand/left/input/dpad_right/click",
		"wheel_button":"/user/hand/right/input/bumper/click",
	}
	var actions: Dictionary = {}
	for action in map.get_action_set(0).get_actions(): actions[action.resource_name] = action
	for name in required:
		check(paths.get(name,[]) == [required[name]],"Frame %s must use the actual observed hardware button path" % name)
		check(actions.has(name) and actions[name].action_type == OpenXRAction.OPENXR_ACTION_BOOL,"Frame %s must be a boolean action in the active action set" % name)
		if not actions.has(name): continue
		var hand: String = "/user/hand/right" if name in ["power_previous","power_next","wheel_button"] else "/user/hand/left"
		check(hand in actions[name].toplevel_paths,"Frame %s must include its actual hardware hand" % name)
	check(paths.get("ax_button",[]) == ["/user/hand/right/input/a/click"],"Frame Dpad Down must not alias A/X and trigger both tactical and pause")
	check("/user/hand/left/input/view/click" in paths.get("menu_button",[]),"Left View must retain pause")
	check("/user/hand/left/input/dpad_up/click" in paths.get("by_button",[]),"Dpad Up must retain shortcuts")
	# The installed vendor Frame profile declares X/Y on the RIGHT controller.
	# Reject accidental Touch-controller assumptions (left X/Y) in this profile.
	for bound_paths in paths.values():
		check(not "/user/hand/left/input/x/click" in bound_paths and not "/user/hand/left/input/y/click" in bound_paths,"Frame X/Y must not be bound to nonexistent left-hand buttons")


func _verify_native_fonts() -> void:
	var assets = load("res://scripts/ftl_ui_assets.gd")
	for role in ["body","header","bold"]:
		var native: Font = assets.font(role)
		check(native is FontFile and native != ThemeDB.fallback_font,"The %s UI font must load the actual owner-local FTL atlas without editor import" % role)
		if native is FontFile and native != ThemeDB.fallback_font:
			check(native.has_char(65) and native.has_char(233),"Native UI font must retain Western glyphs and accented crew names")
			check(native.fixed_size > 0 and native.get_string_size("FTL",HORIZONTAL_ALIGNMENT_LEFT,-1,32).x > 0,"Native bitmap font must expose its original metrics and scalable advances")
			check(assets.font(role) == native,"Native UI font instances must be cached rather than decoded on every label")
	check(assets.load_font("res://local_game_data/fonts/missing.font") == null,"Missing local fonts must fall back without attempting system installation")
	# Compare the runtime A glyph against the original SIL byte metrics/atlas.
	var original := FileAccess.get_file_as_bytes(assets.data_path().path_join("fonts/JustinFont10.font"))
	var body: FontFile = assets.font("body")
	var info: int = assets._be32(original,8)
	var height := int(original[5])
	for i in range(assets._be16(original,12)):
		var offset: int = info + i * 16
		if assets._be32(original,offset) != 65: continue
		var expected_advance: float = original[offset + 8] + assets._signed(assets._be16(original,offset + 12),16) / 256.0 + assets._signed(assets._be16(original,offset + 14),16) / 256.0
		check(is_equal_approx(body.get_glyph_advance(0,height,65).x,expected_advance),"Native font advances must preserve original fractional pre/post bearings")
		check(body.get_glyph_offset(0,Vector2i(height,0),65).y + 2 == -assets._signed(original[offset + 10],8),"Native font baseline must retain original glyph ascent after transparent atlas padding")
		var tex: int = assets._be32(original,16)
		var pixel_offset: int = assets._be32(original,tex + 16)
		var width: int = assets._be16(original,tex + 8)
		var atlas := body.get_texture_image(0,Vector2i(height,0),0)
		var original_x: int = assets._be16(original,offset + 4)
		var original_y: int = assets._be16(original,offset + 6)
		var uv: Rect2 = body.get_glyph_uv_rect(0,Vector2i(height,0),65)
		var gx := int(uv.position.x) + 2
		var gy := int(uv.position.y) + 2
		for y in range(original[offset + 9]):
			for x in range(original[offset + 8]):
				check(roundi(atlas.get_pixel(gx + x,gy + y).a * 255) == original[tex + pixel_offset + (original_y + y) * width + original_x + x],"Native font atlas pixels must match the owned source, not a replacement alphabet")
		break
	var malformed := FileAccess.open("res://local_game_data/fonts/test-invalid.font",FileAccess.WRITE)
	malformed.store_buffer(original.slice(0,24))
	malformed.close()
	check(assets.load_font("res://local_game_data/fonts/test-invalid.font") == null,"Truncated native atlas/index data must fail cleanly")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://local_game_data/fonts/test-invalid.font"))


func _verify_world_font_render() -> void:
	var assets = load("res://scripts/ftl_ui_assets.gd")
	var preview := SubViewport.new()
	preview.size = Vector2i(640,240)
	preview.transparent_bg = true
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(preview)
	var camera := Camera3D.new()
	camera.position.z = 2
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.current = true
	preview.add_child(camera)
	var labels: Array[Label3D] = []
	for i in range(2):
		var label := Label3D.new()
		label.font = assets.font("header" if i == 0 else "body")
		label.text = "FTL HULL" if i == 0 else "Elisabeth / SHIELDS"
		label.font_size = 48
		label.pixel_size = .012
		label.outline_size = 0
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.position.y = .25 if i == 0 else -.25
		preview.add_child(label)
		labels.append(label)
	await rendered()
	var image := preview.get_texture().get_image()
	image.save_png("res://local_game_data/controller-world-native-fonts.png")
	for half in range(2):
		var opaque := 0
		for y in range(half * 120,(half + 1) * 120):
			for x in range(640):
				if image.get_pixel(x,y).a > .5: opaque += 1
		check(opaque > 50,"Native %s FontFile must render visible Label3D glyphs with zero outline" % ("header" if half == 0 else "body"))
	# A raw tight atlas rendered broad letters while dropping every 2px glyph
	# I/i/l in Label3D. Isolate those letters so the broad glyphs cannot mask it.
	labels[0].visible = false
	labels[1].text = "Iil"
	preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	await rendered()
	image = preview.get_texture().get_image()
	image.save_png("res://local_game_data/controller-world-narrow-glyphs.png")
	var narrow_pixels := 0
	for y in range(240):
		for x in range(640):
			if image.get_pixel(x,y).a > .5: narrow_pixels += 1
	check(narrow_pixels > 50,"Original narrow I/i/l glyphs must remain visible in nearest-filtered Label3D via padded UV quads")
	preview.queue_free()
