extends Control

signal texture_changed

var state: Dictionary = {}
var textures: Dictionary = {}
var original_frame: Texture2D
var frame_image: Image
var frame_signature := ""
var frame_file := "hud_frame.png"
var use_original_frame := true
var source_rect := Rect2(0, 0, 1280, 720)
var base_path := ""
var font: Font = ThemeDB.fallback_font
var received_frames := 0
var capture_time_unix := 0.0
const NATIVE_SIZE := Vector2(1280, 720)
const RAW_HEADER_SIZE := 36


func set_state(value: Dictionary) -> void:
	state = value
	if original_frame == null:
		request_redraw()


func request_redraw() -> void:
	queue_redraw()
	texture_changed.emit()


func poll_original_frame() -> void:
	if not use_original_frame:
		return
	var path := base_path.path_join(frame_file)
	var raw_path := path.get_basename() + ".rgba"
	if FileAccess.file_exists(raw_path):
		_poll_raw_frame(raw_path)
		return
	if not FileAccess.file_exists(path):
		var had_frame := original_frame != null
		original_frame = null
		frame_image = null
		frame_signature = ""
		if had_frame:
			request_redraw()
		return
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	var bytes := source.get_buffer(source.get_length())
	source.close()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var signature := frame_file + digest.finish().hex_encode()
	if signature != frame_signature:
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK and not image.is_empty():
			_accept_frame(image, signature)


func _poll_raw_frame(path: String) -> void:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	# Header-only polling avoids reading, hashing and decoding an unchanged image.
	var header := source.get_buffer(RAW_HEADER_SIZE)
	if header.size() != RAW_HEADER_SIZE or header.slice(0, 4).get_string_from_ascii() != "FVR1" or header.decode_u32(4) != 1:
		source.close()
		return
	var width := int(header.decode_u32(8))
	var height := int(header.decode_u32(12))
	if width < 1 or height < 1 or width > 2560 or height > 1440 or header.decode_u32(16) != 4 or source.get_length() != RAW_HEADER_SIZE + width * height * 4:
		source.close()
		return
	var signature := frame_file + header.hex_encode()
	if signature == frame_signature:
		source.close()
		return
	var bytes := source.get_buffer(width * height * 4)
	source.close()
	if bytes.size() != width * height * 4:
		return
	capture_time_unix = header.decode_double(28)
	_accept_frame(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes), signature)


func _accept_frame(image: Image, signature: String) -> void:
	frame_image = image
	if original_frame is ImageTexture and Vector2i(original_frame.get_size()) == image.get_size():
		original_frame.update(image)
	else:
		original_frame = ImageTexture.create_from_image(image)
	frame_signature = signature
	received_frames += 1
	request_redraw()


func native_alpha_at(pixel: Vector2i) -> float:
	if frame_image == null:
		return 0.0
	var image_size := frame_image.get_size()
	var scaled := Vector2(pixel) * Vector2(image_size) / NATIVE_SIZE
	var sample := Vector2i(clampi(floori(scaled.x), 0, image_size.x - 1), clampi(floori(scaled.y), 0, image_size.y - 1))
	return frame_image.get_pixelv(sample).a


func native_used_rect() -> Rect2i:
	if frame_image == null:
		return Rect2i()
	var used := frame_image.get_used_rect()
	var scale := NATIVE_SIZE / Vector2(frame_image.get_size())
	var first := Vector2(used.position) * scale
	var last := Vector2(used.end) * scale
	return Rect2i(Vector2i(floori(first.x), floori(first.y)), Vector2i(ceili(last.x), ceili(last.y)) - Vector2i(floori(first.x), floori(first.y)))


func _texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var file := base_path.path_join("ui/img").path_join(path)
	if not FileAccess.file_exists(file):
		return null
	var image := Image.load_from_file(file)
	var texture := ImageTexture.create_from_image(image)
	textures[path] = texture
	return texture


func _art(path: String, point: Vector2) -> void:
	var texture := _texture(path)
	if texture != null:
		draw_texture(texture, point)


func _text(value: String, point: Vector2, size_px: int = 17, color: Color = Color(0.92, 0.97, 0.87)) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, color)


