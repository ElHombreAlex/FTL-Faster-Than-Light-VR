extends Node3D

const ShipModel = preload("res://scripts/ship_model.gd")
const HudSurface = preload("res://scripts/hud_surface.gd")
const HudAnchor = preload("res://scripts/hud_anchor.gd")
const ShortcutWheel = preload("res://scripts/shortcut_wheel.gd")
const CombatEffects = preload("res://scripts/combat_effects.gd")
const SpaceEnvironment = preload("res://scripts/space_environment.gd")
const RenameKeyboard = preload("res://scripts/rename_keyboard.gd")
const ControllerHelp = preload("res://scripts/controller_help.gd")
const ControllerPanel = preload("res://scripts/controller_panel.gd")
const PoseFilter = preload("res://scripts/pose_filter.gd")
const EnemyHullBar = preload("res://scripts/enemy_hull_bar.gd")
const UiAssets = preload("res://scripts/ftl_ui_assets.gd")

var xr_active := false
var origin: XROrigin3D
var camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var player_ship: Node3D
var enemy_ship: Node3D
var nav_panel: Node3D
var hud_surface: Node3D
var hud_anchor := HudAnchor.new()
var gameplay_hud := false
const GAMEPLAY_HUD_RECT := Rect2(0, 0, 872, 510)
const GAMEPLAY_HUD_SIZE := Vector2(1.10, 1.10 * 510.0 / 872.0)
var combat_effects: Node3D
var hud_state: Dictionary = {}
var seen_shots: Dictionary = {}
var right_laser: MeshInstance3D
var hover_marker: MeshInstance3D
var hazard_root: Node3D
var space_environment: Node3D
var battle := true
var paused := false
var hazard := "clear"
var crew_selected := false
var weapon_selected := true
var trigger_was_down := false
var pause_was_down := false
var cancel_was_down := false
var last_command := "Select a crew marker or target an enemy room"
var elapsed := 0.0
var state_poll_elapsed := 0.0
var state_signature := ""
var bridge_connected := false
var hull_current := 30
var hull_max := 30
var shield_level := 2
var reactor_power := 8
var tabletop_root: Node3D
var map_surface: Node3D
var crew_id_selected := ""
var crew_ship_selected := "player"
var held_surface: Node3D
var held_pixel := Vector2i.ZERO
var beam_drag := false
var inspect_was_down := false
var tactical_was_down := false
var grip_last_position := Vector3.ZERO
var gripping := false
var bridge_session := ""
var hover_elapsed := 0.0
var demo_mode := false
var recenter_was_down := false
var last_hover_time := 0.0
var shift_down := false
var control_down := false
var nav_page := "navigation"
var nav_buttons: Array[Area3D] = []
var nav_title: Label3D
var help_label: Node3D
var pause_label: Label3D
var rename_keyboard: Node3D
var keyboard_press := false
var target_room_label: Label3D
var pointed_room := -1
var pointed_ship := ""
var panel_theme: Node3D
var enemy_hull_bar: Node3D
var panel_filter := PoseFilter.new()
var ray_filter := PoseFilter.new()
var pointer_transform := Transform3D.IDENTITY
var power_remove_was_down := false
var power_previous_was_down := false
var power_next_was_down := false
var power_hover_key := ""
var power_page_was_down := false
var tracking_label: Label3D
var diagnostics_elapsed := 0.0
var diagnostics_signature := ""
var wheel: Node3D
var wheel_category := 0
var wheel_was_down := false
var wheel_committed := false
var wheel_dialog_id := ""
var page_left_was_down := false
var page_right_was_down := false
var station_was_down := false
var event_surface: Node3D
var event_was_open := false
var pending_page := ""
var world_surface: Node3D
var initial_table_placed := false
var grabbed_crew: Node3D
var crew_preview: Node3D
var grab_distance := 0.0
var grab_ship := ""
var grab_crew_id := ""
var grab_shift_down := false
var grab_room := -1
var grab_label: Label3D
var world_panel_kind := ""
var world_panel_crop_pending := false
var world_panel_open_age := 0.0
var world_panel_opened_at := 0.0
var world_panel_open_frame_count := 0
const HAND_PAGES := ["navigation", "tactical", "shortcuts", "power", "jump", "help"]


func _ready() -> void:
	demo_mode = "--demo" in OS.get_cmdline_user_args()
	_create_stage()
	_create_rig()
	_create_ships()
	enemy_hull_bar = EnemyHullBar.new()
	add_child(enemy_hull_bar)
	enemy_hull_bar.build()
	ray_filter.position_deadband = 0.0008
	ray_filter.angle_deadband = deg_to_rad(0.07)
	ray_filter.time_constant = 0.045
	_create_hud()
	_create_navigation()
	_create_pointer()
	_create_event_panel()
	_create_world_panel()
	_create_grab_preview()
	_create_rename_keyboard()
	wheel = ShortcutWheel.new()
	add_child(wheel)
	_set_hazard("clear")
	var interface := XRServer.find_interface("OpenXR")
	if "--desktop" not in OS.get_cmdline_user_args() and interface != null and (interface.is_initialized() or interface.initialize()):
		get_viewport().use_xr = true
		xr_active = true
		camera.position = Vector3.ZERO
		origin.position = Vector3(0.0, 0.0, 1.3)
	else:
		if "--require-vr" in OS.get_cmdline_user_args():
			push_error("OpenXR headset unavailable. Start SteamVR and connect the headset and controllers, then retry.")
			get_tree().quit(2)
			return
		camera.position = Vector3(0.0, 2.5, 3.0)
		camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
		nav_panel.visible = false
		initial_table_placed = true
	_poll_bridge_state()
	_update_hud()
	if "--demo-shot" in OS.get_cmdline_user_args():
		call_deferred("_demo_shot", "laser", "player")


func _create_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.007, 0.012, 0.027)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.43, 0.51, 0.67)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -20.0, 0.0)
	light.light_energy = 1.4
	add_child(light)
	tabletop_root = Node3D.new()
	tabletop_root.name = "FloatingEncounter"
	add_child(tabletop_root)
	tabletop_root.position.y = 0.7
	tabletop_root.scale = Vector3.ONE * 0.35
	space_environment = SpaceEnvironment.new()
	add_child(space_environment)
	space_environment.build()


func _create_rig() -> void:
	origin = XROrigin3D.new()
	origin.name = "PlayerOrigin"
	add_child(origin)
	camera = XRCamera3D.new()
	camera.name = "HeadCamera"
	camera.current = true
	origin.add_child(camera)
	left_hand = XRController3D.new()
	left_hand.name = "LeftController"
	left_hand.tracker = "left_hand"
	origin.add_child(left_hand)
	right_hand = XRController3D.new()
	right_hand.name = "RightController"
	right_hand.tracker = "right_hand"
	# OpenXR actions end in _pose, but Godot renames their tracker poses.
	right_hand.pose = "aim"
	origin.add_child(right_hand)


func _create_ships() -> void:
	player_ship = ShipModel.new()
	player_ship.name = "PlayerShip"
	tabletop_root.add_child(player_ship)
	player_ship.build("kestral", false)
	enemy_ship = ShipModel.new()
	enemy_ship.name = "EnemyShip"
	tabletop_root.add_child(enemy_ship)
	enemy_ship.build("rebel_long", true)
	combat_effects = CombatEffects.new()
	add_child(combat_effects)
	_update_ship_positions()


func _update_ship_positions() -> void:
	# Keep the player's placement stable when a second ship enters the encounter.
	player_ship.position = Vector3(0.0, 0.84, 0.0)
	player_ship.rotation.y = -PI / 2.0 if int(player_ship.layout_data.get("vertical", 0)) != 0 else 0.0
	enemy_ship.position = Vector3(5.0, 0.84, 0.0)
	# Kestrel's bow is local +X; Rebel long's bow is local -Z.
	enemy_ship.rotation.y = PI / 2.0 if int(enemy_ship.layout_data.get("vertical", 1)) != 0 else PI
	enemy_ship.visible = battle


func _create_hud() -> void:
	hud_surface = HudSurface.new()
	hud_surface.render_order = 100
	add_child(hud_surface)
	hud_surface.canvas.use_original_frame = not demo_mode
	pause_label = Label3D.new()
	pause_label.font = UiAssets.font("header")
	pause_label.outline_size = 0
	pause_label.position = Vector3(0, HudSurface.SURFACE_SIZE.y * 0.5 + 0.025, 0.015)
	pause_label.font_size = 32
	pause_label.pixel_size = 0.0008
	pause_label.no_depth_test = true
	pause_label.render_priority = 101
	pause_label.modulate = Color("c6f3da")
	hud_surface.add_child(pause_label)
	_sync_hud_layout()
	_position_hud(0.0, true)


