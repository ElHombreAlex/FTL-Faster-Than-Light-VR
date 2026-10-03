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
var display_rows: Array = []
const LABEL_WIDTH := 136.0
const LABEL_SIZE := 23


static func equipment_entries(player: Dictionary, drone_slots: int) -> Array:
	# Slot keys remain the native 1–8 shortcuts. Only equipment metadata is
	# retained: positions, charge clocks and moving special actors cannot make
	# the held wheel redraw on each state snapshot.
	var result: Array = []
	var weapons: Array = _equipment_rows(player.get("weapons", []))
	var drones: Array = _equipment_rows(player.get("drone_equipment", player.get("drones", [])))
	var has_drone_equipment := player.has("drone_equipment")
	for slot in range(8):
		var weapon_slot := slot < 4
		var index := slot if weapon_slot else slot - 4
		var equipment: Dictionary = {}
		var source: Array = weapons if weapon_slot else drones
		for i in range(source.size()):
			if not source[i] is Dictionary:
				continue
			var item: Dictionary = source[i]
			var native_slot := int(item.get("slot", i)) if weapon_slot or has_drone_equipment else int(item.get("equipment_slot", item.get("slot", -1)))
			if native_slot == index:
				equipment = item
				break
		var enabled := not equipment.is_empty() if weapon_slot else index < drone_slots
		var family := str(equipment.get("kind", "drone" if not weapon_slot else "laser")).to_lower()
		family = {"missiles":"missile", "burst":"flak"}.get(family, family)
		var name := str(equipment.get("title", equipment.get("short_title", ""))).strip_edges()
		if name == "":
			name = str(equipment.get("name", "")).replace("_", " ").strip_edges()
		if name == "":
			name = "DRONE %d" % (index + 1) if enabled and not weapon_slot else "EMPTY"
		var missile_cost := int(equipment.get("ammo_cost", equipment.get("missile_cost", equipment.get("missiles", 1 if family in ["missile", "bomb"] else 0))))
		var detail := "%d MISSILE%s" % [missile_cost, "S" if missile_cost != 1 else ""] if weapon_slot and missile_cost > 0 else family.to_upper() if enabled else "NO EQUIPMENT"
		result.append({"label":name,"key":49 + slot,"enabled":enabled,
			"icon_kind":family if enabled else "empty", "detail":detail,
			"equipment":true,"weapon":weapon_slot})
	return result


static func _equipment_rows(value: Variant) -> Array:
	# Empty native Lua tables serialize as {}. Treat a missing equipment list
	# as empty so a ship without drones still exposes its weapon shortcuts.
	return value if value is Array else []