func _draw() -> void:
	if original_frame != null:
		# The live bridge can provide the original game's transparent UI render target.
		var transport_rect := Rect2(source_rect.position * original_frame.get_size() / NATIVE_SIZE, source_rect.size * original_frame.get_size() / NATIVE_SIZE)
		draw_texture_rect_region(original_frame, Rect2(Vector2.ZERO, size), transport_rect)
		return
	# Demo/fallback art uses native coordinates just like the live texture. The
	# viewport clips the cropped lower controls instead of shrinking them into it.
	var crop_scale := size / source_rect.size
	draw_set_transform(-source_rect.position * crop_scale, 0.0, crop_scale)
	_art("statusUI/top_hull.png", Vector2(5, 0))
	_art("statusUI/top_hull_label.png", Vector2(5, 0))
	_text("HULL", Vector2(12, 22), 18, Color(0.04, 0.12, 0.13))
	var hull := int(state.get("hull", 30))
	var hull_max := maxi(1, int(state.get("hull_max", 30)))
	for i in range(30):
		var color := Color(0.48, 1.0, 0.47) if i < roundi(30.0 * hull / hull_max) else Color(0.11, 0.18, 0.16)
		draw_rect(Rect2(19 + i * 11.7, 32, 10, 14), color)
	_art("statusUI/top_scrap.png", Vector2(393, 0))
	_text(str(state.get("scrap", 52)), Vector2(444, 34))
	_art("statusUI/top_shields4_on.png", Vector2(5, 57))
	for i in range(clampi(int(state.get("shield", 2)), 0, 4)):
		_art("statusUI/top_shieldsquare1_on.png", Vector2(31 + i * 23, 64))
	for entry in [["fuel", 140, 17], ["missiles", 220, 8], ["drones", 300, 2]]:
		_art("statusUI/top_%s_on.png" % entry[0], Vector2(entry[1], 57))
		_text(str(state.get(entry[0], entry[2])), Vector2(entry[1] + 42, 84))
	_art("statusUI/top_evade_oxygen.png", Vector2(5, 106))
	_text("%d%%" % int(state.get("evasion", 25)), Vector2(48, 128), 15)
	_text("%d%%" % int(state.get("oxygen", 100)), Vector2(48, 152), 15)
	var crew: Array = state.get("crew", [{"name": "Crew 1", "health": 100}, {"name": "Crew 2", "health": 100}, {"name": "Crew 3", "health": 100}])
	for i in range(crew.size()):
		var y := 178 + i * 31
		draw_rect(Rect2(8, y, 108, 26), Color(0.06, 0.13, 0.14, 0.9))
		draw_rect(Rect2(8, y, 108, 26), Color(0.58, 0.68, 0.6), false)
		draw_circle(Vector2(21, y + 10), 6, Color(0.6, 0.9, 0.34))
		_text(str(crew[i].get("name", "Crew")), Vector2(34, y + 16), 14)
		draw_rect(Rect2(13, y + 21, 94 * clampf(float(crew[i].get("health", 100)) / 100.0, 0, 1), 3), Color(0.36, 0.88, 0.33))
	var reactor := int(state.get("reactor", 8))
	for i in range(25):
		draw_rect(Rect2(20, 682 - i * 6, 20, 4), Color(0.53, 0.97, 0.49) if i < reactor else Color(0.08, 0.1, 0.11))
		draw_rect(Rect2(20, 682 - i * 6, 20, 4), Color(0.55, 0.61, 0.6), false)
	var systems: Dictionary = state.get("systems", {"shields": 2, "engines": 2, "medbay": 1, "oxygen": 1, "weapons": 3, "drones": 0})
	var system_order := ["shields", "engines", "medbay", "oxygen", "weapons", "drones"]
	for i in range(system_order.size()):
		var x := 62 + i * 43
		var system_name: String = system_order[i]
		_art("icons/s_%s_green1.png" % system_name, Vector2(x, 666))
		_art("systemUI/button_default_base.png", Vector2(x, 592))
		for cell in range(int(systems.get(system_name, 0))):
			draw_rect(Rect2(x + 12, 651 - cell * 9, 17, 7), Color(0.4, 0.94, 0.35))
	_art("box_weapons_bottom4.png", Vector2(341, 616))
	_art("box_weapons_bottom_label.png", Vector2(341, 680))
	_text("WEAPONS", Vector2(352, 705), 17, Color(0.07, 0.17, 0.17))
	var weapons: Array = state.get("weapons", [{"name": "Burst Laser II", "charge": 1.0}, {"name": "Artemis", "charge": 1.0}])
	for i in range(mini(4, weapons.size())):
		var x := 350 + i * 99
		draw_rect(Rect2(x, 624, 93, 46), Color(0.02, 0.08, 0.06, 0.88))
		draw_rect(Rect2(x, 624, 93, 46), Color(0.75, 0.87, 0.78), false)
		draw_rect(Rect2(x + 3, 628, 5, 37 * clampf(float(weapons[i].get("charge", 0)), 0, 1)), Color(0.38, 0.97, 0.38))
		_text(str(weapons[i].get("name", "Weapon")), Vector2(x + 12, 647), 11)
		_text(str(i + 1), Vector2(x + 12, 665), 13)
	_art("box_weapons_autofire_base.png", Vector2(663, 678))
	_text("AUTOFIRE", Vector2(676, 698), 12, Color(0.12, 0.2, 0.12))
	_art("box_subsystems4.png", Vector2(1080, 678))
	for i in range(3):
		_art("icons/s_%s_green1.png" % ["pilot", "sensors", "doors"][i], Vector2(1083 + i * 43, 646))
	_text("SUBSYSTEMS", Vector2(1089, 703), 15, Color(0.07, 0.17, 0.17))
	if bool(state.get("paused", false)):
		_art("Text_pause1.png", Vector2(536, 523))
