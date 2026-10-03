extends Node3D

# The panel owns visuals only. Legacy navigation Area3Ds can retain their exact
# geometry; power cards are picked on this surface without physics collisions.
const UI = preload("res://scripts/ftl_ui_theme.gd")
# Native RenderPowerBoxes uses an orange battery outline, yellow bonus power,
# cyan ion locks and purple hacking. The allocated/battery/bonus fields are
# separate in ShipSystem; GetEffectivePower also includes native manning boosts.
const BATTERY := Color("e66e1e")
const BONUS := Color("fffa5a")
const ION_POWER := Color("85e7ed")
const HACKED_POWER := Color("cf46fd")
const SIZE := Vector2(0.92, 0.72)
const PIXELS := Vector2(1150, 900)
const SYSTEM_NAMES := {"shields":"SHIELDS", "engines":"ENGINES", "oxygen":"OXYGEN", "medbay":"MEDBAY", "clonebay":"CLONE BAY", "weapons":"WEAPONS", "drones":"DRONES", "teleporter":"TELEPORTER", "cloaking":"CLOAKING", "mind":"MIND CONTROL", "hacking":"HACKING", "artillery":"ARTILLERY", "battery":"BATTERY"}
const SYSTEM_ORDER := ["shields","engines","oxygen","medbay","clonebay","weapons","drones","teleporter","cloaking","mind","hacking","artillery","battery"]
var surface_size := SIZE
var viewport: SubViewport
var canvas: Control
var heading := "NAVIGATION"
var buttons: Array = []
var power_rows: Array = []
var reactor: Dictionary = {}
var selected_key := ""
var power_mode := false
var paused := false
var content_revision := 0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(PIXELS)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	canvas = PanelCanvas.new()
	canvas.panel = self
	canvas.size = PIXELS
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	var display := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	display.mesh = quad
	display.position.z = 0.012
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 121
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = viewport.get_texture()
	display.material_override = material
	add_child(display)


func _redraw() -> void:
	content_revision += 1
	if canvas != null:
		canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_navigation(title: String, entries: Array, is_paused: bool = false) -> void:
	if not power_mode and heading == title and buttons == entries and paused == is_paused:
		return
	heading = title
	buttons = entries.duplicate(true)
	paused = is_paused
	power_mode = false
	_redraw()


func set_power(player: Dictionary, is_paused: bool = false) -> void:
	var rows := _power_rows(player)
	var raw_power: Variant = player.get("reactor_status", player.get("reactor", {}))
	var power: Dictionary = raw_power if raw_power is Dictionary else {}
	if power_mode and rows == power_rows and power == reactor and paused == is_paused:
		return
	power_rows = rows
	reactor = power.duplicate(true)
	power_mode = true
	paused = is_paused
	heading = "SYSTEM POWER"
	if selected_system().is_empty():
		selected_key = str(power_rows[0].get("key", "")) if not power_rows.is_empty() else ""
	_redraw()


func _power_rows(player: Dictionary) -> Array:
	var value: Variant = player.get("system_status", player.get("system_power", []))
	var result: Array = []
	if value is Array:
		for row in value:
			if row is Dictionary and row.get("powerable", true):
				var copy: Dictionary = row.duplicate(true)
				copy.key = str(copy.get("key", copy.get("name", "")))
				copy.name = str(copy.get("label", SYSTEM_NAMES.get(copy.key,copy.key.to_upper())))
				result.append(copy)
	else:
		# Compatibility with an older bridge: only real power details are used;
		# boolean system-presence flags must never invent allocated power.
		var systems: Dictionary = player.get("systems", {})
		for key in SYSTEM_ORDER:
			var row: Variant = systems.get(key, null)
			if row is Dictionary and row.get("powerable", true):
				var copy: Dictionary = row.duplicate(true)
				copy.key = key
				copy.name = SYSTEM_NAMES.get(key, key.to_upper())
				result.append(copy)
	return result


func select_system(key: String) -> void:
	if selected_key == key:
		return
	for row in power_rows:
		if str(row.get("key", "")) == key:
			selected_key = key
			_redraw()
			return


func step_selection(direction: int) -> void:
	if power_rows.is_empty():
		return
	var index := 0
	for i in range(power_rows.size()):
		if str(power_rows[i].key) == selected_key:
			index = i
			break
	select_system(str(power_rows[posmod(index + direction,power_rows.size())].key))


func selected_system() -> Dictionary:
	for row in power_rows:
		if str(row.get("key", "")) == selected_key:
			return row
	return {}


