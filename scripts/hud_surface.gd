extends Node3D

const HudCanvas = preload("res://scripts/hud_canvas.gd")
var canvas: Control
var viewport: SubViewport
var timer := 0.0
var frame_file := "hud_frame.png"
var render_order := 0
var source_rect := Rect2(0, 0, 1280, 720)
var surface_size := Vector2(2.85, 1.603125)
var quad: QuadMesh
var mesh_instance: MeshInstance3D
const SURFACE_SIZE := Vector2(2.85, 1.603125)


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.size_2d_override = Vector2i(1280, 720)
	viewport.size_2d_override_stretch = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = HudCanvas.new()
	canvas.frame_file = frame_file
	canvas.source_rect = source_rect
	canvas.size = Vector2(1280, 720)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.base_path = ProjectSettings.globalize_path("res://local_game_data") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("local_game_data")
	viewport.add_child(canvas)
	canvas.texture_changed.connect(_request_update)
	var mesh := MeshInstance3D.new()
	mesh_instance = mesh
	quad = QuadMesh.new()
	quad.size = surface_size
	mesh.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = render_order
	material.albedo_texture = viewport.get_texture()
	mesh.material_override = material
	add_child(mesh)


func set_state(state: Dictionary) -> void:
	canvas.set_state(state)


func set_render_order(value: int) -> void:
	render_order = value
	if mesh_instance != null:
		mesh_instance.material_override.render_priority = value


func _request_update() -> void:
	# Tactical is reduced; the same stream carries the full-resolution jump
	# map, whose small labels must retain their native rendering resolution.
	var dimensions := Vector2i(1280, 720)
	if canvas.frame_file == "screen_frame.png" and canvas.frame_image != null:
		dimensions = canvas.frame_image.get_size()
	if viewport.size != dimensions:
		viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func ray_pixel(from: Vector3, direction: Vector3) -> Variant:
	if not is_visible_in_tree() or canvas.frame_image == null:
		return null
	var local_from := to_local(from)
	var local_end := to_local(from + direction)
	var local_direction := local_end - local_from
	if absf(local_direction.z) < 0.00001:
		return null
	var distance := -local_from.z / local_direction.z
	if distance <= 0.0:
		return null
	var point := local_from + distance * local_direction
	var uv := Vector2(point.x / surface_size.x + 0.5, 0.5 - point.y / surface_size.y)
	if uv.x < 0.0 or uv.x >= 1.0 or uv.y < 0.0 or uv.y >= 1.0:
		return null
	var native := source_rect.position + uv * source_rect.size
	var pixel := Vector2i(clampi(roundi(native.x), maxi(0, ceili(source_rect.position.x)), mini(1279, ceili(source_rect.end.x) - 1)), clampi(roundi(native.y), maxi(0, ceili(source_rect.position.y)), mini(719, ceili(source_rect.end.y) - 1)))
	if canvas.native_alpha_at(pixel) < 0.1:
		return null
	return pixel


func pixel_world(pixel: Vector2i) -> Vector3:
	var uv := (Vector2(pixel) - source_rect.position) / source_rect.size
	return to_global(Vector3((uv.x - 0.5) * surface_size.x, (0.5 - uv.y) * surface_size.y, 0.01))


func set_crop(rect: Rect2, dimensions: Vector2) -> void:
	if source_rect == rect and surface_size == dimensions:
		return
	source_rect = rect
	surface_size = dimensions
	quad.size = dimensions
	canvas.source_rect = rect
	canvas.request_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	timer += delta
	if timer >= 1.0 / 60.0:
		timer = fmod(timer, 1.0 / 60.0)
		canvas.poll_original_frame()
