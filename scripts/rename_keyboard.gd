extends Node3D

# One rendered surface, with geometric key picking. Text remains authoritative
# in FTL; the keyboard only forwards scoped native text events.
const SIZE := Vector2(0.86, 0.39)
const PIXELS := Vector2(1000, 454)
const UI = preload("res://scripts/ftl_ui_theme.gd")
var entry: Dictionary = {}
var upper := true
var keys: Array = []
var viewport: SubViewport
var canvas: Control
var title: Label
var value_label: Label
var hint: Label


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(PIXELS)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = Control.new()
	canvas.size = PIXELS
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var background := ColorRect.new()
	background.size = PIXELS
	background.color = UI.DARK
	canvas.add_child(background)
	title = _label(Vector2(20, 5), 29, "RENAME")
	title.add_theme_font_override("font",UI.ASSETS.font("header"))
	value_label = _label(Vector2(20, 44), 38, "")
	hint = _label(Vector2(20, 417), 28, "Right trigger: type     B: cancel     Native name length applies")
	var rows := ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM-_"]
	for row in range(rows.size()):
		var line: String = rows[row]
		var left := (PIXELS.x - line.length() * 94.0) * 0.5
		for column in range(line.length()):
			_key(Rect2(left + column * 94.0, 100 + row * 61, 88, 55), line[column], "insert", line[column])
	_key(Rect2(30, 350, 100, 58), "SHIFT", "shift", "")
	_key(Rect2(140, 350, 230, 58), "SPACE", "insert", " ")
	_key(Rect2(380, 350, 100, 58), "CLEAR", "clear", "")
	_key(Rect2(490, 350, 140, 58), "BACK", "backspace", "")
	_key(Rect2(640, 350, 150, 58), "CANCEL", "cancel", "")
	_key(Rect2(800, 350, 170, 58), "DONE", "confirm", "")
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	mesh.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 124
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = viewport.get_texture()
	mesh.material_override = material
	add_child(mesh)
	visible = false


func _label(point: Vector2, font_size: int, text: String) -> Label:
	var label := Label.new()
	label.position = point
	label.add_theme_font_override("font",UI.ASSETS.font("body"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",UI.INK)
	label.text = text
	canvas.add_child(label)
	return label


func _key(rect: Rect2, text: String, op: String, character: String) -> void:
	var plate := Panel.new()
	plate.position = rect.position
	plate.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = UI.PANEL if op != "confirm" else UI.SELECTED
	style.border_color = UI.EDGE if op != "confirm" else UI.GREEN
	style.set_border_width_all(1)
	plate.add_theme_stylebox_override("panel",style)
	canvas.add_child(plate)
	var label := _label(rect.position + Vector2(0,4),32,text)
	label.size = rect.size - Vector2(0, 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.append({"rect": rect, "op": op, "text": character, "label": label})


func set_entry(value: Dictionary) -> void:
	if value == entry:
		return
	var first := str(value.get("id", "")) != str(entry.get("id", ""))
	entry = value.duplicate(true)
	visible = bool(entry.get("active", false))
	if first:
		upper = true
		_update_case()
	title.text = "RENAME %s" % str(entry.get("kind", "NAME")).to_upper()
	var text := str(entry.get("text", ""))
	var cursor := clampi(int(entry.get("cursor", text.length())), 0, text.length())
	value_label.text = text.substr(0, cursor) + "|" + text.substr(cursor)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_case() -> void:
	for key in keys:
		if key.op == "insert" and key.text != " ":
			key.label.text = str(key.text).to_upper() if upper else str(key.text).to_lower()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func ray_hit(from: Vector3, direction: Vector3) -> Dictionary:
	if not is_visible_in_tree():
		return {}
	var start := to_local(from)
	var ray := to_local(from + direction) - start
	if absf(ray.z) < 0.00001:
		return {}
	var distance := -start.z / ray.z
	if distance <= 0:
		return {}
	var local_point := start + ray * distance
	var pixel := Vector2(local_point.x / SIZE.x + 0.5, 0.5 - local_point.y / SIZE.y) * PIXELS
	if not Rect2(Vector2.ZERO, PIXELS).has_point(pixel):
		return {}
	var hit := {"position": to_global(local_point), "op": ""}
	for key in keys:
		if key.rect.has_point(pixel):
			hit.op = key.op
			hit.text = str(key.text).to_upper() if upper else str(key.text).to_lower()
			break
	return hit


func activate(hit: Dictionary) -> Dictionary:
	if hit.get("op", "") == "shift":
		upper = not upper
		_update_case()
		return {}
	if hit.get("op", "") == "":
		return {}
	return {"entry_id": entry.get("id", ""), "op": hit.op, "text": hit.get("text", "")}