func _gameplay_hud_mode() -> bool:
	if not bool(hud_state.get("ready", demo_mode)):
		return false
	# In-run native windows have a separate world surface. A simultaneous
	# native menu flag must not expand the HUD into a second copy of that window.
	if str(hud_state.get("ui_mode", "")) == "menu" and not bool(hud_state.get("panel_open", false)):
		return false
	# Desktop preview still needs the complete screen for its Tactical/map view;
	# in VR those views have their own hand/world surfaces with native coordinates.
	return xr_active or not (hud_state.get("map_open", false) or hud_state.get("tactical", false))


func _sync_hud_layout() -> void:
	if hud_surface == null:
		return
	var next_mode := _gameplay_hud_mode()
	if gameplay_hud != next_mode:
		gameplay_hud = next_mode
		hud_anchor.reset()
	if gameplay_hud:
		hud_surface.set_crop(GAMEPLAY_HUD_RECT, GAMEPLAY_HUD_SIZE)
	else:
		hud_surface.set_crop(Rect2(0, 0, 1280, 720), HudSurface.SURFACE_SIZE)
	pause_label.position = Vector3(0, hud_surface.surface_size.y * 0.5 + 0.025, 0.015)


func _player_hud_local_bounds() -> AABB:
	var bounds := AABB(player_ship.shield_center - player_ship.shield_radii, player_ship.shield_radii * 2.0)
	# Keep the envelope even when shields are depleted, preventing the HUD from
	# dropping through crew/weapons or jumping when shields recharge.
	for rect: Rect2 in player_ship.room_bounds.values():
		bounds = bounds.expand(Vector3(rect.position.x, -0.16, rect.position.y))
		bounds = bounds.expand(Vector3(rect.end.x, 0.35, rect.end.y))
	var image: Dictionary = player_ship.layout_data.get("image_rect", {})
	if not image.is_empty():
		var first: Vector2 = (Vector2(float(image.get("x", 0)), float(image.get("y", 0))) / 35.0 - player_ship.layout_center) * ShipModel.TILE
		var last: Vector2 = first + Vector2(float(image.get("w", 0)), float(image.get("h", 0))) / 35.0 * ShipModel.TILE
		bounds = bounds.expand(Vector3(first.x, -0.16, first.y))
		bounds = bounds.expand(Vector3(last.x, 0.35, last.y))
	return bounds


func _position_hud(delta: float, snap := false) -> void:
	if hud_surface == null or camera == null:
		return
	var viewer := camera.get_camera_transform()
	if gameplay_hud:
		hud_surface.global_transform = hud_anchor.update(player_ship.global_transform, _player_hud_local_bounds(), viewer, GAMEPLAY_HUD_SIZE, delta, snap)
	else:
		# Preserve the old full native menu framing; the HUD node itself can remain
		# outside the camera so gameplay can clamp its head-relative pose above
		# the ship when necessary.
		hud_surface.global_transform = viewer * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.64), Vector3(0, -0.16, -1.8))


func _create_navigation() -> void:
	nav_panel = Node3D.new()
	nav_panel.name = "ControllerNavigation"
	left_hand.add_child(nav_panel)
	nav_panel.top_level = true
	nav_panel.position = Vector3(0.0, 0.08, -0.11)
	nav_panel.scale = Vector3.ONE * 0.6
	var base := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.92, 0.72, 0.016)
	base.mesh = mesh
	base.material_override = _material(Color(0.035, 0.075, 0.075))
	base.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base.material_override.no_depth_test = true
	base.material_override.render_priority = 120
	nav_panel.add_child(base)
	base.visible = false
	panel_theme = ControllerPanel.new()
	nav_panel.add_child(panel_theme)
	for i in range(14):
		var button := Area3D.new()
		button.position = Vector3(-0.22 if i % 2 == 0 else 0.22, 0.235 - floori(i / 2.0) * 0.08, 0.025)
		button.set_meta("kind", "navigation")
		nav_panel.add_child(button)
		nav_buttons.append(button)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.40, 0.067, 0.04)
		shape.shape = box
		button.add_child(shape)
		var label := Label3D.new()
		label.font = UiAssets.font("body")
		label.outline_size = 0
		label.font_size = 21
		label.pixel_size = 0.0011
		label.position.z = 0.027
		label.no_depth_test = true
		label.render_priority = 123
		label.modulate = Color(0.73, 0.98, 0.81)
		button.add_child(label)
		var plate := MeshInstance3D.new()
		var tile := BoxMesh.new()
		tile.size = Vector3(0.405, 0.07, 0.006)
		plate.mesh = tile
		plate.position.z = 0.015
		plate.material_override = _emissive(Color(0.12, 0.23, 0.21), 0.25)
		plate.material_override.no_depth_test = true
		plate.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plate.material_override.render_priority = 122
		button.add_child(plate)
		label.visible = false
		plate.visible = false
	nav_title = Label3D.new()
	nav_title.font = UiAssets.font("header")
	nav_title.outline_size = 0
	nav_title.position = Vector3(0, 0.32, 0.03)
	nav_title.font_size = 23
	nav_title.pixel_size = 0.001
	nav_title.no_depth_test = true
	nav_title.render_priority = 123
	nav_panel.add_child(nav_title)
	nav_title.visible = false
	var legend := Label3D.new()
	legend.font = UiAssets.font("body")
	legend.outline_size = 0
	legend.position = Vector3(0, -0.395, 0.03)
	legend.font_size = 18
	legend.pixel_size = 0.001
	legend.no_depth_test = true
	legend.render_priority = 123
	legend.text = "Dpad ◀ / ▶: screen   ▼: tactical   ▲: power\nView: pause   R bumper: 1–8 wheel"
	nav_panel.add_child(legend)
	legend.visible = false
	help_label = ControllerHelp.new()
	help_label.position.z = 0.045
	nav_panel.add_child(help_label)
	map_surface = HudSurface.new()
	map_surface.frame_file = "screen_frame.png"
	map_surface.render_order = 122
	map_surface.scale = Vector3.ONE * 0.3
	map_surface.position = Vector3(0.0, 0.03, 0.045)
	nav_panel.add_child(map_surface)
	map_surface.visible = false
	tracking_label = Label3D.new()
	tracking_label.font = UiAssets.font("body")
	tracking_label.outline_size = 0
	tracking_label.position = Vector3(0.28, -0.34, -1.4)
	tracking_label.font_size = 24
	tracking_label.pixel_size = 0.0008
	tracking_label.no_depth_test = true
	tracking_label.render_priority = 101
	camera.add_child(tracking_label)
	_refresh_navigation()


func _create_pointer() -> void:
	right_laser = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.0008
	beam.bottom_radius = 0.0008
	beam.height = 1.0
	right_laser.mesh = beam
	right_laser.material_override = _emissive(Color(0.32, 1.0, 0.72), 2.0)
	right_laser.material_override.no_depth_test = true
	right_laser.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	right_laser.material_override.render_priority = 127
	right_laser.visible = false
	add_child(right_laser)
	hover_marker = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.0025
	ball.height = 0.005
	hover_marker.mesh = ball
	hover_marker.material_override = _emissive(Color(0.45, 1.0, 0.72), 2.0)
	hover_marker.material_override.no_depth_test = true
	hover_marker.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_marker.material_override.render_priority = 127
	hover_marker.visible = false
	add_child(hover_marker)


func _create_event_panel() -> void:
	event_surface = HudSurface.new()
	event_surface.name = "EncounterDialog"
	event_surface.frame_file = "event_frame.png"
	event_surface.source_rect = Rect2(160, 138, 800, 390)
	event_surface.surface_size = Vector2(0.98, 0.588)
	event_surface.render_order = 40
	add_child(event_surface)
	event_surface.visible = false


func _game_actions_available() -> bool:
	return (rename_keyboard == null or not rename_keyboard.visible) and hud_state.get("ready", false) and (hud_state.get("ui_mode", "") == "game" or hud_state.get("tactical", false)) and not hud_state.get("blocking_ui", false) and not hud_state.get("map_open", false) and not hud_state.get("panel_open", false) and not hud_state.get("event_open", false) and not hud_state.get("transition", false)


func _world_actions_available() -> bool:
	return (rename_keyboard == null or not rename_keyboard.visible) and (demo_mode or (hud_state.get("ready", false) and (hud_state.get("ui_mode", "") == "game" or hud_state.get("tactical", false)) and not hud_state.get("blocking_ui", false) and not hud_state.get("map_open", false) and not hud_state.get("panel_open", false) and not hud_state.get("event_open", false) and not hud_state.get("transition", false)))