func reactor_display() -> Dictionary:
	# The bridge supplies FTL's capped reactor calculation. GetAvailablePower
	# alone includes bars disabled by a storm; never show those as free units
	# or mix separately counted battery/Zoltan power into the reactor total.
	var total := clampi(int(reactor.get("usable_total", reactor.get("total", reactor.get("max", 0)))), 0, 50)
	var installed := clampi(int(reactor.get("installed", total)), total, 50)
	return {"total":total, "installed":installed,
		"free":clampi(int(reactor.get("usable_available", reactor.get("available", reactor.get("current", 0)))), 0, total),
		"cap_loss":clampi(int(reactor.get("cap_loss", installed - total)), 0, installed),
		"storm_loss":clampi(int(reactor.get("storm_loss", 0)), 0, installed),
		"battery_free":maxi(0, int(reactor.get("battery_available", 0))),
		"battery_total":maxi(0, int(reactor.get("battery_total", 0)))}


func power_card_rect(index: int) -> Rect2:
	var count := maxi(1,power_rows.size())
	var rows_per_column := ceili(count / 2.0)
	var height := minf(106.0, 642.0 / rows_per_column)
	return Rect2(190 + floori(float(index) / rows_per_column) * 450, 140 + (index % rows_per_column) * height, 422, height - 10)


func ray_hit(from: Vector3, direction: Vector3) -> Dictionary:
	if not is_visible_in_tree():
		return {}
	var start := to_local(from)
	var ray := to_local(from + direction) - start
	if absf(ray.z) < 0.00001:
		return {}
	var distance := (0.012 - start.z) / ray.z
	if distance <= 0:
		return {}
	var point := start + distance * ray
	var pixel := Vector2(point.x / SIZE.x + 0.5,0.5 - point.y / SIZE.y) * PIXELS
	if not Rect2(Vector2.ZERO,PIXELS).has_point(pixel):
		return {}
	var hit := {"position":to_global(point), "system_key":""}
	if power_mode:
		for i in range(power_rows.size()):
			if power_card_rect(i).has_point(pixel):
				hit.system_key = str(power_rows[i].key)
				break
	return hit


