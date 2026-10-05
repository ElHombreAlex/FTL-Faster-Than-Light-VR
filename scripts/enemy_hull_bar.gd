extends Node3D

const UI = preload("res://scripts/ftl_ui_theme.gd")
const WIDTH := 0.64
const HEIGHT := 0.10
const PIXELS := Vector2i(770,130)
const HULL_COLOR := Color("85ff79")
const FILL_RECT := Rect2(34, 0, 720, 130)
static var native_contour: Texture2D
var viewport: SubViewport
var canvas: Control
var plate: MeshInstance3D
var hull := 0
var hull_max := 0
var ship_label := "HOSTILE"
var signature := ""


func build() -> void:
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw)
	viewport.add_child(canvas)
	plate = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	plate.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)
	visible = false


func set_state(data: Dictionary) -> void:
	hull = maxi(0, int(data.get("hull", 0)))
	hull_max = maxi(0, int(data.get("hull_max", 0)))
	ship_label = str(data.get("name", "HOSTILE")).to_upper()
	if ship_label.is_empty():
		ship_label = "HOSTILE"
	visible = not data.is_empty() and hull_max > 0 and not bool(data.get("destroyed", false))
	var next := "%d:%d:%s" % [hull, hull_max, ship_label]
	if next == signature:
		return
	signature = next
	canvas.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func face_viewer(viewer: Vector3) -> void:
	if visible and global_position.distance_squared_to(viewer) > 0.0001:
		look_at(viewer, Vector3.UP, true)


func _draw() -> void:
	var fraction := clampf(float(hull) / maxf(hull_max, 1), 0.0, 1.0)
	var frame := UI.ASSETS.texture("img/statusUI/top_hull_red.png" if fraction <= .33 else "img/statusUI/top_hull.png")
	var mask := _hull_contour()
	var label := UI.ASSETS.texture("img/statusUI/top_hull_red_label.png" if fraction <= .33 else "img/statusUI/top_hull_label.png")
	# Keep the owner's native stepped contour, but one pip means one hit point.
	# The player mask's fixed thirty separators are replaced by hull_max cells.
	if frame != null and mask != null and label != null:
		var source_size := mask.get_size()
		for i in range(hull_max):
			var cell := hull_cell_rect(i)
			var source := Rect2((cell.position - FILL_RECT.position) * source_size / FILL_RECT.size,
				cell.size * source_size / FILL_RECT.size)
			canvas.draw_texture_rect_region(mask, cell, source,
				(HULL_COLOR if fraction > .33 else UI.RED) if i < hull else Color("253b32"))
		canvas.draw_texture_rect(frame,Rect2(0,0,770,130),false)
		canvas.draw_texture_rect(label,Rect2(18,0,104,56),false)
	else:
		# Missing owned art still leaves a readable small bar during setup.
		var outline := PackedVector2Array([Vector2(16,80),Vector2(16,42),Vector2(255,42),Vector2(267,32),Vector2(496,32),Vector2(506,24),Vector2(755,24),Vector2(755,80),Vector2(16,80)])
		canvas.draw_colored_polygon(outline,UI.DARK)
		canvas.draw_polyline(outline,UI.EDGE,2)
		for i in range(hull_max):
			var cell := hull_cell_rect(i)
			canvas.draw_rect(Rect2(cell.position.x,52,cell.size.x,22),
				(HULL_COLOR if fraction > .33 else UI.RED) if i < hull else Color("253b32"))
	UI.text(canvas,"HULL",Vector2(28,4),29,UI.DARK,"header")
	UI.text(canvas,"%d / %d" % [hull,hull_max],Vector2(639,0),28,UI.INK)


func hull_cell_rect(index: int) -> Rect2:
	var width := FILL_RECT.size.x / maxf(hull_max, 1)
	var gap := minf(3.0, width * 0.18)
	return Rect2(FILL_RECT.position + Vector2(index * width, 0), Vector2(width - gap, FILL_RECT.size.y))


static func _hull_contour() -> Texture2D:
	if native_contour != null:
		return native_contour
	var mask := UI.ASSETS.texture("img/statusUI/top_hull_bar_mask.png")
	if mask == null:
		return null
	var image := mask.get_image()
	if image == null or image.is_empty():
		return null
	# Fill the mask's old gaps row by row, retaining its native alpha boundary.
	# This is cached once and does not alter the shared owner-local texture.
	for y in range(image.get_height()):
		var left := image.get_width()
		var right := -1
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				left = mini(left, x)
				right = maxi(right, x)
		for x in range(left, right + 1):
			image.set_pixel(x, y, Color.WHITE)
	native_contour = ImageTexture.create_from_image(image)
	return native_contour