func _create_world_panel() -> void:
	world_surface = HudSurface.new()
	world_surface.name = "ShipAndStorePanel"
	world_surface.frame_file = "panel_frame.png"
	world_surface.surface_size = Vector2(1.02, 0.57375)
	world_surface.render_order = 45
	add_child(world_surface)
	world_surface.visible = false


func _create_grab_preview() -> void:
	grab_label = Label3D.new()
	grab_label.font = UiAssets.font("body")
	grab_label.outline_size = 0
	grab_label.font_size = 22
	grab_label.pixel_size = 0.00065
	grab_label.no_depth_test = true
	grab_label.render_priority = 126
	grab_label.modulate = Color(0.6, 1.0, 0.72)
	add_child(grab_label)
	grab_label.visible = false
	target_room_label = Label3D.new()
	target_room_label.font = UiAssets.font("body")
	target_room_label.outline_size = 0
	target_room_label.font_size = 24
	target_room_label.pixel_size = 0.00065
	target_room_label.no_depth_test = true
	target_room_label.render_priority = 126
	target_room_label.modulate = Color("ffe4ad")
	add_child(target_room_label)
	target_room_label.visible = false


func _create_rename_keyboard() -> void:
	rename_keyboard = RenameKeyboard.new()
	rename_keyboard.name = "NativeRenameKeyboard"
	add_child(rename_keyboard)


func _face_front(node: Node3D) -> void:
	var toward := camera.get_camera_transform().origin - node.global_position
	if toward.length_squared() < 0.00001:
		return
	var up := Vector3.UP if absf(toward.normalized().dot(Vector3.UP)) < 0.98 else camera.get_camera_transform().basis.y
	# The quads' visible face is +Z. A parent-space Y rotation after look_at
	# would reverse the vertical component and tip the wheel toward the floor.
	node.global_basis = Basis.looking_at(toward, up, true).scaled(node.global_basis.get_scale())


func _place_initial_table() -> void:
	if initial_table_placed:
		return
	var tracker := XRServer.get_tracker("head") as XRPositionalTracker
	if tracker == null or not tracker.has_pose("default") or not tracker.get_pose("default").has_tracking_data:
		return
	_recenter()
	initial_table_placed = true


func _position_world_panels() -> void:
	# These remain attached to the encounter, not to the head or controller.
	var head := camera.get_camera_transform().origin
	# Wait for this opening's native capture before freezing its bounds. An old
	# cached window must not determine the next window's crop after a slow frame.
	if world_surface.visible and world_panel_crop_pending and world_panel_open_age >= 0.25 and _world_panel_has_fresh_frame():
		# Store drop boxes and tooltips are separate native components. Retain a
		# fixed full-canvas envelope so hover content cannot escape the first crop
		# or resize the pointer mapping while an item is being dragged.
		var rect: Rect2i = Rect2i(0, 0, 1280, 720) if world_panel_kind in ["buy", "sell"] else world_surface.canvas.native_used_rect()
		if rect.size.x > 0 and rect.size.y > 0:
			world_surface.set_crop(Rect2(rect), Vector2(1.02, 1.02 * float(rect.size.y) / float(rect.size.x)))
			world_panel_crop_pending = false
	var anchor := player_ship.global_position
	anchor.y += 0.70
	var horizontal := head - anchor
	horizontal.y = 0.0
	if horizontal.length_squared() > 0.001:
		anchor += horizontal.normalized() * 0.18
	for panel in [event_surface, world_surface]:
		if panel.visible:
			panel.global_position = anchor
			_face_front(panel)
	if map_surface.visible and hud_state.get("map_open", false):
		map_surface.global_position = _pilot_map_anchor()
		_face_front(map_surface)
	if enemy_hull_bar != null:
		enemy_hull_bar.global_position = enemy_ship.global_position + Vector3(0, 0.52, 0)
		enemy_hull_bar.face_viewer(head)
	if rename_keyboard.visible:
		var view := camera.get_camera_transform()
		rename_keyboard.global_position = view.origin - view.basis.z * 0.72 - view.basis.y * 0.22
		_face_front(rename_keyboard)


func _world_panel_has_fresh_frame() -> bool:
	if world_surface.canvas.frame_image == null:
		return false
	if world_surface.canvas.capture_time_unix > 0.0:
		return world_surface.canvas.capture_time_unix >= world_panel_opened_at
	# Legacy PNG fixtures have no transport timestamp, so require a new image.
	return world_surface.canvas.received_frames > world_panel_open_frame_count


func _pilot_map_anchor() -> Vector3:
	# The native room role follows the actual installed piloting system, even
	# on layouts whose cockpit is away from the nose. Distances stay in metres
	# when the player resizes or turns the encounter.
	var cockpit := player_ship.global_position
	for id in player_ship.room_nodes:
		if str(player_ship.room_nodes[id].get_meta("system_role", "")) == "pilot":
			cockpit = player_ship.to_global(player_ship.room_points[id])
			break
	var local_bow := Vector3.FORWARD if int(player_ship.layout_data.get("vertical", 0)) != 0 else Vector3.RIGHT
	var bow: Vector3 = (player_ship.global_basis * local_bow).normalized()
	var up: Vector3 = player_ship.global_basis.y.normalized()
	return cockpit + up * 0.62 + bow * 0.24


func _cycle_hand_page(direction: int) -> void:
	var current_page := pending_page if pending_page != "" else nav_page
	var index := HAND_PAGES.find(current_page)
	_open_hand_page(HAND_PAGES[posmod(maxi(0, index) + direction, HAND_PAGES.size())])


func _open_hand_page(page: String) -> void:
	nav_page = page
	if pending_page != "":
		pending_page = page
		_refresh_navigation()
		return
	# Close the native surface before opening another one. Wait for its state
	# acknowledgment rather than issuing two Escape/toggle commands together.
	if hud_state.get("map_open", false) and page != "jump":
		pending_page = page
		_command("navigate", {"screen": "menu"})
	elif hud_state.get("tactical", false) and page != "tactical":
		pending_page = page
		_command("navigate", {"screen": "tactical"})
	elif page == "jump" and not hud_state.get("map_open", false) and _game_actions_available() and hud_state.get("navigation", {}).get("jump", false):
		_command("navigate", {"screen": "jump"})
	elif page == "tactical" and not hud_state.get("tactical", false) and _game_actions_available():
		_command("navigate", {"screen": "tactical"})
	_refresh_navigation()


func _toggle_tactical() -> void:
	if rename_keyboard.visible or not hud_state.get("ready", demo_mode) or hud_state.get("ui_mode", "") == "menu":
		return
	_open_hand_page("navigation" if hud_state.get("tactical", false) else "tactical")


func _toggle_power_page() -> void:
	if rename_keyboard.visible or not hud_state.get("ready", demo_mode) or hud_state.get("ui_mode", "") == "menu":
		return
	_open_hand_page("navigation" if nav_page == "power" else "power")


func _change_system_power(direction: int) -> void:
	if nav_page != "power" or not _game_actions_available():
		return
	var row: Dictionary = panel_theme.selected_system()
	if row.is_empty() or int(row.get("id", -1)) < 0:
		return
	_command("system_power", {"system_id": int(row.id), "system_key": str(row.key),
		"direction": direction, "modifiers": {"shift": false, "control": false}})


func _update_power_controls(remove: bool, previous: bool, next: bool) -> void:
	if nav_page == "power" and _game_actions_available():
		if previous and not power_previous_was_down:
			panel_theme.step_selection(-1)
		if next and not power_next_was_down:
			panel_theme.step_selection(1)
		if remove and not power_remove_was_down:
			_change_system_power(-1)
	power_remove_was_down = remove
	power_previous_was_down = previous
	power_next_was_down = next


func _update_wheel() -> void:
	var down := right_hand.get_is_active() and right_hand.is_button_pressed("wheel_button")
	if down and not wheel_was_down:
		wheel_committed = false
		wheel_dialog_id = str(hud_state.get("dialog", {}).get("id", ""))
		wheel.visible = not rename_keyboard.visible and (hud_state.get("event_open", false) or _game_actions_available())
		_refresh_wheel()
	if wheel.visible:
		if not hud_state.get("event_open", false) and not _game_actions_available():
			wheel_committed = true
			wheel.visible = false
			return
		wheel.global_position = _pointer_ray().from + Vector3(0, 0.17, -0.1)
		_face_front(wheel)
		wheel.choose(right_hand.get_vector2("primary"))
		if wheel_dialog_id != str(hud_state.get("dialog", {}).get("id", "")):
			wheel_committed = true
			wheel.visible = false
	if not down and wheel_was_down:
		if wheel.visible:
			_commit_wheel()
		wheel.visible = false
	wheel_was_down = down