static func bounded_lines(value: String, width: float = LABEL_WIDTH, size_px: int = LABEL_SIZE, limit: int = 3) -> Array[String]:
	# Fit using the actual locally loaded glyph metrics, including long words
	# and translations. Fixed character counts cannot bound native font ink.
	var words := value.replace("\n", " ").split(" ", false)
	var output: Array[String] = []
	var line := ""
	for word in words:
		var next := str(word) if line == "" else line + " " + str(word)
		if UI.text_size(next, size_px).x <= width:
			line = next
			continue
		if line != "":
			output.append(line)
			line = ""
		for character in str(word):
			if line != "" and UI.text_size(line + character, size_px).x > width:
				output.append(line)
				line = ""
			line += character
	if line != "": output.append(line)
	if output.size() > limit:
		output.resize(limit)
		var last := output[limit - 1]
		while last != "" and UI.text_size(last + "...", size_px).x > width:
			last = last.left(last.length() - 1)
		output[limit - 1] = last + "..."
	return output


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
	display_rows.clear()
	for entry in entries:
		display_rows.append({"lines":bounded_lines(str(entry.get("label", "")),LABEL_WIDTH,LABEL_SIZE,2 if entry.get("equipment",false) else 3),
			"detail":bounded_lines(str(entry.get("detail", "")), LABEL_WIDTH, 18, 1) if entry.get("enabled",true) else []})
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
	var sectors: Array[PackedVector2Array] = []


	func _ready() -> void:
		for i in range(8): sectors.append(_sector(i * TAU / 8.0))


	func _equipment_icon(kind: String, center: Vector2, color: Color) -> void:
		# Original vector silhouettes: no extracted sprite, new viewport or
		# mesh allocation. Shape + ammo caption distinguishes similar names.
		match kind:
			"beam":
				draw_line(center + Vector2(-24,8), center + Vector2(-13,-8), color, 4)
				draw_line(center + Vector2(-13,-8), center + Vector2(24,-8), color, 3)
				draw_line(center + Vector2(-13,-3), center + Vector2(24,-3), color, 1)
			"ion":
				draw_arc(center, 10, 0, TAU, 16, color, 3)
				draw_line(center + Vector2(-23,0), center + Vector2(-13,0), color, 3)
				draw_line(center + Vector2(13,0), center + Vector2(23,0), color, 3)
			"missile":
				draw_colored_polygon(PackedVector2Array([center + Vector2(-21,-6),center + Vector2(10,-6),center + Vector2(22,0),center + Vector2(10,6),center + Vector2(-21,6)]),color)
				draw_line(center + Vector2(-11,-11),center + Vector2(-11,11),color,3)
			"bomb":
				draw_circle(center + Vector2(-2,2),10,color)
				draw_line(center + Vector2(3,-7),center + Vector2(13,-13),color,3)
				draw_line(center + Vector2(13,-13),center + Vector2(20,-9),color,2)
			"flak":
				for offset in [Vector2(-17,3),Vector2(-3,-8),Vector2(11,5),Vector2(22,-7)]: draw_rect(Rect2(center + offset - Vector2(3,3),Vector2(6,6)),color)
			"laser":
				draw_rect(Rect2(center + Vector2(-23,-5),Vector2(20,10)),color)
				draw_line(center + Vector2(-3,0),center + Vector2(23,0),color,3)
			"empty":
				draw_line(center + Vector2(-12,0),center + Vector2(12,0),color,2)
			_:
				draw_rect(Rect2(center - Vector2(10,7),Vector2(20,14)),color,false,2)
				draw_line(center + Vector2(-23,0),center + Vector2(-10,0),color,3)
				draw_line(center + Vector2(10,0),center + Vector2(23,0),color,3)


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
			var outline := sectors[i]
			draw_colored_polygon(outline,UI.SELECTED if active else UI.PANEL if enabled else UI.DARK)
			draw_polyline(outline,UI.GOLD if active else UI.EDGE if enabled else UI.MUTED,1.5,false)
			draw_line(outline[outline.size() - 1],outline[0],UI.GOLD if active else UI.EDGE if enabled else UI.MUTED,1.5)
			var center := CENTER + Vector2(sin(angle),-cos(angle)) * 225
			var entry: Dictionary = wheel.entries[i] if i < wheel.entries.size() else {}
			var equipment := bool(entry.get("equipment", false))
			UI.centered_text(self,str(i + 1),center + Vector2(0,-55 if equipment else -22),38,UI.GOLD if active else UI.GREEN if enabled else UI.MUTED,"header")
			if equipment: _equipment_icon(str(entry.get("icon_kind", "empty")),center + Vector2(0,-20),UI.GOLD if active else UI.GREEN if enabled else UI.MUTED)
			var row: Dictionary = wheel.display_rows[i] if i < wheel.display_rows.size() else {"lines":["-"],"detail":[]}
			var wrapped: Array = row.lines
			for line in range(wrapped.size()):
				UI.centered_text(self,str(wrapped[line]),center + Vector2(0,9 + line * 22),LABEL_SIZE,UI.INK if enabled else UI.MUTED)
			if equipment and not row.detail.is_empty():
				UI.centered_text(self,str(row.detail[0]),center + Vector2(0,56),18,UI.GOLD if enabled else UI.MUTED)
		UI.frame(self,Rect2(CENTER - Vector2(102,56),Vector2(204,112)),UI.DARK,UI.EDGE,17)
		var titles := str(wheel.heading).split("\n")
		for i in range(titles.size()):
			UI.centered_text(self,titles[i],CENTER + Vector2(0,(i - (titles.size() - 1) * .5) * 29),25,UI.INK,"header")
		UI.frame(self,Rect2(38,700,644,88),UI.DARK,UI.EDGE,12)
		var selected: Dictionary = wheel.entries[wheel.selected] if wheel.selected >= 0 and wheel.selected < wheel.entries.size() else {}
		var caption := str(selected.get("label", "STICK: CHOOSE   RELEASE BUMPER: CONFIRM"))
		if selected.get("equipment",false) and selected.get("enabled",true): caption += " / " + str(selected.get("detail",""))
		var caption_lines: Array = wheel.bounded_lines(caption,608,23,1)
		UI.centered_text(self,str(caption_lines[0]) if not caption_lines.is_empty() else "",Vector2(360,716),23,UI.INK)
		UI.centered_text(self,"A: CATEGORY   B / CENTER: CANCEL   TRIGGER: CONFIRM",Vector2(360,745),20,UI.MUTED)
		var hint := "SHIFT: DEPOWER   CTRL: REVERSE AUTOFIRE" if bool(selected.get("weapon", false)) else "SHIFT: DEPOWER   RELEASE BUMPER: CONFIRM" if bool(selected.get("equipment", false)) else "RELEASE BUMPER: CONFIRM"
		UI.centered_text(self,hint,Vector2(360,772),20,UI.GOLD)
