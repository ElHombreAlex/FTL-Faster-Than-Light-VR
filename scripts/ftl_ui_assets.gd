extends RefCounted

# Owner-local SIL bitmap fonts. Preserve the original atlas, baseline, glyph
# bearings and 1/256-pixel advance; no editor import or installed font is needed.
const FONT_NAMES := {"body":"JustinFont10.font", "header":"c&c.font", "bold":"JustinFont11Bold.font"}
static var fonts: Dictionary = {}
static var textures: Dictionary = {}


static func data_path() -> String:
	if OS.has_feature("editor") or OS.get_cmdline_user_args().has("--desktop"):
		return ProjectSettings.globalize_path("res://local_game_data")
	return OS.get_executable_path().get_base_dir().path_join("local_game_data")


static func font(role: String = "body") -> Font:
	var name: String = FONT_NAMES.get(role,FONT_NAMES.body)
	if not fonts.has(name):
		var native := load_font(data_path().path_join("fonts").path_join(name))
		fonts[name] = native if native != null else ThemeDB.fallback_font
	return fonts[name]


static func texture(relative_path: String) -> Texture2D:
	if not textures.has(relative_path):
		var path := data_path().path_join("ui").path_join(relative_path)
		var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		textures[relative_path] = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	return textures[relative_path]


static func _be16(bytes: PackedByteArray, at: int) -> int:
	return (int(bytes[at]) << 8) | int(bytes[at + 1])


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (_be16(bytes,at) << 16) | _be16(bytes,at + 2)


static func _signed(value: int, bits: int) -> int:
	return value - (1 << bits) if value & (1 << (bits - 1)) else value


static func load_font(path: String) -> FontFile:
	if not FileAccess.file_exists(path): return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 24 or bytes.slice(0,4).get_string_from_ascii() != "FONT" or bytes[4] != 1: return null
	var height := int(bytes[5])
	var baseline := int(bytes[6])
	var info := _be32(bytes,8)
	var count := _be16(bytes,12)
	var stride := _be16(bytes,14)
	var tex := _be32(bytes,16)
	var tex_length := _be32(bytes,20)
	if height < 1 or baseline > height or stride != 16 or count < 1 or info < 24 or info + count * stride > bytes.size(): return null
	if tex < 24 or tex_length < 32 or tex + tex_length > bytes.size(): return null
	# FTL's western fonts contain a SIL v2, uncompressed A8 texture (0x40).
	if bytes.slice(tex,tex + 4).get_string_from_ascii() != "TEX\n" or bytes[tex + 4] != 2 or bytes[tex + 5] != 0x40: return null
	var width := _be16(bytes,tex + 8)
	var atlas_height := _be16(bytes,tex + 10)
	var pixels := _be32(bytes,tex + 16)
	var pixel_count := _be32(bytes,tex + 20)
	if width < 1 or atlas_height < 1 or width > 2048 or atlas_height > 2048 or pixel_count != width * atlas_height or pixels < 32 or pixels + pixel_count > tex_length: return null
	# Validate all glyph bounds before mutating the font cache.
	for i in range(count):
		var offset := info + i * stride
		if _be32(bytes,offset) > 0x10ffff or _be16(bytes,offset + 4) + int(bytes[offset + 8]) > width or _be16(bytes,offset + 6) + int(bytes[offset + 9]) > atlas_height: return null
	var rgba := PackedByteArray()
	rgba.resize(pixel_count * 4)
	for i in range(pixel_count):
		rgba[i * 4] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = bytes[tex + pixels + i]
	var source_image := Image.create_from_data(width,atlas_height,false,Image.FORMAT_RGBA8,rgba)
	# Godot's 3D glyph quads need transparent margins around a narrow stroke.
	# Repack original pixels without changing bearings/advances; a stroke at the
	# right edge of a 2px I/i/l glyph otherwise disappears in Label3D sampling.
	const PADDING := 2
	var atlas_width := 512
	var uv_rects: Array[Rect2i] = []
	var cursor := Vector2i.ZERO
	var row_height := 0
	for i in range(count):
		var offset := info + i * stride
		var padded := Vector2i(int(bytes[offset + 8]),int(bytes[offset + 9])) + Vector2i.ONE * (PADDING * 2)
		if cursor.x + padded.x > atlas_width:
			cursor = Vector2i(0,cursor.y + row_height)
			row_height = 0
		uv_rects.append(Rect2i(cursor,padded))
		cursor.x += padded.x
		row_height = maxi(row_height,padded.y)
	var padded_height := 1
	while padded_height < cursor.y + row_height: padded_height <<= 1
	var atlas := Image.create(atlas_width,padded_height,false,Image.FORMAT_RGBA8)
	atlas.fill(Color(1,1,1,0))
	for i in range(count):
		var offset := info + i * stride
		var original := Rect2i(_be16(bytes,offset + 4),_be16(bytes,offset + 6),int(bytes[offset + 8]),int(bytes[offset + 9]))
		if original.size.x > 0 and original.size.y > 0:
			atlas.blit_rect(source_image,original,uv_rects[i].position + Vector2i.ONE * PADDING)
	var result := FontFile.new()
	result.font_name = path.get_file().get_basename()
	result.fixed_size = height
	result.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	result.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	result.allow_system_fallback = false
	result.set_cache_ascent(0,height,baseline)
	result.set_cache_descent(0,height,height - baseline)
	result.set_texture_image(0,Vector2i(height,0),0,atlas)
	for i in range(count):
		var offset := info + i * stride
		var codepoint := _be32(bytes,offset)
		var glyph_size := Vector2(int(bytes[offset + 8]),int(bytes[offset + 9]))
		var pre := _signed(_be16(bytes,offset + 12),16) / 256.0
		var post := _signed(_be16(bytes,offset + 14),16) / 256.0
		result.set_glyph_advance(0,height,codepoint,Vector2(pre + glyph_size.x + post,0))
		result.set_glyph_offset(0,Vector2i(height,0),codepoint,Vector2(pre - PADDING,-_signed(int(bytes[offset + 10]),8) - PADDING))
		result.set_glyph_size(0,Vector2i(height,0),codepoint,glyph_size + Vector2.ONE * (PADDING * 2))
		result.set_glyph_uv_rect(0,Vector2i(height,0),codepoint,Rect2(uv_rects[i]))
		result.set_glyph_texture_idx(0,Vector2i(height,0),codepoint,0)
	return result