func _refresh_wheel() -> void:
	var entries: Array = []
	if hud_state.get("event_open", false):
		for choice in hud_state.get("dialog", {}).get("choices", []):
			entries.append({"label": "Choice %d" % (int(choice.get("index", 0)) + 1), "choice": choice.get("index", 0), "enabled": choice.get("enabled", true)})
		wheel.set_entries(entries, "EVENT\nCHOICES")
		return
	var player: Dictionary = hud_state.get("player", {})
	if wheel_category == 0:
		entries = ShortcutWheel.equipment_entries(player, int(hud_state.get("drone_slots", 0)))
		wheel.set_entries(entries, "WEAPONS\nDRONES")
	elif wheel_category == 1:
		var systems: Dictionary = player.get("systems", {})
		for item in [["SHIELD", "shields", 97], ["ENGINE", "engines", 115], ["OXYGEN", "oxygen", 102], ["MED/CLONE", "medbay", 100], ["WEAPONS", "weapons", 119], ["DRONES", "drones", 101], ["TELEPORT", "teleporter", 103], ["CLOAK", "cloaking", 104]]:
			entries.append({"label": item[0], "key": item[2], "enabled": systems.get(item[1], false) or (item[1] == "medbay" and systems.get("clonebay", false))})
		wheel.set_entries(entries, "SYSTEM\nPOWER")
	else:
		var systems: Dictionary = player.get("systems", {})
		for item in [["CLOAK", "cloaking", 99], ["SEND", "teleporter", 116], ["RETURN", "teleporter", 114], ["HACK", "hacking", 110], ["MIND", "mind", 109], ["BATTERY", "battery", 98], ["AUTOFIRE", "weapons", 118], ["ALL CREW", "crew", 113]]:
			entries.append({"label": item[0], "key": item[2], "enabled": item[1] == "crew" or systems.get(item[1], false)})
		wheel.set_entries(entries, "SYSTEM\nACTIONS")


func _commit_wheel() -> void:
	if rename_keyboard.visible or (not hud_state.get("event_open", false) and not _game_actions_available()):
		wheel_committed = true
		wheel.visible = false
		return
	if wheel_committed or wheel.selected < 0 or wheel.selected >= wheel.entries.size():
		return
	var entry: Dictionary = wheel.entries[wheel.selected]
	if not entry.get("enabled", true):
		return
	wheel_committed = true
	if entry.has("choice"):
		_command("event_choice", {"index": entry.choice, "dialog_id": wheel_dialog_id})
	else:
		_command("key", {"key": entry.key})
	wheel.visible = false


func _process(delta: float) -> void:
	if world_surface.visible:
		world_panel_open_age += delta
	if not paused:
		elapsed += delta
	state_poll_elapsed += delta
	if state_poll_elapsed >= 0.05:
		state_poll_elapsed = 0.0
		_poll_bridge_state()
	combat_effects.simulation_paused = paused
	player_ship.simulation_paused = paused
	enemy_ship.simulation_paused = paused
	space_environment.simulation_paused = paused
	var viewer := camera.get_camera_transform().origin
	player_ship.set_viewer_position(viewer)
	enemy_ship.set_viewer_position(viewer)
	if xr_active:
		_place_initial_table()
		_resolve_controller_pose(right_hand)
		_resolve_controller_pose(left_hand)
		_update_stable_ray(delta)
		shift_down = _pressed(right_hand, "grip")
		control_down = right_hand.is_button_pressed("primary_click")
		_update_input_diagnostics(delta)
		_face_navigation_to_headset(delta)
		_position_world_panels()
		_update_pointer()
		var ray := _pointer_ray()
		_update_crew_grab(ray.from, ray.direction)
		_update_wheel()
		if wheel.visible:
			right_laser.visible = false
			hover_marker.visible = false
		var trigger_down := right_hand.get_is_active() and _pressed(right_hand, "trigger")
		if trigger_down and not trigger_was_down and wheel.visible:
			_commit_wheel()
		elif trigger_down and not trigger_was_down:
			_select_from_ray(ray.from, ray.direction)
		if not trigger_down and trigger_was_down:
			_release_pointer(ray.from, ray.direction)
		trigger_was_down = trigger_down
		var pause_down := left_hand.is_button_pressed("menu_button")
		if pause_down and not pause_was_down:
			_toggle_pause()
		pause_was_down = pause_down
		var cancel_down := right_hand.is_button_pressed("by_button")
		if cancel_down and not cancel_was_down:
			if wheel.visible:
				wheel_committed = true
				wheel.visible = false
			else:
				_secondary_click(ray.from, ray.direction)
		cancel_was_down = cancel_down
		var inspect_down := right_hand.is_button_pressed("ax_button")
		if inspect_down and not inspect_was_down:
			if wheel.visible and not hud_state.get("event_open", false):
				wheel_category = (wheel_category + 1) % 3
				_refresh_wheel()
			else:
				enemy_ship.inspect_rooms = not enemy_ship.inspect_rooms
				enemy_ship.apply_live(enemy_ship.live_data)
		inspect_was_down = inspect_down
		var frame := _is_frame_hand(left_hand)
		var tactical_down := left_hand.is_button_pressed("tactical_button") if frame else left_hand.is_button_pressed("ax_button") and nav_page != "power"
		if tactical_down and not tactical_was_down:
			_toggle_tactical()
		tactical_was_down = tactical_down
		var power_page_down := left_hand.is_button_pressed("by_button") and (frame or nav_page != "power")
		if power_page_down and not power_page_was_down:
			_toggle_power_page()
		power_page_was_down = power_page_down
		var page_left := left_hand.is_button_pressed("page_left")
		var page_right := left_hand.is_button_pressed("page_right")
		if page_left and not page_left_was_down:
			_cycle_hand_page(-1)
		if page_right and not page_right_was_down:
			_cycle_hand_page(1)
		page_left_was_down = page_left
		page_right_was_down = page_right
		var stations := _pressed(left_hand, "trigger")
		if stations and not station_was_down and _game_actions_available():
			if nav_page == "power":
				_change_system_power(1)
			else:
				_command("key", {"key": 47 if shift_down else 13})
		station_was_down = stations
		_update_power_controls(left_hand.is_button_pressed("power_remove"), right_hand.is_button_pressed("power_previous") if frame else left_hand.is_button_pressed("ax_button"), right_hand.is_button_pressed("power_next") if frame else left_hand.is_button_pressed("by_button"))
		var grip_down := left_hand.get_is_active() and _pressed(left_hand, "grip")
		if grip_down and gripping:
			tabletop_root.global_position += left_hand.global_position - grip_last_position
		gripping = grip_down
		grip_last_position = left_hand.global_position
		var stick := left_hand.get_vector2("primary")
		if stick.length() > 0.2:
			tabletop_root.rotate_y(-stick.x * delta)
			tabletop_root.scale = Vector3.ONE * clampf(tabletop_root.scale.x + stick.y * delta * 0.35, 0.2, 1.5)
		var recenter_down := left_hand.is_button_pressed("primary_click")
		if recenter_down and not recenter_was_down:
			_recenter()
		recenter_was_down = recenter_down
		hover_elapsed += delta
		if hover_elapsed >= 0.12 and not wheel.visible:
			hover_elapsed = 0.0
			_hover_ui(ray.from, ray.direction)
	_position_hud(delta)


func _face_navigation_to_headset(delta: float = 1.0 / 90.0) -> void:
	if not left_hand.get_is_active():
		nav_panel.visible = false
		panel_filter.reset()
		return
	nav_panel.visible = true
	var point := left_hand.to_global(Vector3(0, 0.08, -0.11))
	var toward := camera.get_camera_transform().origin - point
	if toward.length_squared() > 0.00001:
		var up := Vector3.UP if absf(toward.normalized().dot(Vector3.UP)) < 0.98 else camera.get_camera_transform().basis.y
		var target := Transform3D(Basis.looking_at(toward, up, true).scaled(Vector3.ONE * 0.6), point)
		nav_panel.global_transform = panel_filter.update(target, delta)


func _is_frame_hand(hand: XRController3D) -> bool:
	var tracker := XRServer.get_tracker(hand.tracker) as XRControllerTracker
	return tracker != null and "frame_controller" in str(tracker.profile)


func _update_stable_ray(delta: float) -> void:
	if not right_hand.get_is_active():
		ray_filter.reset()
		return
	pointer_transform = ray_filter.update(right_hand.global_transform, delta)


func _pointer_ray() -> Dictionary:
	var pose := pointer_transform if ray_filter.initialized else right_hand.global_transform
	return {"from": pose.origin, "direction": -pose.basis.z.normalized()}


