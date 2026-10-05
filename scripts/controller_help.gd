extends Node3D

const UI = preload("res://scripts/ftl_ui_theme.gd")

# An original vector schematic, rendered once. It labels the active bindings
# rather than reproducing controller industrial design or extracted artwork.
var surface_size := Vector2(0.88, 0.53)
var render_priority := 122
var viewport: SubViewport
var canvas: Control


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = HelpCanvas.new()
	canvas.size = Vector2(1000, 600)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var display := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = surface_size
	display.mesh = quad
	display.position.y = 0.03
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = render_priority
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = viewport.get_texture()
	display.material_override = material
	add_child(display)


class HelpCanvas extends Control:
	const INK := UI.INK
	const GREEN := UI.GREEN
	const MUTED := UI.MUTED
	const DARK := UI.DARK
	var font: Font = UI.ASSETS.font("body")


	func _label(value: String, at: Vector2, font_size: int = 20, color: Color = INK) -> void:
		draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1.0,roundi(font_size * 1.45),color)


	func _leader(pin: Vector2, edge: Vector2, channel_x: float) -> void:
		var points := PackedVector2Array([pin, Vector2(channel_x, pin.y), Vector2(channel_x, edge.y), edge])
		draw_polyline(points, MUTED, 2.0, true)
		draw_circle(pin, 4.0, GREEN)


	func _callout(title: String, lines: Array, at: Vector2, pin: Vector2, left_side: bool) -> void:
		_label(title, at, 20, GREEN)
		for i in range(lines.size()):
			_label(str(lines[i]), at + Vector2(0, 22 * (i + 1)), 19)
		var edge := Vector2(199 if left_side else 771, at.y + 5)
		_leader(pin, edge, 210 if left_side else 750)


	func _controller(center_x: float, right: bool) -> void:
		var outline := PackedVector2Array([
			Vector2(center_x - 67, 153), Vector2(center_x - 52, 136),
			Vector2(center_x - 24, 124), Vector2(center_x + 31, 132),
			Vector2(center_x + 61, 152), Vector2(center_x + 72, 202),
			Vector2(center_x + 44, 241), Vector2(center_x + 38, 321),
			Vector2(center_x + 20, 350), Vector2(center_x - 23, 350),
			Vector2(center_x - 43, 320), Vector2(center_x - 46, 240),
			Vector2(center_x - 68, 199)])
		draw_colored_polygon(outline, Color(0.065, 0.125, 0.139))
		var border := outline.duplicate()
		border.append(outline[0])
		draw_polyline(border, INK, 3.0, true)
		for line in range(4):
			draw_line(Vector2(center_x - 26, 299 + line * 10), Vector2(center_x + 24, 299 + line * 10), MUTED, 2.0, true)
		var stick := Vector2(center_x - 17, 185)
		draw_circle(stick, 26, DARK)
		draw_arc(stick, 26, 0, TAU, 32, GREEN, 3.0, true)
		draw_circle(stick, 11, MUTED)
		_label("STICK", stick + Vector2(-26, -36), 16, MUTED)
		if right:
			_button(Vector2(center_x - 14, 250), "B")
			_button(Vector2(center_x + 31, 264), "A")
			_button(Vector2(center_x - 39,222),"X",14)
			_button(Vector2(center_x + 5,216),"Y",14)
			draw_rect(Rect2(center_x + 27, 183, 24, 16), MUTED, false, 2.0)
			_label("PAUSE", Vector2(center_x + 15, 175), 15, MUTED)
			draw_line(Vector2(center_x - 28, 127), Vector2(center_x + 10, 132), GREEN, 6.0, true)
		else:
			draw_line(Vector2(center_x - 28,127),Vector2(center_x + 10,132),GREEN,6.0,true)
			var pad := Vector2(center_x + 22, 252)
			draw_rect(Rect2(pad - Vector2(12, 34), Vector2(24, 68)), DARK)
			draw_rect(Rect2(pad - Vector2(34, 12), Vector2(68, 24)), DARK)
			draw_line(pad + Vector2(-24, 0), pad + Vector2(24, 0), GREEN, 4.0, true)
			draw_line(pad + Vector2(0, -24), pad + Vector2(0, 24), GREEN, 4.0, true)
			draw_rect(Rect2(center_x - 36, 276, 24, 16), MUTED, false, 2.0)
			_label("VIEW", Vector2(center_x - 49, 268), 15, MUTED)


	func _button(at: Vector2, text: String, radius: float = 18.0) -> void:
		draw_circle(at, radius, DARK)
		draw_arc(at, radius, 0, TAU, 24, GREEN, 2.0, true)
		_label(text, at + Vector2(-7, 7), 21, GREEN)


	func _badge(text: String, at: Vector2, width: float = 32.0) -> void:
		draw_rect(Rect2(at + Vector2(0, -20), Vector2(width, 28)), Color(0.08, 0.2, 0.19))
		draw_rect(Rect2(at + Vector2(0, -20), Vector2(width, 28)), MUTED, false, 1.0)
		_label(text, at + Vector2(7, 1), 20, GREEN)


	func _draw() -> void:
		UI.frame(self,Rect2(2,2,996,596),DARK,UI.EDGE,14)
		UI.text(self,"STEAM FRAME CONTROLS",Vector2(28,14),30,INK,"header")
		UI.text(self,"BINDING DIAGRAM",Vector2(785,23),24,MUTED)
		draw_line(Vector2(25, 58), Vector2(975, 58), MUTED, 2.0)
		draw_line(Vector2(500, 78), Vector2(500, 470), MUTED, 1.0)
		_label("LEFT  /  TABLE + NAVIGATION", Vector2(28, 91), 22, GREEN)
		_label("RIGHT  /  POINT + ACT", Vector2(526, 91), 22, GREEN)
		_controller(290, false)
		_controller(660, true)
		_callout("TRIGGER", ["Power page: + power", "Else: stations"], Vector2(28, 132), Vector2(301, 149), true)
		_callout("STICK", ["Rotate / scale", "Click: recenter"], Vector2(28, 212), Vector2(273, 185), true)
		_callout("GRIP", ["Move tabletop"], Vector2(28, 305), Vector2(222, 253), true)
		_callout("BUMPER", ["Hold: 1-8 wheel", "Release: confirm"], Vector2(784, 119), Vector2(646, 128), false)
		_callout("TRIGGER", ["Click / hold crew", "Drop / beam drag"], Vector2(784, 210), Vector2(694, 149), false)
		_callout("GRIP", ["Hold for SHIFT"], Vector2(784, 305), Vector2(718, 253), false)
		_label("DPAD / VIEW", Vector2(28, 369), 19, MUTED)
		_leader(Vector2(312, 252), Vector2(431, 366), 434)
		_badge("UP", Vector2(28, 394), 49)
		_label("System Power", Vector2(91, 394), 20)
		_badge("VIEW",Vector2(296,394),72)
		_label("Hide / show",Vector2(380,394),17)
		_badge("L / R", Vector2(28, 425), 72)
		_label("Previous / next screen", Vector2(112, 425), 20)
		_badge("DOWN", Vector2(28, 456), 80)
		_label("Tactical screen toggle", Vector2(121, 456), 20)
		_badge("PAUSE", Vector2(526, 369), 85)
		_label("Pause / resume", Vector2(626, 369), 20)
		_badge("A", Vector2(526, 394))
		_label("Inspect rooms / wheel category", Vector2(568, 394), 20)
		_badge("B", Vector2(526, 425))
		_label("Right-click / cancel grab or wheel", Vector2(568, 425), 19)
		_label("STICK: wheel selection   /   click: CTRL", Vector2(526, 456), 20)
		draw_line(Vector2(25, 480), Vector2(975, 480), MUTED, 2.0)
		_label("SHIFT: add crew / depower weapons and systems", Vector2(28, 508), 19, GREEN)
		_label("SHIFT + L trigger: save stations    |    CTRL: reverse autofire", Vector2(28, 534), 19)
		_label("POWER PAGE: L trigger adds power / L bumper removes power", Vector2(28, 560), 19, GREEN)
		_label("POWER PAGE: RIGHT X / Y select previous / next, or point at a system", Vector2(28, 586), 19)
