extends Node3D

const UI = preload("res://scripts/ftl_ui_theme.gd")
const WIDTH := 0.64
const HEIGHT := 0.10
const PIXELS := Vector2i(770,130)
const HULL_COLOR := Color("85ff79")
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
	var mask := UI.ASSETS.texture("img/statusUI/top_hull_bar_mask.png")
	var label := UI.ASSETS.texture("img/statusUI/top_hull_red_label.png" if fraction <= .33 else "img/statusUI/top_hull_label.png")
	# Use the actual vanilla stepped contour and segmented mask. Only owner-local
	# textures are read; no FTL imagery is embedded in the distributable mod.
	if frame != null and mask != null and label != null:
		canvas.draw_texture_rect(mask,Rect2(34,0,720,130),false,Color("253b32"))
		if fraction > 0:
			canvas.draw_texture_rect_region(mask,Rect2(34,0,720 * fraction,130),Rect2(0,0,360 * fraction,65),HULL_COLOR if fraction > .33 else UI.RED)
		canvas.draw_texture_rect(frame,Rect2(0,0,770,130),false)
		canvas.draw_texture_rect(label,Rect2(18,0,104,56),false)
	else:
		# Missing owned art still leaves a readable small bar during setup.
		var outline := PackedVector2Array([Vector2(16,80),Vector2(16,42),Vector2(255,42),Vector2(267,32),Vector2(496,32),Vector2(506,24),Vector2(755,24),Vector2(755,80),Vector2(16,80)])
		canvas.draw_colored_polygon(outline,UI.DARK)
		canvas.draw_polyline(outline,UI.EDGE,2)
		for i in range(30):
			canvas.draw_rect(Rect2(26 + i * 24,52,21,22),HULL_COLOR if float(i) / 30 < fraction else Color("253b32"))
	UI.text(canvas,"HULL",Vector2(28,4),29,UI.DARK,"header")
	UI.text(canvas,"%d / %d" % [hull,hull_max],Vector2(639,0),28,UI.INK)