func _update_pointer() -> void:
	if not right_hand.get_is_active():
		right_laser.visible = false
		hover_marker.visible = false
		return
	var ray := _pointer_ray()
	var start: Vector3 = ray.from
	var direction: Vector3 = ray.direction
	var hit := {}
	var keyboard_hit: Dictionary = rename_keyboard.ray_hit(start, direction)
	var hand_hit := {} if rename_keyboard.visible else _hand_panel_hit(start, direction)
	var surface_hit := {} if rename_keyboard.visible else _surface_hit(start, direction)
	# A left-hand power press in this frame must use the card under the visible
	# right-hand ray, rather than waiting for the slower native hover interval.
	var hover_key := str(hand_hit.get("system_key", "")) if nav_page == "power" and not wheel.visible else ""
	if hover_key != power_hover_key:
		power_hover_key = hover_key
		if hover_key != "":
			panel_theme.select_system(hover_key)
	if not keyboard_hit.is_empty():
		hit = keyboard_hit
	elif not hand_hit.is_empty():
		hit = hand_hit
	elif surface_hit.is_empty() and _world_actions_available():
		if grabbed_crew != null:
			hit = _room_hit(start, direction, grab_ship, 0.012)
		elif not _active_target().is_empty():
			hit = _target_room_hit(start, direction)
		if hit.is_empty():
			var query := PhysicsRayQueryParameters3D.create(start, start + direction * 8.0)
			query.collide_with_areas = true
			query.collide_with_bodies = false
			hit = get_world_3d().direct_space_state.intersect_ray(query)
	var end := start + direction * 4.0
	if not hit.is_empty():
		end = hit.get("room_position", hit["position"])
		hover_marker.global_position = end
		hover_marker.visible = true
	else:
		hover_marker.visible = false
	if not surface_hit.is_empty():
		var pixel: Vector2i = surface_hit["pixel"]
		var surface: Node3D = surface_hit["surface"]
		end = surface.pixel_world(pixel)
		hover_marker.global_position = end
		hover_marker.visible = true
	_update_target_feedback(hit if surface_hit.is_empty() and hand_hit.is_empty() and keyboard_hit.is_empty() else {})
	# A thin cylinder is visible in stereo; a one-pixel line can vanish at distance.
	var length := start.distance_to(end)
	right_laser.global_position = (start + end) * 0.5
	if length > 0.001:
		var toward := (end - start).normalized()
		var up := Vector3.UP if absf(toward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var orientation := Basis.looking_at(toward, up) * Basis(Vector3.RIGHT, PI / 2.0)
		right_laser.global_basis = Basis(orientation.x, orientation.y * length, orientation.z)
	right_laser.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not xr_active and event is InputEventWithModifiers:
		shift_down = event.shift_pressed
		control_down = event.ctrl_pressed
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not xr_active:
		_select_from_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not xr_active:
		_release_pointer(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not xr_active:
		_secondary_click(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseMotion and not xr_active:
		_hover_ui(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventKey and event.pressed and (not event.echo or rename_keyboard.visible):
		if rename_keyboard.visible:
			var data := {"entry_id": rename_keyboard.entry.get("id", "")}
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER: data.op = "confirm"
				KEY_ESCAPE: data.op = "cancel"
				KEY_BACKSPACE: data.op = "backspace"
				_:
					if event.unicode < 32:
						return
					data.op = "insert"
					data.text = String.chr(event.unicode)
			_command("text_input", data)
			return
		if not demo_mode:
			if event.keycode == KEY_SPACE:
				_toggle_pause()
			elif event.keycode == KEY_ESCAPE:
				_command("key", {"key": 27})
			elif event.keycode >= KEY_1 and event.keycode <= KEY_8:
				_command("key", {"key": 49 + event.keycode - KEY_1})
			elif event.keycode == KEY_E:
				enemy_ship.inspect_rooms = not enemy_ship.inspect_rooms
				enemy_ship.apply_live(enemy_ship.live_data)
			elif event.keycode == KEY_R:
				_recenter()
			elif event.keycode == KEY_J:
				_command("navigate", {"screen": "jump"})
			elif event.keycode == KEY_F8:
				_command("key", {"key": 289})
			return
		match event.keycode:
			KEY_SPACE:
				_toggle_pause()
			KEY_F:
				battle = not battle
				_update_ship_positions()
				_update_hud()
			KEY_0:
				_set_hazard("clear")
			KEY_1:
				_set_hazard("asteroid")
			KEY_2:
				_set_hazard("sun")
			KEY_3:
				_set_hazard("storm")
			KEY_4:
				_set_hazard("nebula")
			KEY_5:
				_set_hazard("pulsar")
			KEY_ESCAPE:
				crew_selected = false
				_update_hud()
			KEY_T:
				_demo_shot("laser", "player")
			KEY_Y:
				_demo_shot("laser", "enemy")
			KEY_M:
				_demo_shot("missile", "player")
			KEY_I:
				_demo_shot("ion", "player")
			KEY_B:
				_demo_shot("beam", "player")
			KEY_O:
				_demo_shot("bomb", "player")


func _select_from_ray(from: Vector3, direction: Vector3) -> void:
	keyboard_press = false
	var keyboard_hit: Dictionary = rename_keyboard.ray_hit(from, direction)
	if not keyboard_hit.is_empty():
		keyboard_press = true
		var data: Dictionary = rename_keyboard.activate(keyboard_hit)
		if not data.is_empty():
			_command("text_input", data)
		return
	if rename_keyboard.visible:
		return
	var hand_hit := _hand_panel_hit(from, direction)
	if not hand_hit.is_empty() and not hand_hit.has("surface"):
		if hand_hit.has("system_key"):
			panel_theme.select_system(str(hand_hit.system_key))
		elif hand_hit.has("button"):
			_navigation_action(str(hand_hit.button.get_meta("action")))
		return
	var surface_hit := _surface_hit(from, direction)
	if not surface_hit.is_empty():
		held_surface = surface_hit["surface"]
		held_pixel = surface_hit["pixel"]
		_command("ui_mouse", {"x": held_pixel.x, "y": held_pixel.y, "phase": "down"})
		return
	if not bridge_connected and not demo_mode:
		return
	if _world_actions_available() and not _active_target().is_empty():
		var room_hit := _target_room_hit(from, direction)
		if not room_hit.is_empty():
			beam_drag = str(_active_target().kind) == "weapon" and _selected_weapon_is_beam()
			_command("target_room", {"room_id": int(room_hit.room_id), "ship": str(room_hit.ship), "phase": "down" if beam_drag else "click"})
			return
	var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * 12.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Object = hit["collider"]
	if not target.has_meta("kind"):
		return
	if str(target.get_meta("kind")) != "navigation" and not _world_actions_available():
		return
	match str(target.get_meta("kind")):
		"crew":
			if not bool(target.get_meta("controllable", true)):
				return
			crew_selected = true
			crew_id_selected = str(target.get_meta("crew_id"))
			crew_ship_selected = str(target.get_meta("ship"))
			_command("select_crew", {"crew_id": crew_id_selected})
			_begin_crew_grab(target as Node3D, from)
			last_command = "Hold trigger to grab; release over a room to order crew"
		"door":
			if str(target.get_meta("ship", "")) == "player":
				_command("door_toggle", {"door_id": int(target.get_meta("door_id"))})
		"room":
			var ship := str(target.get_meta("ship"))
			var room_id := int(target.get_meta("room_id"))
			if ship == crew_ship_selected and crew_selected:
				_command("move_crew", {"crew_id": crew_id_selected, "room_id": room_id})
			elif not _active_target().is_empty() and ship in _active_target().get("ships", []):
				beam_drag = str(_active_target().kind) == "weapon" and _selected_weapon_is_beam()
				_command("target_room", {"room_id": room_id, "ship": ship, "phase": "down" if beam_drag else "click"})
			else:
				last_command = "%s room %d" % [ship.capitalize(), room_id]
		"navigation":
			_navigation_action(str(target.get_meta("action")))
	_update_hud()


func _command(action: String, data: Dictionary) -> void:
	data = data.duplicate(true)
	data["modifiers"] = {"shift": false, "control": false} if action == "text_input" else data.get("modifiers", {"shift": shift_down, "control": control_down})
	last_command = "%s %s" % [action, JSON.stringify(data)]
	if demo_mode:
		return
	var command := {"action": action, "data": data, "time_unix": Time.get_unix_time_from_system()}
	var output_path := _local_data_path("commands.jsonl")
	var output := FileAccess.open(output_path, FileAccess.READ_WRITE if FileAccess.file_exists(output_path) else FileAccess.WRITE)
	if output != null:
		output.seek_end()
		output.store_line(JSON.stringify(command))
	if action != "ui_move":
		print("FTL_TABLETOP_COMMAND ", JSON.stringify(command))


func _toggle_pause() -> void:
	if rename_keyboard.visible:
		return
	if demo_mode:
		paused = not paused
	else:
		_command("key", {"key": 32})
	_update_hud()


func _update_hud() -> void:
	if hud_surface == null:
		return
	var state := hud_state.duplicate(true)
	var player_paused := bool(hud_state.get("paused", paused if demo_mode else false))
	state.merge({"hull": hull_current, "hull_max": hull_max, "shield": shield_level,
		"reactor": reactor_power, "combat": battle, "paused": player_paused}, true)
	hud_surface.set_state(state)
	# A single live-state cue is shared by both eyes and every native view.
	# Frozen event/store simulation is distinct from the player's pause toggle.
	pause_label.text = "PAUSED" if player_paused else ""
	pause_label.visible = bool(state.get("ready", demo_mode)) and not rename_keyboard.visible and player_paused
	player_ship.set_shields(shield_level, int(state.get("super_shield", 0)))
	enemy_ship.set_shields(int(state.get("enemy_shield", 2)), int(state.get("enemy_super_shield", 0)))
	_sync_hud_layout()
	_position_hud(0.0)


func _demo_shot(kind: String, source: String) -> void:
	if not battle:
		return
	var receiver: Node3D = enemy_ship if source == "player" else player_ship
	var outcome := "shield" if receiver.shield_charge > 0 and kind in ["laser", "ion"] else "hull"
	_present_shot({"kind": kind, "source": source, "weapon_slot": 0, "target_room": 0,
		"end_room": 4, "outcome": outcome, "duration": 0.9})


func _present_shot(event: Dictionary) -> void:
	var source := str(event.get("source", ""))
	if source == "environment":
		var receiver: Node3D = enemy_ship if int(event.get("ship", 0)) == 1 else player_ship
		combat_effects.spawn_shot(event, receiver, receiver)
		return
	if source not in ["player", "enemy"] or (not battle and not event.has("drone_id")):
		return
	if str(event.get("kind", "laser")) not in ["laser", "ion", "missile", "beam", "bomb"]:
		return
	combat_effects.spawn_shot(event, player_ship if source == "player" else enemy_ship,
		enemy_ship if source == "player" else player_ship)


func _poll_bridge_state() -> void:
	if demo_mode:
		return
	var path := _local_data_path("live_state.json")
	if not FileAccess.file_exists(path):
		bridge_connected = false
		return
	var signature := FileAccess.get_sha256(path)
	bridge_connected = Time.get_unix_time_from_system() - float(hud_state.get("bridge_time_unix", 0)) < 2.0
	if signature == state_signature:
		return
	var decoder := JSON.new()
	if decoder.parse(FileAccess.get_file_as_string(path)) != OK or not decoder.data is Dictionary:
		return
	var parsed: Variant = decoder.data
	state_signature = signature
	bridge_connected = true
	var state: Dictionary = parsed
	bridge_connected = Time.get_unix_time_from_system() - float(state.get("bridge_time_unix", 0)) < 2.0
	if not bridge_connected:
		return
	hud_state = state.duplicate(true)
	_apply_text_entry(state.get("text_entry", {}))
	space_environment.apply_state(state)
	var event_open := bool(state.get("event_open", false))
	event_surface.visible = event_open
	var world_was_open: bool = world_surface.visible
	world_surface.visible = bool(state.get("panel_open", false))
	var panel_kind := str(state.get("panel_kind", "window"))
	if world_surface.visible and (not world_was_open or panel_kind != world_panel_kind):
		world_panel_kind = panel_kind
		world_panel_crop_pending = true
		world_panel_open_age = 0.0
		world_panel_opened_at = Time.get_unix_time_from_system()
		world_panel_open_frame_count = world_surface.canvas.received_frames
	if grabbed_crew != null and not _world_actions_available():
		_end_crew_grab()
	event_was_open = event_open
	if event_open:
		event_surface.set_crop(Rect2(313 if state.get("dialog", {}).get("centered", true) else 163, 138, 650, 390), Vector2(0.98, 0.588))
		_face_front(event_surface)
	if pending_page != "" and not state.get("map_open", false) and not state.get("tactical", false):
		var next_page := pending_page
		pending_page = ""
		_open_hand_page(next_page)
	var session := str(state.get("bridge_session", ""))
	var first_state := bridge_session == "" or session != bridge_session
	if session != bridge_session:
		seen_shots.clear()
		bridge_session = session
	weapon_selected = int(state.get("weapon_selected", -1)) >= 0
	crew_selected = false
	for side in ["player", "enemy"]:
		for crew in state.get(side, {}).get("crew", []):
			if crew.get("selected", false) and crew.get("controllable", false):
				crew_selected = true
				crew_id_selected = str(crew["id"])
				crew_ship_selected = side
				break
	player_ship.visible = bool(state.get("ready", false))
	for side in ["player", "enemy"]:
		if state.has(side):
			var ship: Node3D = player_ship if side == "player" else enemy_ship
			var data: Dictionary = state[side]
			if str(data.get("asset_key", "")) != ship.ship_name:
				ship.build(str(data["asset_key"]), side == "enemy")
				if side == "enemy":
					pointed_room = -1
				_update_ship_positions()
			ship.apply_live(data)
	if enemy_hull_bar != null:
		enemy_hull_bar.set_state(state.get("enemy", {}) if state.get("combat", false) else {})
	var map_on_controller := (bool(state.get("map_open", false)) or bool(state.get("tactical", false))) and xr_active
	map_surface.visible = map_on_controller
	hud_surface.visible = true
	hud_surface.canvas.frame_file = "screen_frame.png" if not xr_active and (state.get("map_open", false) or state.get("tactical", false)) else "hud_frame.png"
	map_surface.set_state(state)
	_refresh_navigation()
	var new_battle := bool(state.get("combat", battle))
	if new_battle != battle:
		battle = new_battle
		_update_ship_positions()
	var new_hazard := str(state.get("hazard", hazard))
	if new_hazard in ["clear", "asteroid", "sun", "storm", "nebula", "pulsar"] and new_hazard != hazard:
		_set_hazard(new_hazard)
	paused = bool(state.get("paused", paused)) or bool(state.get("frozen", false))
	hull_current = int(state.get("hull", hull_current))
	hull_max = int(state.get("hull_max", hull_max))
	shield_level = int(state.get("shield", shield_level))
	reactor_power = int(state.get("reactor", reactor_power))
	last_command = "Encounter state updated"
	_update_hud()
	if world_surface != null and rename_keyboard != null:
		_position_world_panels()
	for event in state.get("shots", []):
		if not event is Dictionary or not event.has("id"):
			continue
		var id := str(event["id"])
		if not seen_shots.has(id):
			seen_shots[id] = true
			if first_state:
				var active := false
				for projectile in state.get("projectiles", []):
					if str(projectile["id"]) == str(event.get("projectile_id", "")):
						active = true
				if not active or event.get("phase", "fire") == "impact":
					continue
			if event.get("phase", "fire") == "impact":
				combat_effects.resolve_live(event, enemy_ship if int(event.get("ship", 0)) == 1 else player_ship)
			else:
				_present_shot(event)
	combat_effects.update_live_projectiles(state.get("projectiles", []))


func _apply_text_entry(entry: Dictionary) -> void:
	rename_keyboard.set_entry(entry)
	if rename_keyboard.visible:
		# Native text entry can begin while a previously opened wheel is held.
		# Its eventual release must not send a gameplay shortcut into the name.
		wheel.visible = false
		wheel_committed = true
		beam_drag = false
		if grabbed_crew != null:
			_end_crew_grab()


func _surface_hit(from: Vector3, direction: Vector3) -> Dictionary:
	if rename_keyboard.visible:
		return {}
	var hand_hit := _hand_panel_hit(from, direction)
	if not hand_hit.is_empty():
		return hand_hit if hand_hit.has("surface") else {}
	var closest := {}
	var closest_distance := INF
	for surface in [hud_surface, world_surface, event_surface, map_surface]:
		var pixel: Variant = surface.ray_pixel(from, direction)
		if pixel != null:
			# Hand UI has already won. HUD pixels win over world panels.
			if surface == hud_surface:
				return {"surface": surface, "pixel": pixel}
			var point: Vector3 = surface.pixel_world(pixel)
			var distance := from.distance_to(point)
			if distance < closest_distance:
				closest_distance = distance
				closest = {"surface": surface, "pixel": pixel}
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 12.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"].get_meta("kind", "") == "navigation" and from.distance_to(hit["position"]) < closest_distance:
		return {}
	return closest


func _hand_panel_hit(from: Vector3, direction: Vector3) -> Dictionary:
	if not nav_panel.is_visible_in_tree():
		return {}
	# The native Tactical quad is in front of the themed panel. Pick each
	# actual display plane; a shared plane shifts oblique controller rays.
	if map_surface.get_parent() == nav_panel:
		var native_pixel: Variant = map_surface.ray_pixel(from, direction)
		if native_pixel != null:
			return {"position": map_surface.pixel_world(native_pixel), "surface": map_surface, "pixel": native_pixel}
	var start := nav_panel.to_local(from)
	var ray := nav_panel.to_local(from + direction) - start
	if absf(ray.z) < 0.00001:
		return {}
	var distance := (0.012 - start.z) / ray.z
	if distance <= 0.0:
		return {}
	var point := start + distance * ray
	if absf(point.x) > 0.46 or absf(point.y) > 0.36:
		return {}
	var result := {"position": nav_panel.to_global(point)}
	if nav_page == "power":
		var power_hit: Dictionary = panel_theme.ray_hit(from, direction)
		if not power_hit.is_empty():
			return power_hit
		return result
	for button in nav_buttons:
		if button.visible and Rect2(Vector2(button.position.x - 0.20, button.position.y - 0.0335), Vector2(0.40, 0.067)).has_point(Vector2(point.x, point.y)):
			result.button = button
			return result
	return result


func _update_target_feedback(hit: Dictionary) -> void:
	var target := _active_target()
	var id := int(hit.get("room_id", -1)) if not target.is_empty() and grabbed_crew == null else -1
	var side := str(hit.get("ship", "")) if id >= 0 else ""
	if id != pointed_room or side != pointed_ship:
		player_ship.set_drop_target(id if side == "player" else -1)
		enemy_ship.set_drop_target(id if side == "enemy" else -1)
		pointed_room = id
		pointed_ship = side
	target_room_label.visible = id >= 0
	if id >= 0:
		var ship: Node3D = player_ship if side == "player" else enemy_ship
		var role := str(ship.room_nodes[id].get_meta("system_role", ""))
		var kind := str(target.get("kind", "weapon"))
		target_room_label.text = ("TARGET" if kind == "weapon" else kind.to_upper()) + " • " + (role.to_upper() if role != "" else "ROOM")
		target_room_label.global_position = hit.position + Vector3(0, 0.045, 0)
		_face_front(target_room_label)


func _pressed(hand: XRController3D, action: String) -> bool:
	return hand.is_button_pressed(action + "_click") or hand.get_float(action) > 0.65


func _resolve_controller_pose(hand: XRController3D) -> void:
	var tracker := XRServer.get_tracker(hand.tracker) as XRPositionalTracker
	if tracker == null:
		return
	for name in ["aim", "default", "grip"]:
		if tracker.has_pose(name) and tracker.get_pose(name).has_tracking_data:
			hand.pose = name
			return


func _update_input_diagnostics(delta: float) -> void:
	diagnostics_elapsed += delta
	var status := ""
	if not right_hand.get_is_active():
		status = "RIGHT CONTROLLER NOT TRACKED — check SteamVR controller status"
	elif shift_down or control_down:
		status = ("SHIFT " if shift_down else "") + ("CTRL" if control_down else "")
	if status != tracking_label.text:
		tracking_label.text = status
	if diagnostics_elapsed < 1.0:
		return
	diagnostics_elapsed = 0.0
	var hands := {}
	for hand in [left_hand, right_hand]:
		var tracker := XRServer.get_tracker(hand.tracker) as XRPositionalTracker
		hands[str(hand.tracker)] = {"tracked": hand.get_is_active(), "pose": str(hand.pose),
			"profile": str(tracker.profile) if tracker != null else "missing",
			"trigger": hand.get_float("trigger"), "trigger_click": hand.is_button_pressed("trigger_click"),
			"grip": hand.get_float("grip"), "grip_click": hand.is_button_pressed("grip_click")}
	var info := {"hands": hands, "ray_visible": right_laser.visible, "shift": shift_down,
		"control": control_down, "time_unix": Time.get_unix_time_from_system()}
	var file := FileAccess.open(_local_data_path("xr_input.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(info))
	var signature := JSON.stringify(hands)
	if signature != diagnostics_signature:
		print("FTLVR_XR_INPUT ", signature)
		diagnostics_signature = signature


func _navigation_action(action: String) -> void:
	if action.begins_with("page:"):
		_open_hand_page(action.trim_prefix("page:"))
	elif action.begins_with("key:"):
		_command("key", {"key": int(action.trim_prefix("key:"))})
	elif action == "recenter":
		_recenter()
	else:
		_command("navigate", {"screen": action})


func _navigation_entries() -> Array:
	var entries: Array = []
	var game := _game_actions_available()
	if nav_page == "power":
		return []
	if map_surface.visible:
		return [["CLOSE MAP" if hud_state.get("map_open", false) else "CLOSE TACTICAL",
			"menu" if hud_state.get("map_open", false) else "tactical"], ["HELP", "page:help"]]
	if nav_page == "help":
		return [["BACK", "page:navigation"]]
	if nav_page == "navigation":
		if game:
			for name in ["jump", "ship", "store"]:
				if hud_state.get("navigation", {}).get(name, false):
					entries.append([name.to_upper(), name])
			entries.append(["SHORTCUTS", "page:shortcuts"])
			entries.append(["SYSTEM POWER", "page:power"])
			entries.append(["TACTICAL VIEW", "tactical"])
		entries.append(["MENU / BACK", "menu"])
		entries.append(["CONTROLS / HELP", "page:help"])
		entries.append(["RECENTER", "recenter"])
		return entries
	if not game:
		return [["BACK", "page:navigation"]]
	if nav_page == "jump":
		return [["OPEN JUMP MAP", "jump"], ["BACK", "page:navigation"]] if hud_state.get("navigation", {}).get("jump", false) else [["JUMP UNAVAILABLE", "page:navigation"]]
	if nav_page == "shortcuts":
		return [["CREW / DOORS", "page:crew"], ["WEAPONS / DRONES", "page:weapons"],
			["SYSTEM POWER", "page:power"], ["SYSTEM ACTIONS", "page:systems"],
			["BACK", "page:navigation"], ["CONTROLS / HELP", "page:help"]]
	if nav_page == "crew":
		entries = [["ALL CREW (Q)", "key:113"], ["SAVE STATIONS (/)", "key:47"],
			["RETURN (ENTER)", "key:13"], ["OPEN DOORS (Z)", "key:122"], ["CLOSE DOORS (X)", "key:120"]]
	elif nav_page == "weapons":
		for i in range(hud_state.get("player", {}).get("weapons", []).size()):
			entries.append(["WEAPON %d (%d)" % [i + 1, i + 1], "key:%d" % (49 + i)])
		for i in range(int(hud_state.get("drone_slots", 0))):
			entries.append(["DRONE %d (%d)" % [i + 1, (i + 5) % 10], "key:%d" % (48 + ((i + 5) % 10))])
		entries.append(["AUTOFIRE (V)", "key:118"])
	else:
		var systems: Dictionary = hud_state.get("player", {}).get("systems", {})
		var keys := {"cloaking":[["CLOAK (C)",99]],"teleporter":[["SEND (T)",116],["RETURN (R)",114]],
			"hacking":[["HACK (N)",110]],"mind":[["MIND CONTROL (M)",109]],"battery":[["BATTERY (B)",98]]}
		for name in keys:
			if systems.get(name, false):
				for entry in keys[name]:
					entries.append([entry[0], "key:%d" % entry[1]])
	entries.append(["BACK", "page:shortcuts"])
	entries.append(["CONTROLS / HELP", "page:help"])
	return entries


func _refresh_navigation() -> void:
	if map_surface == null:
		return
	map_surface.visible = xr_active and nav_page != "help" and (hud_state.get("map_open", false) or hud_state.get("tactical", false))
	if hud_state.get("map_open", false):
		if map_surface.get_parent() != self:
			map_surface.reparent(self, false)
		map_surface.scale = Vector3.ONE
		map_surface.set_render_order(45)
		map_surface.set_crop(Rect2(335, 80, 760, 590), Vector2(1.02, 1.02 * 590.0 / 760.0))
	else:
		if map_surface.get_parent() != nav_panel:
			map_surface.reparent(nav_panel, false)
		map_surface.position = Vector3(0, 0.03, 0.045)
		map_surface.rotation = Vector3.ZERO
		map_surface.scale = Vector3.ONE * 0.3
		map_surface.set_render_order(122)
		map_surface.set_crop(Rect2(0, 0, 1280, 720), HudSurface.SURFACE_SIZE)
	help_label.visible = nav_page == "help"
	nav_title.text = ("JUMP MAP" if hud_state.get("map_open", false) else "TACTICAL VIEW") if map_surface.visible else nav_page.to_upper()
	var heading: String = nav_title.text
	if bool(hud_state.get("paused", false)):
		nav_title.text += " • PAUSED"
	var entries := _navigation_entries()
	var themed_buttons: Array = []
	for i in range(nav_buttons.size()):
		var button := nav_buttons[i]
		button.visible = i < entries.size()
		button.collision_layer = 1 if button.visible else 0
		button.get_child(0).set_deferred("disabled", not button.visible)
		if button.visible:
			button.set_meta("action", entries[i][1])
			button.get_child(1).text = entries[i][0]
			button.position.y = -0.29 if (map_surface.visible and map_surface.get_parent() == nav_panel) or help_label.visible else 0.235 - floori(i / 2.0) * 0.08
			themed_buttons.append({"label": entries[i][0], "position": Vector2(button.position.x, button.position.y), "enabled": true})
	if nav_page == "power":
		panel_theme.set_power(hud_state.get("player", {}), bool(hud_state.get("paused", false)))
	else:
		panel_theme.set_navigation(heading, themed_buttons, bool(hud_state.get("paused", false)))
	if world_surface != null and rename_keyboard != null:
		_position_world_panels()


func _hover_ui(from: Vector3, direction: Vector3) -> void:
	if keyboard_press or rename_keyboard.visible:
		return
	if nav_page == "power" and _game_actions_available():
		# Local card hover is handled before power buttons every frame. A
		# stationary ray must not undo a system selected with X/Y.
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_hover_time < 0.1:
		return
	last_hover_time = now
	var hit := _surface_hit(from, direction)
	if not hit.is_empty():
		var pixel: Vector2i = hit["pixel"]
		_command("ui_move", {"x": pixel.x, "y": pixel.y})


func _release_pointer(from: Vector3, direction: Vector3) -> void:
	if keyboard_press:
		keyboard_press = false
		return
	if grabbed_crew != null:
		_update_crew_grab(from, direction)
		if grab_room >= 0:
			# The initial selection may still be queued in FTL. If the bridge
			# repeats that selection, retain the press-time Shift grouping.
			_command("move_crew", {"crew_id": grab_crew_id, "room_id": grab_room,
				"modifiers": {"shift": grab_shift_down, "control": control_down}})
		_end_crew_grab()
		return
	if held_surface != null:
		var pixel: Variant = held_surface.ray_pixel(from, direction)
		if pixel != null:
			held_pixel = pixel
		_command("ui_mouse", {"x": held_pixel.x, "y": held_pixel.y, "phase": "up"})
		held_surface = null
	if beam_drag:
		var hit := _room_hit(from, direction, "enemy", 0.012)
		if not hit.is_empty() and _surface_hit(from, direction).is_empty() and _hand_panel_hit(from, direction).is_empty() and rename_keyboard.ray_hit(from, direction).is_empty():
			_command("target_room", {"room_id": int(hit.room_id), "ship": "enemy", "phase": "up"})
		else:
			_command("cancel", {})
		beam_drag = false


func _secondary_click(from: Vector3, direction: Vector3) -> void:
	if rename_keyboard.visible:
		_command("text_input", {"entry_id": rename_keyboard.entry.get("id", ""), "op": "cancel"})
		return
	_end_crew_grab()
	var hit := _surface_hit(from, direction)
	if not hit.is_empty():
		var pixel: Vector2i = hit["pixel"]
		_command("ui_mouse", {"x": pixel.x, "y": pixel.y, "button": "right"})
	else:
		_command("cancel", {})
	crew_selected = false
	crew_id_selected = ""


func _selected_weapon_is_beam() -> bool:
	var slot := int(hud_state.get("weapon_selected", -1))
	var weapons: Array = hud_state.get("player", {}).get("weapons", [])
	return slot >= 0 and slot < weapons.size() and str(weapons[slot].get("kind", "")).to_lower() == "beam"


func _active_target() -> Dictionary:
	var targeting: Dictionary = hud_state.get("targeting", {})
	if targeting.get("active", false):
		return targeting
	if not hud_state.has("targeting") and weapon_selected and battle:
		return {"active": true, "kind": "weapon", "ships": ["enemy"]}
	return {}


func _target_room_hit(from: Vector3, direction: Vector3) -> Dictionary:
	var closest := {}
	for side in _active_target().get("ships", ["enemy"]):
		var hit := _room_hit(from, direction, str(side), 0.012)
		if not hit.is_empty() and (closest.is_empty() or hit.distance < closest.distance):
			closest = hit
	return closest


func _begin_crew_grab(crew: Node3D, from: Vector3) -> void:
	_end_crew_grab()
	grabbed_crew = crew
	grab_ship = str(crew.get_meta("ship", "player"))
	grab_crew_id = str(crew.get_meta("crew_id"))
	grab_shift_down = shift_down
	grab_distance = clampf(from.distance_to(crew.global_position), 0.08, 3.0)
	# This is a visual preview. The native crew remains at its real position and
	# walks normally after the drop order; moving the hand never teleports it.
	crew_preview = crew.duplicate() as Node3D
	crew_preview.set_process(false)
	crew_preview.set_physics_process(false)
	_disable_preview_collisions(crew_preview)
	add_child(crew_preview)
	crew_preview.global_transform = crew.global_transform
	grab_label.visible = true
	grab_label.text = "GRAB • release over a room\nB: cancel"


func _disable_preview_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is CollisionShape3D:
		node.disabled = true
	for child in node.get_children():
		_disable_preview_collisions(child)


func _room_hit(from: Vector3, direction: Vector3, side: String = "", margin: float = 0.0) -> Dictionary:
	var closest := {}
	for ship in [player_ship, enemy_ship]:
		if not ship.is_visible_in_tree() or (side != "" and side != ("enemy" if ship == enemy_ship else "player")):
			continue
		var hit: Dictionary = ship.room_ray_hit(from, direction, margin)
		if not hit.is_empty() and (closest.is_empty() or hit.distance < closest.distance):
			closest = hit
	return closest


func _update_crew_grab(from: Vector3, direction: Vector3) -> void:
	if grabbed_crew == null:
		return
	if not is_instance_valid(grabbed_crew):
		_end_crew_grab()
		return
	grab_room = -1
	var hit := _room_hit(from, direction, grab_ship, 0.012)
	var drop_ship: Node3D = player_ship if grab_ship == "player" else enemy_ship
	var point := from + direction * grab_distance
	if not hit.is_empty() and _surface_hit(from, direction).is_empty() and _hand_panel_hit(from, direction).is_empty() and rename_keyboard.ray_hit(from, direction).is_empty():
		grab_room = int(hit["collider"].get_meta("room_id"))
		point = hit.get("room_position", hit["position"]) + drop_ship.global_basis.y.normalized() * 0.025
		var role := str(drop_ship.room_nodes[grab_room].get_meta("system_role", ""))
		grab_label.text = "DROP • %s\nRelease trigger • B: cancel" % (role.to_upper() if role != "" else "ROOM")
	else:
		grab_label.text = "GRAB • aim at a room on this ship\nRelease to keep selection • B: cancel"
	if drop_ship.has_method("set_drop_target"):
		drop_ship.set_drop_target(grab_room)
	crew_preview.global_position = point
	grab_label.global_position = point + Vector3(0, 0.08, 0)
	_face_front(grab_label)


func _end_crew_grab() -> void:
	for ship in [player_ship, enemy_ship]:
		if ship != null and ship.has_method("set_drop_target"):
			ship.set_drop_target(-1)
	if is_instance_valid(crew_preview):
		crew_preview.queue_free()
	crew_preview = null
	grabbed_crew = null
	grab_crew_id = ""
	grab_room = -1
	if grab_label != null:
		grab_label.visible = false


func _recenter() -> void:
	tabletop_root.transform = Transform3D.IDENTITY
	tabletop_root.scale = Vector3.ONE * 0.35
	if xr_active:
		var head := camera.get_camera_transform().origin
		# Local/head-relative XR spaces can put the head at Y=0. There is no
		# virtual floor, so keep the ship below the head in either reference space.
		var forward := -camera.get_camera_transform().basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			forward = forward.normalized()
			tabletop_root.global_position = head + forward * 0.85 - Vector3(0, 0.95, 0)
			tabletop_root.rotation.y = atan2(-forward.x, -forward.z)
		else:
			tabletop_root.global_position = head + Vector3(0, -0.95, -0.85)
	else:
		tabletop_root.position.y = 0.7
	hud_anchor.reset()
	_position_hud(0.0, true)


func _local_data_path(file_name: String) -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://local_game_data/%s" % file_name)
	return OS.get_executable_path().get_base_dir().path_join("local_game_data").path_join(file_name)


func _set_hazard(kind: String) -> void:
	hazard = kind
	space_environment.set_hazard(kind)
	if hud_surface != null:
		_update_hud()


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _emissive(color: Color, strength: float) -> StandardMaterial3D:
	var mat := _material(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = strength
	return mat
