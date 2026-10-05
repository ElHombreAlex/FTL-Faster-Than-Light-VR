extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := load("res://tools/input_harness.gd").new() as Node3D
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = "right_hand"
	tracker.set_pose("aim", Transform3D(Basis.IDENTITY, Vector3(0.1,1.2,1)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	scene._resolve_controller_pose(scene.right_hand)
	check(scene.right_hand.pose == "aim" and scene.right_hand.get_is_active(), "Right hand must use the active aim tracker pose")
	var initial_ship_pose: Transform3D = scene.player_ship.transform
	scene.player_ship.rotation.y = PI / 2
	scene._sync_jump_heading()
	check(scene.space_environment.travel_direction.is_equal_approx(Vector3.FORWARD), "Jump streaks must follow the ship's transformed bow rather than the headset")
	scene.player_ship.transform = initial_ship_pose
	scene._sync_jump_heading()
	scene._update_pointer()
	check(scene.right_laser.visible and scene.right_laser.mesh is CylinderMesh, "Tracked hand must draw a stereo-visible ray")
	check(scene.right_laser.material_override.no_depth_test, "Ray must remain visible over the native menu")
	check(scene.right_laser.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and scene.right_laser.material_override.render_priority == 127,"Pointer must render after transparent HUD surfaces")
	check(is_equal_approx(scene.right_laser.mesh.height,1.0),"Pointer length must use node scaling, without regenerating its mesh every frame")
	tracker.set_input("trigger",0.8)
	check(scene._pressed(scene.right_hand,"trigger"), "Analog trigger must work without trigger_click")
	tracker.invalidate_pose("aim")
	tracker.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	scene._resolve_controller_pose(scene.right_hand)
	check(scene.right_hand.pose == "default", "Missing aim tracking must fall back to default")
	scene._update_input_diagnostics(1.1)
	scene.hud_state = {"ready":true,"ui_mode":"game","navigation":{"jump":true,"ship":true,"store":false}}
	scene.xr_active = true
	scene._refresh_navigation()
	var names := []
	for button in scene.nav_buttons:
		if button.visible: names.append(button.get_meta("action"))
		else: check(button.collision_layer == 0,"Hidden navigation buttons must not intercept rays")
	check("jump" in names and "store" not in names,"Navigation must reflect live availability")
	scene.hud_state.map_open = true
	scene._refresh_navigation()
	check(scene.map_surface.visible and scene.map_surface.get_parent() == scene,"Actual jump map must float in the world above the ship")
	check(scene.map_surface.global_position.y >= scene.player_ship.global_position.y + 0.65,"Jump map must have comfortable clearance above the ship")
	var pilot_id := -1
	for id in scene.player_ship.room_nodes:
		if scene.player_ship.room_nodes[id].get_meta("system_role", "") == "pilot": pilot_id = int(id)
	check(pilot_id >= 0,"Owned Kestrel layout must provide its actual piloting room")
	if pilot_id >= 0:
		var pilot_point: Vector3 = scene.player_ship.to_global(scene.player_ship.room_points[pilot_id])
		var bow: Vector3 = scene.player_ship.global_basis.x.normalized()
		var projected: Vector3 = scene.map_surface.global_position - pilot_point
		check(projected.dot(bow) > 0.20 and projected.y > 0.60,"Jump map must project above and ahead of the pilot instead of the ship center")
		var original_table: Transform3D = scene.tabletop_root.transform
		scene.tabletop_root.rotation.y = PI * 0.5
		scene.tabletop_root.scale *= 1.8
		scene._position_world_panels()
		pilot_point = scene.player_ship.to_global(scene.player_ship.room_points[pilot_id])
		bow = scene.player_ship.global_basis.x.normalized()
		projected = scene.map_surface.global_position - pilot_point
		check(projected.dot(bow) > 0.20 and projected.y > 0.60 and projected.length() < 0.70,"Pilot projection must follow ship rotation while keeping world-metre clearance at different table scales")
		var saved_vertical: int = int(scene.player_ship.layout_data.get("vertical",0))
		scene.player_ship.layout_data.vertical = 1
		scene._update_ship_positions()
		scene._position_world_panels()
		pilot_point = scene.player_ship.to_global(scene.player_ship.room_points[pilot_id])
		projected = scene.map_surface.global_position - pilot_point
		check(projected.dot(-scene.player_ship.global_basis.z.normalized()) > 0.20,"Vertical ship layouts must project ahead of their actual bow")
		scene.player_ship.layout_data.vertical = saved_vertical
		scene._update_ship_positions()
		scene.tabletop_root.transform = original_table
		# Read the actual room roles, not the extracted blueprint's first pilot.
		var alternate: int = int(scene.player_ship.room_nodes.keys().back())
		if alternate != pilot_id:
			scene.player_ship.room_nodes[pilot_id].set_meta("system_role", "")
			var saved_role: String = scene.player_ship.room_nodes[alternate].get_meta("system_role", "")
			scene.player_ship.room_nodes[alternate].set_meta("system_role", "pilot")
			scene._position_world_panels()
			pilot_point = scene.player_ship.to_global(scene.player_ship.room_points[alternate])
			check(Vector2(scene.map_surface.global_position.x-pilot_point.x,scene.map_surface.global_position.z-pilot_point.z).length() < 0.25,"A different piloting room must move the projected map anchor with it")
			scene.player_ship.room_nodes[alternate].set_meta("system_role", saved_role)
			scene.player_ship.room_nodes[pilot_id].set_meta("system_role", "pilot")
		scene._position_world_panels()
	check(is_equal_approx(scene.enemy_hull_bar.global_position.y-scene.enemy_ship.global_position.y,0.52),"Enemy hull bar must sit slightly lower while retaining clearance over the ship")
	scene.hud_state.map_open = false
	scene.hud_state.tactical = true
	scene._refresh_navigation()
	check(scene.nav_buttons[0].get_meta("action") == "tactical","Tactical view must close with its own toggle, not Escape")
	scene.hud_state.map_open = true
	scene.hud_state.tactical = false
	scene._refresh_navigation()
	var image := Image.create(1280,720,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	scene.map_surface.canvas.frame_image = image
	scene.nav_panel.visible = true
	var pixel: Variant = scene.map_surface.ray_pixel(scene.map_surface.to_global(Vector3(0,0,1)), -scene.map_surface.global_basis.z)
	check(pixel == Vector2i(715,375),"Cropped map pointer must map to the native game's original coordinates")
	scene._select_from_ray(scene.map_surface.to_global(Vector3(0,0,1)), -scene.map_surface.global_basis.z)
	scene._release_pointer(scene.map_surface.to_global(Vector3(0,0,1)), -scene.map_surface.global_basis.z)
	check(scene.commands.size() == 2 and scene.commands[0].data.phase == "down" and scene.commands[1].data.phase == "up","Map selection must dispatch a full native mouse click")
	scene.nav_panel.visible = false
	check(scene.map_surface.ray_pixel(scene.map_surface.to_global(Vector3(0,0,1)), -scene.map_surface.global_basis.z) != null,"World jump map must stay usable when hand tracking is hidden")
	var map: OpenXRActionMap = load("res://openxr_action_map.tres")
	check(map.find_interaction_profile("/interaction_profiles/valve/frame_controller_valve") != null,"Explicit Frame profile must ship with the client")
	var frame_bindings := map.find_interaction_profile("/interaction_profiles/valve/frame_controller_valve").get_bindings()
	var menu_paths := []
	for binding in frame_bindings:
		if binding.action.resource_name == "menu_button": menu_paths.append(binding.binding_path)
	check("/user/hand/right/input/menu/click" in menu_paths and "/user/hand/left/input/view/click" in menu_paths,"Frame Pause and View must use the vendor-declared right Menu and left View paths")
	var left_tracker := XRControllerTracker.new()
	left_tracker.type = XRServer.TRACKER_CONTROLLER
	left_tracker.name = "left_hand"
	left_tracker.set_pose("aim",Transform3D(Basis.IDENTITY,Vector3(-0.3,1.2,0.5)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(left_tracker)
	scene._resolve_controller_pose(scene.left_hand)
	scene.hud_state = {"ready":true,"ui_mode":"game"}
	scene.nav_page = "navigation"
	scene._refresh_navigation()
	scene._face_navigation_to_headset()
	var before_view_count: int = scene.commands.size()
	left_tracker.set_input("menu_button",true)
	scene._update_pause_panel_buttons()
	check(scene.hand_screen_hidden and not scene.nav_panel.visible and scene.commands.size() == before_view_count,"Left View must hide the hand screen without issuing a native pause/menu action")
	for button in scene.nav_buttons:
		check(button.collision_layer == 0,"A hidden hand screen must not leave invisible navigation colliders")
	scene._face_navigation_to_headset()
	scene._refresh_navigation()
	scene._update_pause_panel_buttons()
	check(scene.hand_screen_hidden and not scene.nav_panel.visible,"Held View and subsequent state/pose refresh must not show the hand screen again")
	left_tracker.set_input("menu_button",false)
	scene._update_pause_panel_buttons()
	left_tracker.set_input("menu_button",true)
	scene._update_pause_panel_buttons()
	check(not scene.hand_screen_hidden and scene.nav_panel.visible,"Pressing left View again must restore the same hand screen")
	left_tracker.set_input("menu_button",false)
	scene._update_pause_panel_buttons()
	tracker.set_input("menu_button",true)
	scene._update_pause_panel_buttons()
	check(scene.commands.size() == before_view_count+1 and scene.commands.back().action == "key" and scene.commands.back().data.key == 32 and scene.nav_panel.visible,"Right Pause must send native Space without hiding the hand screen")
	scene._update_pause_panel_buttons()
	check(scene.commands.size() == before_view_count+1,"Holding right Pause must toggle the native pause once")
	tracker.set_input("menu_button",false)
	scene._update_pause_panel_buttons()
	scene.nav_panel.visible = false
	scene.hud_state = {"ready":true,"ui_mode":"game"}
	scene._sync_hud_layout()
	scene._position_hud(0.0, true)
	check(is_equal_approx(scene.nav_panel.scale.x, 0.6) and scene.hud_surface.get_parent()==scene and scene.hud_surface.source_rect==scene.GAMEPLAY_HUD_RECT,"Gameplay HUD must retain native upper/crew pixels, exclude the bottom strip and use independent world placement")
	check(scene.hud_surface.render_order == 100 and scene.panel_theme.get_child(1).material_override.render_priority > scene.pause_label.render_priority and scene.tracking_label.render_priority < 120,"Hand screen must render over all HUD layers, including pause and modifier labels")
	var hud_mode_state: Dictionary = scene.hud_state.duplicate(true)
	scene.hud_state = {"ready":true,"ui_mode":"menu","panel_open":true}
	scene._sync_hud_layout()
	check(scene.gameplay_hud and scene.hud_surface.source_rect == scene.GAMEPLAY_HUD_RECT,"An in-run world window must not promote the headset HUD into a second full menu")
	scene.hud_state = {"ready":false,"ui_mode":"menu","panel_open":true}
	scene._sync_hud_layout()
	check(not scene.gameplay_hud and scene.hud_surface.source_rect == Rect2(0,0,1280,720),"Initial and hangar menus must keep their full headset display")
	scene.hud_state = hud_mode_state
	scene._sync_hud_layout()
	check(scene.help_label.get_script().resource_path.ends_with("controller_help.gd"),"Help must use a controller infographic instead of plain text")
	check(scene.hover_marker.mesh.radius <= 0.003 and scene.right_laser.mesh.top_radius <= 0.001,"Pointer endpoint must support precise native UI selection")
	scene.wheel.global_position = scene.camera.get_camera_transform().origin + Vector3(0.3,-0.5,-0.4)
	scene._face_front(scene.wheel)
	var to_head: Vector3 = (scene.camera.get_camera_transform().origin-scene.wheel.global_position).normalized()
	check(scene.wheel.global_basis.z.dot(to_head) > 0.999 and scene.wheel.global_basis.z.y > 0,"Wheel face must tilt up toward the real viewer rather than the ground")
	scene.hud_state = {"ready":true,"ui_mode":"game","navigation":{"jump":true},"player":{"weapons":[{"slot":0,"name":"LASER_BURST_1"}],"systems":{"shields":true}},"drone_slots":1}
	scene.nav_page = "navigation"
	scene._refresh_navigation()
	check(scene._navigation_entries().has(["SYSTEM POWER", "page:power"]),"System Power must have a direct Navigation entry")
	scene._cycle_hand_page(1)
	check(scene.nav_page == "tactical" and scene.commands.back().data.screen == "tactical","Dpad right must cycle into tactical")
	scene.hud_state.tactical = true
	scene._cycle_hand_page(1)
	check(scene.pending_page == "shortcuts" and scene.commands.back().data.screen == "tactical","Changing screen must first close the native tactical view")
	scene.hud_state.tactical = false
	scene.wheel_category = 2
	scene.wheel_was_down = false
	tracker.set_input("wheel_button", true)
	scene._update_wheel()
	check(scene.wheel_category == 0 and scene.wheel.heading == "WEAPONS\nDRONES", "Each new wheel hold must return to equipment rather than retaining a system category")
	scene.wheel_category = 1
	scene._update_wheel()
	check(scene.wheel_category == 1, "A held wheel must retain a manually chosen category")
	tracker.set_input("wheel_button", false)
	scene._update_wheel()
	check(scene.wheel_category == 0, "Closing the wheel must restore its equipment default")
	scene._refresh_wheel()
	check(scene.wheel.entries[0].enabled and not scene.wheel.entries[1].enabled and scene.wheel.entries[4].enabled,"Wheel must show only equipped weapon/drone slots as available")
	scene.wheel.choose(Vector2(0,1))
	check(scene.wheel.selected == 0,"Joystick up must select slot 1")
	scene.wheel.choose(Vector2.ZERO)
	check(scene.wheel.selected == -1,"Wheel center must cancel")
	scene.hud_state.event_open = true
	scene.hud_state.dialog = {"id":"test","choices":[{"index":0,"enabled":true}]}
	scene.wheel_dialog_id = "test"
	scene._refresh_wheel()
	scene.wheel.choose(Vector2(0,1))
	scene._commit_wheel()
	var command_count: int = scene.commands.size()
	scene._commit_wheel()
	check(scene.commands.back().action == "event_choice" and scene.commands.size() == command_count,"Event wheel must commit once")
	var saved_state: Dictionary = scene.hud_state.duplicate(true)
	scene.hud_state = {"ready":true,"ui_mode":"game"}
	scene.pending_page = ""
	scene.nav_page = "navigation"
	scene._toggle_power_page()
	check(scene.nav_page=="power","Dpad Up action must open System Power")
	scene._toggle_power_page()
	check(scene.nav_page=="navigation","Dpad Up action must close System Power")
	scene.hud_state.ui_mode = "menu"
	scene._toggle_power_page()
	check(scene.nav_page=="navigation","Dpad Up must not open unusable Power controls in a main menu")
	scene.hud_state = {"ready":true,"ui_mode":"screen","map_open":true}
	scene.wheel_committed = false
	scene.wheel.visible = true
	scene.wheel.set_entries([{"key":49,"enabled":true}],"WEAPONS")
	scene.wheel.selected = 0
	command_count = scene.commands.size()
	scene._commit_wheel()
	check(scene.commands.size()==command_count and not scene.wheel.visible,"Opening a native map must cancel equipment wheel commits")
	scene.hud_state = saved_state
	scene.event_surface.visible = true
	scene.event_surface.canvas.frame_image = image
	scene.event_surface.source_rect = Rect2(313,138,650,390)
	var event_pixel: Variant = scene.event_surface.ray_pixel(scene.event_surface.to_global(Vector3(0,0,1)), -scene.event_surface.global_basis.z)
	check(event_pixel == Vector2i(638,333),"Cropped event ray must retain the original native coordinates")
	# A visible HUD pixel takes precedence over a physically nearer world panel.
	scene.hud_surface.canvas.frame_image = image
	scene.hud_surface.global_transform = Transform3D.IDENTITY
	scene.world_surface.global_transform = Transform3D(Basis.IDENTITY,Vector3(0,0,0.4))
	scene.world_surface.visible = true
	scene.world_surface.canvas.frame_image = image
	var top_hit: Dictionary = scene._surface_hit(Vector3(0,0,1),Vector3.FORWARD)
	check(top_hit.surface == scene.hud_surface,"Rendered HUD priority must match click priority")
	# A hand map wins against an overlapping opaque HUD pixel, regardless of distance.
	scene.nav_panel.global_transform = Transform3D(Basis.IDENTITY,Vector3(0,0,0.4))
	scene.nav_panel.visible = true
	scene.hud_state.map_open = false
	scene.hud_state.tactical = true
	scene._refresh_navigation()
	scene.map_surface.visible = true
	scene.map_surface.canvas.frame_image = image
	var hand_top: Dictionary = scene._surface_hit(Vector3(0,0,1),Vector3.FORWARD)
	check(hand_top.get("surface") == scene.map_surface,"Controller screen click priority must match its foreground draw priority")
	scene.map_surface.visible = false
	scene._select_from_ray(Vector3(0,0,1),Vector3.FORWARD)
	check(scene.held_surface == null,"Blank hand panel pixels must block clicks into the HUD behind them")
	scene.nav_panel.visible = false
	scene.nav_page = "power"
	scene.hud_state = {"ready":true,"ui_mode":"screen","panel_open":true,"blocking_ui":true}
	scene.last_hover_time = -1.0
	command_count = scene.commands.size()
	scene._hover_ui(Vector3(0,0,1),Vector3.FORWARD)
	check(scene.commands.size()==command_count+1 and scene.commands.back().action=="ui_move","Native window hover must remain available while System Power is selected")
	scene.nav_page = "navigation"
	var window_image := Image.create(1280,720,false,Image.FORMAT_RGBA8)
	var body_image := Image.create(650,520,false,Image.FORMAT_RGBA8)
	body_image.fill(Color.WHITE)
	window_image.blit_rect(body_image,Rect2i(0,0,650,520),Vector2i(300,90))
	scene.world_surface.canvas.frame_image = window_image
	scene.world_panel_crop_pending = true
	scene.world_panel_open_age = 0.3
	scene.world_panel_opened_at = 100.0
	scene.world_surface.canvas.capture_time_unix = 99.0
	var old_crop: Rect2 = scene.world_surface.source_rect
	scene._position_world_panels()
	check(scene.world_panel_crop_pending and scene.world_surface.source_rect == old_crop,"A previous panel's cached frame must not lock a new window crop")
	scene.world_surface.canvas.capture_time_unix = 100.1
	scene._position_world_panels()
	var fixed_crop: Rect2 = scene.world_surface.source_rect
	check(fixed_crop == Rect2(300,90,650,520),"Native world window crop must preserve its original pixel coordinates")
	check(scene.world_surface.global_position.y > scene.player_ship.global_position.y,"Ship and store windows must hang above the VR player ship")
	scene.world_surface.canvas.frame_image = image
	scene._position_world_panels()
	check(scene.world_surface.source_rect == fixed_crop,"Hover image changes must not resize a floating window or change pointer mapping")
	scene.world_surface.canvas.capture_time_unix = 0.0
	scene.world_panel_open_frame_count = scene.world_surface.canvas.received_frames
	check(not scene._world_panel_has_fresh_frame(),"Legacy PNG transport must wait for a new image on panel opening")
	scene.world_surface.canvas.received_frames += 1
	check(scene._world_panel_has_fresh_frame(),"A newly decoded legacy PNG must remain usable without a raw timestamp")
	scene.world_panel_kind = "sell"
	scene.world_panel_crop_pending = true
	scene._position_world_panels()
	check(scene.world_surface.source_rect == Rect2(0,0,1280,720),"Shop crop must retain detached sell drop boxes and future hover panels")
	check(scene.world_surface.surface_size.x <= 1.03 and scene.event_surface.surface_size.x < 1.0,"Floating ship/store and event panels must be smaller")
	# The authoritative pause cue does not inherit a cached native image or forced menu freeze.
	scene.hud_state = {"ready":true,"paused":true}
	scene.paused = true
	scene._update_hud()
	scene._refresh_navigation()
	check(scene.pause_label.visible and "PAUSED" in scene.nav_title.text,"Paused status must be present on HUD and hand screen from the same state")
	scene.hud_state = {"ready":true,"paused":false,"frozen":true}
	scene._update_hud()
	scene._refresh_navigation()
	check(not scene.pause_label.visible and "PAUSED" not in scene.nav_title.text,"A menu freeze must not leave a stale player-pause cue")
	# Text buttons send native text operations, with no leaked UI mouse-up/hotkeys.
	scene.wheel.visible = true
	scene.wheel_committed = false
	scene._apply_text_entry({"active":true,"id":"rename-1","kind":"crew","text":"Test","cursor":4})
	check(not scene.wheel.visible and scene.wheel_committed,"Native renaming must cancel an already-open action wheel")
	var count_before_modal_wheel: int = scene.commands.size()
	scene.wheel_committed = false
	scene._commit_wheel()
	check(scene.commands.size() == count_before_modal_wheel,"Wheel release must not send a gameplay key into native text entry")
	scene.rename_keyboard.global_transform = Transform3D.IDENTITY
	var key: Dictionary = scene.rename_keyboard.keys[10]
	var key_pixel: Vector2 = key.rect.get_center()
	var key_world: Vector3 = scene.rename_keyboard.to_global(Vector3((key_pixel.x/1000.0-0.5)*0.86,(0.5-key_pixel.y/454.0)*0.39,0))
	scene._select_from_ray(key_world+Vector3(0,0,1),Vector3.FORWARD)
	check(scene.commands.back().action == "text_input" and scene.commands.back().data.op == "insert" and scene.commands.back().data.text == "Q" and scene.commands.back().data.entry_id == "rename-1","VR keyboard must insert into the exact active native name field")
	var count_before_release: int = scene.commands.size()
	scene._release_pointer(key_world+Vector3(0,0,1),Vector3.FORWARD)
	check(scene.commands.size() == count_before_release,"Keyboard release must not leak a native UI click")
	scene._select_from_ray(Vector3(0,20,0),Vector3.DOWN)
	check(scene.commands.size() == count_before_release,"Active renaming must block background HUD, menu and scene clicks")
	scene._secondary_click(Vector3.ZERO,Vector3.DOWN)
	check(scene.commands.back().action == "text_input" and scene.commands.back().data.op == "cancel","B must cancel the native rename field")
	scene.rename_keyboard.set_entry({"active":false})
	for surface in [scene.hud_surface,scene.world_surface,scene.event_surface,scene.map_surface]: surface.visible = false
	scene.hud_state = {"ready":true,"ui_mode":"screen","tactical":true}
	scene.demo_mode = false
	scene.bridge_connected = true
	# Weapon targets and beam endpoints ignore miniatures and door colliders.
	scene.weapon_selected = true
	scene.battle = true
	var enemy_room: int = scene.enemy_ship.room_points.keys()[0]
	var enemy_point: Vector3 = scene.enemy_ship.room_target(enemy_room)
	var obstruction := Area3D.new()
	obstruction.set_meta("kind","door")
	obstruction.set_meta("ship","enemy")
	var obstruction_shape := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(0.1,0.1,0.1)
	obstruction_shape.shape = obstruction_box
	obstruction.add_child(obstruction_shape)
	scene.add_child(obstruction)
	obstruction.global_position = enemy_point + Vector3(0,0.2,0)
	await physics_frame
	scene._select_from_ray(enemy_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.commands.back().action == "target_room" and scene.commands.back().data.room_id == enemy_room,"Weapon room selection must bypass enemy crew and door colliders")
	scene.beam_drag = true
	scene._release_pointer(enemy_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.commands.back().action == "target_room" and scene.commands.back().data.phase == "up","Beam release must use the same room-floor picking")
	scene.hud_state = {"ready":true,"ui_mode":"game","weapon_selected":0,"player":{"weapons":[{"kind":"beam"}]},"targeting":{"active":true,"kind":"weapon","ships":["enemy"]}}
	var saved_bounds: Dictionary = scene.enemy_ship.room_bounds
	var saved_image: Dictionary = scene.enemy_ship.layout_data.get("image_rect", {})
	var saved_table: Transform3D = scene.tabletop_root.transform
	scene.enemy_ship.room_bounds = {enemy_room:Rect2(-0.5,-0.2,0.4,0.4),999:Rect2(0.1,-0.2,0.4,0.4)}
	scene.enemy_ship.layout_data.image_rect = {}
	scene.tabletop_root.rotation.y += 0.47
	scene.tabletop_root.scale *= 1.6
	var first_local := Vector3(-0.499,0.0775,-0.199)
	var first_world: Vector3 = scene.enemy_ship.to_global(first_local)
	scene._select_from_ray(first_world+Vector3.UP,Vector3.DOWN)
	var first_command: Dictionary = scene.commands.back()
	var expected_native: Vector2 = Vector2(first_local.x,first_local.z) / scene.ShipModel.TILE + scene.enemy_ship.layout_center + Vector2(float(scene.enemy_ship.layout_data.get("x_offset",0)),float(scene.enemy_ship.layout_data.get("y_offset",0)))
	check(scene.beam_drag and first_command.data.phase == "down" and first_command.data.has("point"),"Beam press must supply the actual freely chosen native deck point")
	check(absf(float(first_command.data.point.x)-expected_native.x*35.0)<0.001 and absf(float(first_command.data.point.y)-expected_native.y*35.0)<0.001,"Beam endpoints must retain subpixel room-edge position under scaled/rotated table transforms")
	var gap_world: Vector3 = scene.enemy_ship.to_global(Vector3(0,0.0775,0.03))
	var gap_hit: Dictionary = scene._beam_deck_hit(gap_world+Vector3.UP,Vector3.DOWN,"enemy")
	check(not gap_hit.is_empty() and gap_hit.room_id == -1,"Free beam placement must allow the deck between rooms rather than snapping to a nearest room")
	scene.last_hover_time = -1.0
	scene._hover_ui(gap_world+Vector3.UP,Vector3.DOWN)
	check(scene.commands.back().data.phase == "move" and scene.commands.back().data.point == gap_hit.pixel,"Held beam aiming must forward native endpoint movement before release")
	scene._release_pointer(gap_world+Vector3.UP,Vector3.DOWN)
	check(not scene.beam_drag and scene.commands.back().data.phase == "up" and scene.commands.back().data.room_id == -1 and scene.commands.back().data.point == gap_hit.pixel,"Beam release must preserve an inter-room endpoint exactly")
	check(scene._beam_deck_hit(scene.enemy_ship.to_global(Vector3(9,0.0775,9))+Vector3.UP,Vector3.DOWN,"enemy").is_empty(),"Free beam projection must reject points outside the current ship's deck envelope")
	scene.enemy_ship.room_bounds = saved_bounds
	scene.enemy_ship.layout_data.image_rect = saved_image
	scene.tabletop_root.transform = saved_table
	scene.hud_state = {"ready":true,"ui_mode":"screen","tactical":true}
	for kind in ["mind", "hacking", "teleporter"]:
		scene.hud_state.targeting = {"active":true,"kind":kind,"ships":["enemy"]}
		scene._select_from_ray(enemy_point+Vector3(0,1,0),Vector3.DOWN)
		check(scene.commands.back().action == "target_room" and scene.commands.back().data.ship == "enemy" and not scene.beam_drag,"Native %s targeting must work on 3D enemy room floors" % kind)
	scene.hud_state.targeting = {"active":false}
	obstruction.queue_free()
	var room_id: int = scene.player_ship.room_points.keys()[0]
	var room_point: Vector3 = scene.player_ship.room_target(room_id)
	var crew := Area3D.new()
	crew.set_meta("kind","crew")
	crew.set_meta("crew_id","grab-test")
	crew.set_meta("ship","player")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.04
	shape.shape = sphere
	crew.add_child(shape)
	scene.add_child(crew)
	crew.global_position = room_point + Vector3(0,0.2,0)
	await physics_frame
	scene.hud_state.blocking_ui = true
	var blocked_count: int = scene.commands.size()
	scene._select_from_ray(room_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.commands.size() == blocked_count,"Real native dialogs must block background crew commands even in Tactical")
	scene.hud_state.blocking_ui = false
	scene.hud_state.targeting = {"active":true,"kind":"mind","ships":["player","enemy"]}
	scene._select_from_ray(room_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.commands.back().action == "target_room" and scene.commands.back().data.ship == "player" and scene.grabbed_crew == null,"Friendly mind control must target the room instead of grabbing its crew")
	scene.hud_state.targeting = {"active":false}
	scene.shift_down = true
	scene._select_from_ray(room_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.grabbed_crew == crew and scene.commands.back().action == "select_crew","Holding trigger on crew must begin a native selection and visual grab")
	scene.crew_id_selected = "older-native-selected-crew"
	scene.shift_down = false
	scene._release_pointer(room_point+Vector3(0,1,0),Vector3.DOWN)
	check(scene.grabbed_crew == null and scene.commands.back().action == "move_crew" and scene.commands.back().data.room_id == room_id and scene.commands.back().data.crew_id == "grab-test","Dropping crew must retain the grabbed id despite asynchronous native selection updates")
	check(scene.commands.back().data.modifiers.shift,"Quick Shift-grabs must retain group selection even when grip is released before native selection acknowledgement")
	scene._begin_crew_grab(crew,room_point+Vector3(0,1,0))
	scene._secondary_click(Vector3(0,20,0),Vector3.UP)
	check(scene.grabbed_crew == null and scene.commands.back().action == "cancel","B must cancel the grab without issuing a move")
	crew.queue_free()
	scene.nav_page = "power"
	scene.hud_state.tactical = false
	scene.hud_state.ui_mode = "game"
	scene.hud_state.player = {"system_status":[{"id":0,"key":"shields","powerable":true,"allocated":2,"max_power":4},{"id":1,"key":"engines","powerable":true,"allocated":1,"max_power":3}]}
	scene._refresh_navigation()
	scene.nav_panel.visible = true
	scene.nav_panel.global_transform = Transform3D.IDENTITY
	var card: Rect2 = scene.panel_theme.power_card_rect(0)
	var card_pixel: Vector2 = card.position + Vector2(3,card.size.y*0.5)
	var card_point := Vector3((card_pixel.x/1150.0-0.5)*0.92,(0.5-card_pixel.y/900.0)*0.72,0.012)
	var oblique_from := card_point + Vector3(-0.65,0,0.3)
	var oblique_hit: Dictionary = scene._hand_panel_hit(oblique_from,(card_point-oblique_from).normalized())
	check(oblique_hit.get("system_key", "") == "shields","Oblique power-page pointing must hit the visible card edge on the actual display plane")
	card = scene.panel_theme.power_card_rect(1)
	card_pixel = card.get_center()
	card_point = Vector3((card_pixel.x/1150.0-0.5)*0.92,(0.5-card_pixel.y/900.0)*0.72,0.012)
	scene.pointer_transform = Transform3D(Basis.IDENTITY,card_point+Vector3(0,0,1))
	scene.ray_filter.initialized = true
	scene._update_pointer()
	check(scene.panel_theme.selected_system().key == "engines","Power pointing must select the current card before a same-frame left trigger press")
	scene.panel_theme.step_selection(-1)
	scene._update_pointer()
	scene._hover_ui(scene.pointer_transform.origin,Vector3.FORWARD)
	check(scene.panel_theme.selected_system().key == "shields","A stationary power-page ray must not override X/Y system selection")
	scene.ray_filter.reset()
	scene.panel_theme.select_system("shields")
	scene.nav_panel.visible = false
	scene._change_system_power(1)
	check(scene.commands.back().action == "system_power" and scene.commands.back().data.system_id == 0 and scene.commands.back().data.direction == 1 and not scene.commands.back().data.modifiers.shift,"Power trigger must use installed system identity and neutral modifiers")
	scene._update_power_controls(true,false,true)
	check(scene.commands.back().data.system_id == 1 and scene.commands.back().data.direction == -1,"X/Y selection and bumper removal must act on the newly selected system")
	var held_count: int = scene.commands.size()
	scene._update_power_controls(true,false,true)
	check(scene.commands.size() == held_count,"Held bumper and X/Y must dispatch once per press")
	scene._update_power_controls(false,false,false)
	scene._update_power_controls(false,true,false)
	check(scene.panel_theme.selected_system().key == "shields","Previous-system button must wrap back through installed systems")
	scene.nav_page = "tactical"
	scene.pending_page = ""
	scene.hud_state.tactical = true
	scene.hud_state.ui_mode = "screen"
	scene._toggle_tactical()
	check(scene.commands.back().action == "navigate" and scene.commands.back().data.screen == "tactical","Dpad Down must close Tactical without pausing")
	scene.hud_state.tactical = false
	scene.hud_state.ui_mode = "game"
	scene.pending_page = ""
	scene._toggle_tactical()
	check(scene.commands.back().data.screen == "tactical","Dpad Down must open Tactical from gameplay")
	check(scene.pause_label.position.y > 0.0,"Authoritative pause cue must remain above the HUD center, clear of Autofire")
	var filter := preload("res://scripts/pose_filter.gd").new()
	var steady := Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.3))
	filter.update(steady,1.0/90.0)
	for i in range(90):
		var jitter := steady
		jitter.origin.x += 0.001 if i%2==0 else -0.001
		jitter.basis = Basis(Vector3.UP,deg_to_rad(0.1 if i%2==0 else -0.1))
		filter.update(jitter,1.0/90.0)
	check(filter.value.is_equal_approx(steady),"Submillimetre hand/ray jitter must not move a stationary panel")
	var moved := steady
	moved.origin.x += 0.12
	for i in range(9): filter.update(moved,1.0/90.0)
	check(filter.value.origin.distance_to(moved.origin)<0.012,"Deliberate hand movement must follow within a tenth of a second")
	filter.reset()
	check(filter.update(moved,1.0/90.0).is_equal_approx(moved),"Reacquired tracking must snap rather than retain the previous pose")
	# Recenter is explicit; combat arrival must preserve the player's ship anchor.
	scene.xr_active = true
	scene._recenter()
	var head_point: Vector3 = scene.camera.get_camera_transform().origin
	var offset: Vector3 = scene.tabletop_root.global_position - head_point
	var forward: Vector3 = -scene.camera.get_camera_transform().basis.z
	forward.y = 0
	check(Vector2(offset.x,offset.z).length() > 0.8 and offset.dot(forward.normalized()) > 0.8 and is_equal_approx(offset.y,-0.95),"Recenter must place the table in front of the headset at its established height")
	scene.battle = false
	scene._update_ship_positions()
	var player_position: Vector3 = scene.player_ship.global_position
	scene.battle = true
	scene._update_ship_positions()
	check(scene.player_ship.global_position.is_equal_approx(player_position),"Another ship arriving must not shift the player's placed table")
	var head_tracker := XRPositionalTracker.new()
	head_tracker.name = "head"
	head_tracker.type = XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(1.4,1.65,-0.9)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head_tracker)
	scene.initial_table_placed = false
	scene._place_initial_table()
	check(scene.initial_table_placed,"First valid headset pose must place the tabletop exactly once")
	var initial_position: Vector3 = scene.tabletop_root.global_position
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(2.4,1.65,-0.9)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	scene._place_initial_table()
	check(scene.tabletop_root.global_position.is_equal_approx(initial_position),"Walking after initial placement must not drag the ship with the headset")
	head_tracker.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	scene._recenter()
	check(scene.player_ship.global_position.y < scene.camera.get_camera_transform().origin.y - 0.3,"Head-relative XR spaces with zero head height must still place the ship below the headset")
	XRServer.remove_tracker(head_tracker)
	# A native end page may still report the previous ship and world-window flags.
	scene.hud_state = {"ready":true,"ui_mode":"game","end_screen":true,"panel_open":true,"map_open":true,"tactical":true,"paused":true}
	scene.world_surface.visible = true
	scene.event_surface.visible = true
	scene.wheel.visible = true
	scene.beam_drag = true
	scene.pending_page = "power"
	check(scene._apply_end_screen(scene.hud_state),"Native victory/death state must enter the full-screen presentation path")
	check(not scene.gameplay_hud and scene.hud_surface.source_rect == Rect2(0,0,1280,720) and scene.hud_surface.canvas.frame_file == "screen_frame.png","Final pages must use all native screen pixels regardless of stale in-run panel flags")
	check(not scene.world_surface.visible and not scene.event_surface.visible and not scene.map_surface.visible and not scene.nav_panel.visible and not scene.player_ship.visible and not scene.enemy_ship.visible and not scene.combat_effects.visible,"Final native pages must not be obscured by old combat or world UI")
	check(not scene.beam_drag and not scene.wheel.visible and scene.pending_page == "" and not scene.pause_label.visible,"Finished runs must cancel transient aiming and pause cues")
	var end_commands: int = scene.commands.size()
	scene._toggle_pause()
	check(scene.commands.size() == end_commands,"The Pause button must not send a gameplay key into a native final screen")
	scene.hud_state = {"ready":true,"ui_mode":"game"}
	check(not scene._apply_end_screen(scene.hud_state),"A new active run must leave the final-screen path")
	scene._sync_hud_layout()
	scene._face_navigation_to_headset()
	check(scene.gameplay_hud and scene.nav_panel.visible,"A new run must regain the compact HUD and visible tracked hand screen")
	XRServer.remove_tracker(left_tracker)
	XRServer.remove_tracker(tracker)
	scene.queue_free()
	await process_frame
	print("INPUT_TESTS ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
