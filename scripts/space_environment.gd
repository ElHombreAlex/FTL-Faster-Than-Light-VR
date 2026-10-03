extends Node3D

# Stationary surroundings: three draw calls cover the entire sky, with a sparse
# nearer shell for stereo parallax. No captured 2D background is used here.
const STAR_COUNT := 1600
const NEAR_STAR_COUNT := 96
const GALAXY_COUNT := 420
const VALID_HAZARDS := ["clear", "asteroid", "sun", "storm", "nebula", "pulsar"]

var star_positions := PackedVector3Array()
var hazard := "clear"
var simulation_paused := false
var elapsed := 0.0
var hazard_root: Node3D
var rocks: Array[Dictionary] = []
var clouds: Array[Node3D] = []
var body: Node3D
var storm_arcs: Array[MeshInstance3D] = []
var built := false
var cloud_material: ShaderMaterial
var body_material: ShaderMaterial

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front;
uniform vec4 tint : source_color = vec4(0.3, 0.15, 0.45, 0.18);
uniform float clock = 0.0;
varying vec3 local_point;
float hash(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x),
                   mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x),
                   mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { local_point = VERTEX; }
void fragment() {
    vec3 p = local_point * 0.23 + vec3(clock * 0.012, 0.0, clock * 0.007);
    float n = noise(p) * 0.58 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.14;
    ALBEDO = tint.rgb * (0.5 + n * 0.5);
    ALPHA = smoothstep(0.34, 0.7, n) * tint.a;
}
"""

const STAR_BODY_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.015, 1.0);
uniform float clock = 0.0;
varying vec3 local_point;
float hash(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x),
                   mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x),
                   mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { local_point = VERTEX; }
void fragment() {
    vec3 p = normalize(local_point);
    vec3 drift = vec3(clock * 0.035, clock * 0.012, 0.0);
    float cells = smoothstep(0.18, 0.78, noise(p * 23.0 + drift) * 0.65 + noise(p * 47.0) * 0.35);
    ALBEDO = mix(tint.rgb * 0.34, tint.rgb, cells);
    EMISSION = mix(tint.rgb, vec3(1.0, 0.88, 0.54), cells * 0.35) * 1.8;
}
"""