class PanelCanvas extends Control:
	var panel: Node3D
	var icons: Dictionary = {}
	var base_path := ""


	func _ready() -> void:
		base_path = ProjectSettings.globalize_path("res://local_game_data") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("local_game_data")


	func _icon(key: String) -> Texture2D:
		if not icons.has(key):
			var path := base_path.path_join("ui/img/icons/s_%s.png" % key)
			icons[key] = ImageTexture.create_from_image(Image.load_from_file(path)) if FileAccess.file_exists(path) else null
		return icons[key]


	func _draw() -> void:
		UI.frame(self,Rect2(3,3,1144,894),UI.DARK,UI.EDGE,5)
		UI.text(self,panel.heading,Vector2(32,29),32,UI.INK,"header")
		draw_line(Vector2(28,85),Vector2(1122,85),UI.MUTED,1)
		if panel.paused:
			UI.centered_text(self,"PAUSED",Vector2(1024,46),25,UI.GREEN,"header")
		if panel.power_mode:
			_draw_power()
		else:
			var low_buttons := false
			for item in panel.buttons:
				var point: Vector2 = item.get("position",Vector2.ZERO)
				low_buttons = low_buttons or point.y < -.25
				var center := Vector2(point.x / SIZE.x + .5,.5 - point.y / SIZE.y) * PIXELS
				var rect := Rect2(center - Vector2(250,41.875),Vector2(500,83.75))
				UI.button(self,rect,str(item.get("label","")),item.get("enabled",true))
			if low_buttons:
				UI.centered_text(self,"UP: POWER   L/R: SCREEN   DOWN: TACTICAL   VIEW: PAUSE",Vector2(575,877),22,UI.MUTED)
			else:
				draw_line(Vector2(38,829),Vector2(1112,829),UI.MUTED,1)
				UI.centered_text(self,"UP: POWER   L/R: SCREEN   DOWN: TACTICAL   VIEW: PAUSE",Vector2(575,850),24,UI.MUTED)
				UI.centered_text(self,"LEFT TRIGGER: STATIONS   RIGHT BUMPER: ACTION WHEEL",Vector2(575,877),22,UI.INK)


	func _draw_power() -> void:
		UI.text(self,"REACTOR",Vector2(31,108),27,UI.INK)
		var power: Dictionary = panel.reactor_display()
		var total := int(power.total)
		var available := int(power.free)
		var installed := int(power.installed)
		if int(power.cap_loss) > 0:
			UI.centered_text(self,"STORM -%d" % int(power.storm_loss) if int(power.storm_loss) > 0 else "LIMIT -%d" % int(power.cap_loss),Vector2(94,134),18,ION_POWER)
		UI.frame(self,Rect2(41,145,103,610),UI.PANEL,UI.EDGE,9)
		var pitch := minf(20,562.0 / maxi(1,installed))
		for cell in range(installed):
			var rect := Rect2(57,731 - cell * pitch,71,pitch - 3)
			draw_rect(rect,UI.GREEN if cell < available else UI.DARK)
			draw_rect(rect,ION_POWER if cell >= total else UI.EDGE,false,1)
			if cell >= total: draw_line(rect.position,rect.end,ION_POWER,1)
		UI.centered_text(self,"%d/%d" % [available,total],Vector2(94,779),32,UI.GREEN)
		UI.centered_text(self,"FREE",Vector2(94,809),22,UI.MUTED)
		if int(power.battery_total) > 0:
			UI.centered_text(self,"BATTERY",Vector2(94,839),18,BATTERY)
			UI.centered_text(self,"%d/%d" % [int(power.battery_free),int(power.battery_total)],Vector2(94,865),23,BATTERY)
		for i in range(panel.power_rows.size()):
			var row: Dictionary = panel.power_rows[i]
			var rect: Rect2 = panel.power_card_rect(i)
			var active: bool = str(row.key) == panel.selected_key
			UI.frame(self,rect,UI.SELECTED if active else UI.PANEL,UI.GOLD if active else UI.EDGE,9)
			var texture := _icon(str(row.key))
			if texture != null:
				draw_texture_rect(texture,Rect2(rect.position + Vector2(15,13),Vector2(42,42)),false,UI.GOLD if active else UI.INK)
			else:
				draw_rect(Rect2(rect.position + Vector2(18,18),Vector2(34,34)),UI.MUTED,false,2)
				UI.centered_text(self,str(row.key).substr(0,1),rect.position + Vector2(35,35),30,UI.INK)
			UI.text(self,str(row.name),rect.position + Vector2(68,12),30,UI.GOLD if active else UI.INK)
			var capacity := clampi(int(row.get("max_power",row.get("max",0))),0,16)
			var allocated := clampi(int(row.get("allocated",row.get("power",0))),0,capacity)
			var battery := clampi(int(row.get("battery_power",0)),0,capacity)
			var bonus := clampi(int(row.get("bonus_power",0)),0,capacity)
			var effective := maxi(0,int(row.get("effective_power",allocated + battery + bonus)))
			var damaged := clampi(int(row.get("damaged",0)),0,capacity)
			var cap := clampi(int(row.get("power_cap",capacity)),0,capacity)
			var ionized := bool(row.get("ionized",false))
			var locked := bool(row.get("locked",false))
			var hacked := int(row.get("hacked",0)) > 1
			var bar_y := rect.end.y - 30
			var cell_width := minf(22,(250.0 - maxi(0,capacity - 1) * 3) / maxi(1,capacity))
			for cell in range(capacity):
				var bar := Rect2(rect.position.x + 68 + cell * (cell_width + 3),bar_y,cell_width,15)
				var color := UI.DARK
				var outline := UI.EDGE
				var battery_cell := cell >= allocated and cell < allocated + battery
				if cell < allocated:
					color = HACKED_POWER if hacked else ION_POWER if ionized else UI.INK if locked else UI.GREEN
				elif battery_cell:
					outline = BATTERY
				elif cell < allocated + battery + bonus:
					color = BONUS
				elif cell >= capacity - damaged:
					color = UI.RED
				elif cell >= cap:
					outline = ION_POWER
				draw_rect(bar,color)
				if battery_cell:
					draw_rect(bar.grow(-3),UI.GREEN)
				draw_rect(bar,outline,false,1)
			# Keep the native effective total; do not count battery twice or debit
			# reactor availability for Zoltan power. Raw selected rows are untouched.
			UI.text(self,"%d/%d" % [effective,capacity],Vector2(rect.end.x - 75,bar_y - 2),22,UI.INK)
			if hacked or ionized or locked:
				UI.text(self,"HACK" if hacked else "LOCK",Vector2(rect.end.x - 75,rect.position.y + 16),20,HACKED_POWER if hacked else ION_POWER if ionized else UI.INK)
		if panel.power_rows.is_empty():
			UI.centered_text(self,"WAITING FOR LIVE SYSTEM STATUS",Vector2(661,440),30,UI.MUTED)
		for source in [[250,"REACTOR",UI.GREEN],[445,"BATTERY",BATTERY],[640,"ZOLTAN",BONUS],[826,"DAMAGED",UI.RED]]:
			draw_rect(Rect2(int(source[0]),791,12,12),source[2])
			UI.text(self,str(source[1]),Vector2(int(source[0]) + 22,788),22,source[2])
		draw_line(Vector2(185,814),Vector2(1107,814),UI.MUTED,1)
		UI.centered_text(self,"L TRIGGER: + POWER   L BUMPER: - POWER",Vector2(661,842),28,UI.INK)
		UI.centered_text(self,"RIGHT X/Y: PREV/NEXT   POINT: SELECT SYSTEM",Vector2(661,873),28,UI.GOLD)
