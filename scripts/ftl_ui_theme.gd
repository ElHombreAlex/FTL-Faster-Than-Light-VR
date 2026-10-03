extends RefCounted

const ASSETS = preload("res://scripts/ftl_ui_assets.gd")
# Native FTL uses near-black panels, pale outlines and restrained green/gold.
const INK := Color("e0ead4")
const EDGE := Color("a2b5a5")
const GREEN := Color("7fff74")
const MUTED := Color("70857d")
const DARK := Color("081012")
const PANEL := Color("102023")
const SELECTED := Color("20352c")
const GOLD := Color("ffe89a")
const RED := Color("ed6260")
const ION := Color("7bb8ff")


static func text_size(value: String, font_size: int, role: String = "body") -> Vector2:
	var font := ASSETS.font(role)
	return Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x,font.get_height(font_size))


static func text(canvas: CanvasItem, value: String, at: Vector2, font_size: int = 28, color: Color = INK, role: String = "body") -> void:
	var font := ASSETS.font(role)
	canvas.draw_string(font,(at + Vector2(0,font.get_ascent(font_size))).round(),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)


static func centered_text(canvas: CanvasItem, value: String, center: Vector2, font_size: int = 28, color: Color = INK, role: String = "body") -> void:
	text(canvas,value,center - text_size(value,font_size,role) * .5,font_size,color,role)


static func clipped_rect(rect: Rect2, cut: float = 5.0) -> PackedVector2Array:
	var p := rect.position
	var q := rect.end
	return PackedVector2Array([Vector2(p.x + cut,p.y),Vector2(q.x - cut,p.y),Vector2(q.x,p.y + cut),Vector2(q.x,q.y - cut),Vector2(q.x - cut,q.y),Vector2(p.x + cut,q.y),Vector2(p.x,q.y - cut),Vector2(p.x,p.y + cut)])


static func frame(canvas: CanvasItem, rect: Rect2, fill: Color = PANEL, edge: Color = EDGE, cut: float = 5.0) -> void:
	var polygon := clipped_rect(rect,minf(cut,5.0))
	canvas.draw_colored_polygon(polygon,fill)
	polygon.append(polygon[0])
	canvas.draw_polyline(polygon,edge,1.5,false)


static func button(canvas: CanvasItem, rect: Rect2, label: String, enabled: bool = true, highlighted: bool = false) -> void:
	frame(canvas,rect,SELECTED if highlighted else PANEL,GOLD if highlighted else EDGE if enabled else MUTED,4)
	var size_px := 34 if label.length() <= 20 else 28
	centered_text(canvas,label,rect.get_center(),size_px,INK if enabled else MUTED)