const CORONA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.035, 0.42);
void fragment() {
    float rim = pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.5);
    ALBEDO = tint.rgb;
    ALPHA = rim * tint.a;
}
"""


func build() -> void:
	if built:
		return
	built = true
	name = "SpaceEnvironment"
	var rng := RandomNumberGenerator.new()
	rng.seed = 26011002
	_star_shell("DistantStars360", STAR_COUNT, 30.0, 58.0, rng, false)
	_star_shell("NearStarsParallax", NEAR_STAR_COUNT, 8.0, 17.0, rng, false)
	_star_shell("DistantGalaxyBand", GALAXY_COUNT, 35.0, 54.0, rng, true)
	hazard_root = Node3D.new()
	hazard_root.name = "NativeHazard"
	add_child(hazard_root)
	_set_hazard("clear")


func apply_state(state: Dictionary) -> void:
	if not built:
		build()
	simulation_paused = bool(state.get("paused", false))
	var next := str(state.get("hazard", "clear"))
	if next in VALID_HAZARDS and next != hazard:
		_set_hazard(next)


func set_hazard(kind: String) -> void:
	if not built:
		build()
	if kind in VALID_HAZARDS and kind != hazard:
		_set_hazard(kind)


func _star_shell(node_name: String, count: int, near_radius: float, far_radius: float,
		rng: RandomNumberGenerator, galaxy: bool) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.use_colors = true
	stars.mesh = sphere
	stars.instance_count = count
	stars.custom_aabb = AABB(Vector3.ONE * -far_radius, Vector3.ONE * far_radius * 2.0)
	for i in range(count):
		var y := rng.randf_range(-1.0, 1.0)
		var angle := rng.randf_range(0.0, TAU)
		if galaxy:
			y = rng.randfn(0.0, 0.1)
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var direction := Vector3(radial * cos(angle), y, radial * sin(angle)).normalized()
		if galaxy:
			direction = direction.rotated(Vector3.FORWARD, 0.42)
		var point := direction * rng.randf_range(near_radius, far_radius)
		var size := rng.randf_range(0.019, 0.048) * (near_radius / 30.0)
		if galaxy:
			size *= 0.8
		stars.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), point))
		var tint := Color(0.7, 0.81, 1.0).lerp(Color(1.0, 0.83, 0.65), rng.randf())
		tint *= rng.randf_range(0.42, 1.0) if not galaxy else rng.randf_range(0.12, 0.28)
		tint.a = 1.0
		stars.set_instance_color(i, tint)
		if not galaxy:
			star_positions.append(point)
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = stars
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	node.material_override = material
	add_child(node)


func _set_hazard(kind: String) -> void:
	hazard = kind
	for child in hazard_root.get_children():
		hazard_root.remove_child(child)
		child.queue_free()
	rocks.clear()
	clouds.clear()
	storm_arcs.clear()
	body = null
	cloud_material = null
	body_material = null
	elapsed = 0.0
	match kind:
		"asteroid":
			_build_asteroids()
		"sun", "pulsar":
			_build_star_body(kind)
		"storm", "nebula":
			_build_nebula(kind)


func _build_asteroids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7262026
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.31, 0.29, 0.28)
	material.roughness = 1.0
	for i in range(32):
		var rock := MeshInstance3D.new()
		rock.mesh = mesh
		rock.material_override = material
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(3.0, 9.0)
		rock.position = Vector3(cos(angle) * radius, rng.randf_range(-1.7, 5.0), sin(angle) * radius)
		var size := rng.randf_range(0.12, 0.38)
		rock.scale = Vector3(rng.randf_range(0.7, 1.2), rng.randf_range(0.65, 1.1), rng.randf_range(0.6, 1.2)) * size
		rock.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		hazard_root.add_child(rock)
		rocks.append({"node": rock, "start": rock.position,
			"velocity": Vector3(0.055, 0.007, -0.022) * rng.randf_range(0.5, 1.4),
			"spin": Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))})


func _build_star_body(kind: String) -> void:
	body = Node3D.new()
	body.name = "Sun" if kind == "sun" else "Pulsar"
	body.position = Vector3(-12.0, 8.0, -19.0)
	body.rotation = Vector3(0.28, 0.0, -0.45)
	hazard_root.add_child(body)
	var color := Color(1.0, 0.23, 0.025) if kind == "sun" else Color(0.26, 0.67, 1.0)
	var radius := 4.0 if kind == "sun" else 1.9
	var surface := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	surface.mesh = sphere
	body_material = ShaderMaterial.new()
	body_material.shader = Shader.new()
	body_material.shader.code = STAR_BODY_SHADER
	body_material.set_shader_parameter("tint", color)
	surface.material_override = body_material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(surface)
	for scale_factor in [1.08, 1.23]:
		var corona := MeshInstance3D.new()
		corona.mesh = sphere
		corona.scale = Vector3.ONE * scale_factor
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = CORONA_SHADER
		material.set_shader_parameter("tint", Color(color, 0.32))
		corona.material_override = material
		corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(corona)
	if kind == "pulsar":
		for sign_value in [-1.0, 1.0]:
			var jet := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 1.25 if sign_value > 0.0 else 0.06
			cone.bottom_radius = 0.06 if sign_value > 0.0 else 1.25
			cone.height = 11.0
			cone.radial_segments = 12
			jet.mesh = cone
			jet.position.y = sign_value * 6.5
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.albedo_color = Color(0.1, 0.42, 0.85, 0.09)
			jet.material_override = material
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(jet)


func _build_nebula(kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 729 if kind == "storm" else 820
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = Shader.new()
	cloud_material.shader.code = CLOUD_SHADER
	cloud_material.set_shader_parameter("tint", Color(0.12, 0.42, 0.7, 0.24) if kind == "storm" else Color(0.5, 0.19, 0.67, 0.23))
	# Concentric interior shells avoid the visible triangle intersections caused
	# by overlapping transparent cloud spheres. Their distinct depths/rotations
	# still give stereo parallax while the nebula surrounds the player fully.
	for i in range(3):
		var cloud := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 16.0 + float(i) * 9.0
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 64
		sphere.rings = 32
		cloud.mesh = sphere
		cloud.position.y = 1.6
		cloud.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		cloud.material_override = cloud_material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hazard_root.add_child(cloud)
		clouds.append(cloud)
	if kind == "storm":
		# Faint distant electrical filaments are atmosphere only; native FTL still
		# decides every ion hit and hazard effect.
		for i in range(5):
			var arc := MeshInstance3D.new()
			var mesh := ImmediateMesh.new()
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			var angle := float(i) / 5.0 * TAU
			var point := Vector3(cos(angle) * 10.0, rng.randf_range(0.5, 6.0), sin(angle) * 10.0)
			for part in range(5):
				var next := point + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
				mesh.surface_add_vertex(point)
				mesh.surface_add_vertex(next)
				point = next
			mesh.surface_end()
			arc.mesh = mesh
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.albedo_color = Color(0.28, 0.58, 0.82, 0.25)
			arc.material_override = material
			arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hazard_root.add_child(arc)
			storm_arcs.append(arc)


func _process(delta: float) -> void:
	if simulation_paused or not built:
		return
	elapsed += delta
	for rock in rocks:
		var node: Node3D = rock["node"]
		node.position += Vector3(rock["velocity"]) * delta
		node.rotation += Vector3(rock["spin"]) * delta
		if node.position.distance_to(Vector3.ZERO) > 11.0:
			node.position = rock["start"]
	if cloud_material != null:
		cloud_material.set_shader_parameter("clock", elapsed)
	if body_material != null:
		body_material.set_shader_parameter("clock", elapsed)
	if is_instance_valid(body):
		body.rotation.y += delta * 0.005
	for i in range(storm_arcs.size()):
		storm_arcs[i].visible = sin(elapsed * 0.43 + i * 1.73) > 0.88
