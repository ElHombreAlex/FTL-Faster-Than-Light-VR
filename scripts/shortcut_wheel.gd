extends Node3D

# One FTL-styled radial surface. Choosing a sector redraws once; no animated
# viewport or per-label meshes are needed while the wheel is held open.
const UI = preload("res://scripts/ftl_ui_theme.gd")
const SIZE := Vector2(0.54,0.60)
const PIXELS := Vector2(720,800)
var selected := -1
var entries: Array = []
var heading := "ACTIONS"
var viewport: SubViewport
var canvas: Control
var content_revision := 0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(PIXELS)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = WheelCanvas.new()
	canvas.wheel = self
	canvas.size = PIXELS
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var backing := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	backing.mesh = quad
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 125
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = viewport.get_texture()
	backing.material_override = material
	add_child(backing)
	visible = false


func set_entries(value: Array, title: String) -> void:
	if entries == value and heading == title:
		return
	entries = value.duplicate(true)
	heading = title
	_redraw()


func choose(stick: Vector2) -> void:
	# Top = 1, clockwise through 8. Center releases without an action.
	var next := -1 if stick.length() < 0.45 else posmod(roundi(atan2(stick.x,stick.y) / (TAU / 8.0)),8)
	if next == selected:
		return
	selected = next
	_redraw()


func _redraw() -> void:
	content_revision += 1
	if canvas != null:
		canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


class WheelCanvas extends Control:
	var wheel: Node3D
	const CENTER := Vector2(360,353)


	func _sector(angle: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		var half := TAU / 16.0 - .025
		for j in range(13):
			var a := angle - half + (half * 2) * j / 12.0
			points.append(CENTER + Vector2(sin(a),-cos(a)) * 326)
		for j in range(12,-1,-1):
			var a := angle - half + (half * 2) * j / 12.0
			points.append(CENTER + Vector2(sin(a),-cos(a)) * 129)
		return points


	func _draw() -> void:
		for i in range(8):
			var enabled: bool = i < wheel.entries.size() and bool(wheel.entries[i].get("enabled",true))
			var active: bool = wheel.selected == i and enabled
			var angle := i * TAU / 8.0
			var outline := _sector(angle)
			draw_colored_polygon(outline,UI.SELECTED if active else UI.PANEL if enabled else UI.DARK)
			outline.append(outline[0])
			draw_polyline(outline,UI.GOLD if active else UI.EDGE if enabled else UI.MUTED,1.5,false)
			var center := CENTER + Vector2(sin(angle),-cos(angle)) * 225
			UI.centered_text(self,str(i + 1),center + Vector2(0,-22),38,UI.GOLD if active else UI.GREEN if enabled else UI.MUTED,"header")
			var label := str(wheel.entries[i].get("label","")) if i < wheel.entries.size() else "-"
			var lines := label.replace("\n"," ").split(" ",false)
			var current := ""
			var wrapped: Array[String] = []
			for word in lines:
				if current.length() + word.length() + 1 > 12 and current != "":
					wrapped.append(current)
					current = ""
				current = word if current == "" else current + " " + word
			if current != "": wrapped.append(current)
			for line in range(mini(3,wrapped.size())):
				UI.centered_text(self,wrapped[line],center + Vector2(0,11 + line * 21),24,UI.INK if enabled else UI.MUTED)
		UI.frame(self,Rect2(CENTER - Vector2(102,56),Vector2(204,112)),UI.DARK,UI.EDGE,17)
		var titles := str(wheel.heading).split("\n")
		for i in range(titles.size()):
			UI.centered_text(self,titles[i],CENTER + Vector2(0,(i - (titles.size() - 1) * .5) * 29),25,UI.INK,"header")
		UI.frame(self,Rect2(38,700,644,88),UI.DARK,UI.EDGE,12)
		UI.centered_text(self,"STICK: CHOOSE   RELEASE BUMPER: CONFIRM",Vector2(360,727),24,UI.INK)
		UI.centered_text(self,"A: CATEGORY   B / CENTER: CANCEL",Vector2(360,760),24,UI.MUTED)
