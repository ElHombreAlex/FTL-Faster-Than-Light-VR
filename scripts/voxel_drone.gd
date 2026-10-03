extends Node3D

const Voxels = preload("res://scripts/voxel_mesh.gd")
const UNIT := 0.01
const STEEL := Color("a5b8be")
const RIM := Color("d3dcda")
const DARK := Color("354b59")
const BLACK := Color("182832")
const BRASS := Color("c6ac75")
static var body_meshes: Dictionary = {}
static var body_material: StandardMaterial3D
var drone_name := ""
var kind := "combat"
var family := "combat"
var is_space := true
var body: MeshInstance3D
var thruster: MeshInstance3D
var emitter: MeshInstance3D
var tool: MeshInstance3D
var live_data: Dictionary = {}
var animation_time := 0.0
var firing := false


static func model_family(data: Dictionary) -> String:
	# Species and blueprint names are native identifiers, independent of the
	# player's language. Crew drone names can be translated or renamed.
	var identity := (str(data.get("kind", "")) + " " + str(data.get("species", "")) + " " + str(data.get("name", ""))).to_lower()
	if not bool(data.get("is_space", true)):
		match str(data.get("species", "")).to_lower():
			"repair": return "repair"
			"battle", "boarder": return "battle"
			"ion": return "ion_boarder"
		if identity.contains("ion"): return "ion_boarder"
		if identity.contains("battle") or identity.contains("board") or identity.contains("anti_person"): return "battle"
		return "repair"
	if identity.contains("hack"): return "hacking"
	if identity.contains("anti") and identity.contains("drone"): return "anti_drone"
	if identity.contains("shield"): return "shield"
	if identity.contains("board") or identity.contains("ion"): return "boarding"
	if identity.contains("defense") or identity.contains("defence"): return "defense"
	if identity.contains("beam"): return "beam"
	return "combat"


func build(data: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	drone_name = str(data.get("name", ""))
	kind = str(data.get("kind", "combat")).to_lower()
	is_space = bool(data.get("is_space", true))
	family = model_family(data)
	animation_time = 0.0
	var mark_two := drone_name.ends_with("_2") and family in ["combat", "defense"]
	var cache_key := family + ("_2" if mark_two else "")
	if not body_meshes.has(cache_key):
		var source := Voxels.make(_body_blocks(mark_two))
		body_meshes[cache_key] = source.mesh
		if body_material == null:
			body_material = source.material_override
		source.free()
	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_meshes[cache_key]
	body.material_override = body_material
	add_child(body)
	var exhaust: Array = []
	var lights: Array = []
	var glow := Color("69d8fa")
	if is_space:
		if family == "boarding":
			exhaust = [_b(-8.0, 0, -2.5, 2.8, 1.5, 1.5, glow), _b(-8.0, 0, 2.5, 2.8, 1.5, 1.5, glow)]
		elif family == "shield":
			exhaust = [_b(-6.6, -1.3, 0, 2.0, 1.0, 2.4, glow)]
		elif family == "hacking":
			exhaust = [_b(-5.4, 0, 0, 2.0, 1.2, 2.0, glow)]
		else:
			for side in [-1.0, 1.0]:
				exhaust.append(_b(-8.4, -0.5, side * 5.4, 2.4, 1.2, 1.8, glow))
		match family:
			"combat":
				glow = Color("f2725b")
				for z in ([-1.8, 1.8] if mark_two else [0.0]): lights.append(_b(13.2, 0.3, z, 0.6, 1.3, 1.3, glow))
			"beam":
				glow = Color("ffdc76")
				lights = [_b(13.0, 0, 0, 0.6, 1.0, 3.7, glow)]
			"defense", "anti_drone":
				glow = Color("98e5aa")
				for z in ([-1.5, 1.5] if mark_two else [0.0]): lights.append(_b(10.7, 2.4, z, 0.6, 1.3, 1.3, glow))
			"hacking":
				glow = Color("b591e0")
				lights = [_b(0, 2.6, 0, 2.6, 0.4, 2.6, glow)]
			"shield":
				for side in [-1.0, 1.0]:
					lights.append(_b(0, 1.4, side * 6.2, 4.2, 0.4, 2.0, glow))
					lights.append(_b(side * 6.2, 1.4, 0, 2.0, 0.4, 4.2, glow))
			"boarding": lights = [_b(8.3, 0, 0, 0.5, 1.5, 2.5, Color("e69468"))]
	else:
		glow = Color("ef736a") if family == "battle" else Color("7fdafa")
		lights = [_b(0, 9.0, -3.0, 2.8, 0.7, 0.3, glow)]
	thruster = _glow_mesh(exhaust, Color("69d8fa"))
	thruster.name = "Exhaust"
	add_child(thruster)
	emitter = _glow_mesh(lights, glow)
	emitter.name = "Emitter"
	add_child(emitter)
	tool = null
	if not is_space:
		var tool_blocks: Array
		if family == "repair":
			tool_blocks = [_b(0, -0.5, 0, 0.9, 3.0, 1.0, STEEL), _b(0, -2.1, -0.7, 2.4, 0.7, 1.3, BRASS),
				_b(-0.9, -2.6, -0.8, 0.5, 1.1, 1.3, RIM), _b(0.9, -2.6, -0.8, 0.5, 1.1, 1.3, RIM)]
		else:
			tool_blocks = [_b(0, -1.2, 0, 1.8, 3.0, 2.0, DARK), _b(0, -2.4, -1.0, 2.7, 1.0, 3.0, STEEL),
				_b(-1.0, -2.9, -2.0, 0.6, 1.1, 1.7, RIM), _b(1.0, -2.9, -2.0, 0.6, 1.1, 1.7, RIM)]
		tool = Voxels.make(tool_blocks)
		tool.name = "Tool"
		tool.position = Vector3(5.2, 6.3, 0) * UNIT
		add_child(tool)
	set_live(data)


func _body_blocks(mark_two: bool) -> Array:
	var blocks: Array = []
	if not is_space:
		# Repair: wheeled service robot and wrench. Battle: an armored torso,
		# articulated claws and feet. Ion boarder: conductive antenna vanes.
		var armored := family != "repair"
		blocks = [_b(0, 5.0, 0, 6.4 if armored else 5.5, 5.0, 4.8, STEEL),
			_b(0, 3.0, 0, 6.8 if armored else 5.8, 1.0, 5.0, DARK),
			_b(0, 8.8, 0, 4.7, 2.5, 5.2, DARK), _b(0, 10.0, 0.5, 5.2, 0.6, 4.2, STEEL),
			_b(0, 9.0, -2.8, 3.5, 1.5, 0.4, BLACK), _b(0, 5.2, -2.6, 2.8, 2.0, 0.5, DARK)]
		for side in [-1.0, 1.0]:
			blocks.append(_b(side * 4.1, 6.6, 0, 2.0, 2.0, 3.0, BRASS if not armored else STEEL))
			blocks.append(_b(side * 5.2, 5.2, 0, 0.9, 2.0, 1.2, DARK))
			if armored:
				blocks.append(_b(side * 2.0, 1.8, 0, 1.8, 2.5, 2.0, DARK))
				blocks.append(_b(side * 2.0, 0.6, -0.8, 2.4, 1.2, 4.1, STEEL))
				blocks.append(_b(side * 4.3, 6.6, -0.5, 2.7, 1.2, 3.8, RIM))
			else:
				blocks.append(_b(side * 2.7, 1.0, 0, 1.8, 2.0, 5.5, DARK))
				for z in [-1.8, 0.0, 1.8]: blocks.append(_b(side * 3.7, 1.0, z, 0.3, 1.3, 0.7, RIM))
		blocks.append(_b(-5.1, 3.7, -0.7, 1.4, 1.2, 2.8, STEEL))
		if family == "ion_boarder":
			for side in [-1.0, 1.0]:
				blocks.append(_b(side * 2.0, 11.2, 0, 0.8, 2.0, 2.3, Color("6aa8c5")))
				blocks.append(_b(side * 3.2, 5.4, -2.9, 0.6, 3.8, 0.8, Color("6aa8c5")))
		return blocks
	match family:
		"hacking":
			blocks = [_b(0, 0, 0, 8.5, 3.7, 8.5, DARK), _b(0, 1.7, 0, 5.8, 1.5, 5.8, STEEL),
				_b(0, 2.5, 0, 3.5, 0.6, 3.5, BLACK), _b(-4.5, 0, 0, 2.2, 2.8, 2.8, STEEL)]
			for side in [-1.0, 1.0]:
				for end in [-1.0, 1.0]:
					blocks.append(_b(side * 4.8, -0.5, end * 4.2, 2.0, 1.3, 3.2, STEEL))
					blocks.append(_b(side * 5.2, -2.5, end * 5.4, 1.1, 3.2, 1.1, BRASS))
					blocks.append(_b(side * 4.7, -4.0, end * 5.4, 2.1, 0.7, 1.3, DARK))
		"shield":
			blocks = [_b(0, -0.6, 0, 6.0, 3.0, 6.0, DARK), _b(0, 1.0, 0, 3.0, 1.0, 3.0, STEEL)]
			for side in [-1.0, 1.0]:
				blocks.append(_b(0, 0, side * 6.2, 7.2, 2.0, 4.2, STEEL))
				blocks.append(_b(side * 6.2, 0, 0, 4.2, 2.0, 7.2, STEEL))
				blocks.append(_b(0, 1.1, side * 6.2, 5.0, 0.5, 2.8, DARK))
				blocks.append(_b(side * 6.2, 1.1, 0, 2.8, 0.5, 5.0, DARK))
				blocks.append(_b(side * 4.7, -1.0, side * 4.7, 2.8, 0.8, 2.8, BRASS))
		"boarding":
			blocks = [_b(-1, 0, 0, 13.0, 5.0, 7.0, STEEL), _b(4.7, 0, 0, 5.0, 4.0, 6.0, DARK),
				_b(7.7, 0, 0, 1.2, 3.0, 4.0, BRASS), _b(-6.0, 0, 0, 2.0, 6.0, 8.5, DARK),
				_b(-1, 2.7, 0, 7.0, 0.7, 4.0, RIM)]
			for side in [-1.0, 1.0]:
				blocks.append(_b(-2.0, -0.5, side * 4.6, 8.0, 1.0, 2.4, DARK))
				blocks.append(_b(-6.6, 0, side * 2.5, 2.5, 2.5, 2.4, STEEL))
				blocks.append(_b(3.5, 0, side * 3.4, 0.7, 4.0, 1.0, BRASS))
		_:
			blocks = [_b(-1.5, -1.4, 0, 12.0, 2.0, 8.0, DARK), _b(-1.0, 0, 0, 11.0, 3.8, 7.0, STEEL),
				_b(-2.2, 2.2, 0, 6.0, 1.1, 5.0, RIM), _b(-6.5, 0, 0, 2.0, 3.0, 6.5, DARK)]
			for side in [-1.0, 1.0]:
				blocks.append(_b(-2.8, -0.7, side * 4.4, 7.6, 1.1, 3.0, DARK))
				blocks.append(_b(-4.5, -0.3, side * 5.4, 6.4, 2.6, 3.0, STEEL))
				blocks.append(_b(-7.4, -0.3, side * 5.4, 1.0, 2.2, 2.6, BLACK))
				blocks.append(_b(-2.5, 1.2, side * 5.4, 1.0, 0.5, 2.8, BRASS))
				for x in [-4.2, -2.8, -1.4]: blocks.append(_b(x, 1.5, side * 2.6, 0.5, 0.5, 1.1, DARK))
			match family:
				"beam":
					blocks.append(_b(5.4, 0, 0, 10.0, 2.0, 4.5, DARK))
					for side in [-1.0, 1.0]:
						blocks.append(_b(9.0, 0, side * 2.9, 7.0, 2.5, 1.3, BRASS))
						blocks.append(_b(12.0, 0, side * 2.9, 1.0, 3.2, 1.8, RIM))
					blocks.append(_b(3.1, 1.4, 0, 2.5, 0.8, 4.0, BRASS))
				"defense", "anti_drone":
					blocks.append(_b(1.3, 2.0, 0, 5.8, 2.0, 5.8, DARK))
					blocks.append(_b(1.3, 3.1, 0, 4.2, 0.6, 4.2, STEEL))
					for z in ([-1.5, 1.5] if mark_two else [0.0]):
						blocks.append(_b(6.0, 2.4, z, 8.0, 1.3, 1.3, DARK))
						blocks.append(_b(9.7, 2.4, z, 1.2, 2.0, 2.0, RIM))
					for side in [-1.0, 1.0]:
						blocks.append(_b(-1.5, 0, side * 8.0, 9.0, 0.8, 2.0, BRASS))
						blocks.append(_b(-4.7, 2.0, side * 5.4, 0.5, 4.0, 0.5, DARK))
					if family == "anti_drone":
						blocks.append(_b(4.5, 1.7, -4.2, 7.0, 1.0, 1.0, BRASS))
						blocks.append(_b(4.5, 1.7, 4.2, 7.0, 1.0, 1.0, BRASS))
				_:
					for z in ([-1.8, 1.8] if mark_two else [0.0]):
						blocks.append(_b(7.3, 0.3, z, 10.5, 2.0, 2.0, DARK))
						blocks.append(_b(11.7, 0.3, z, 1.4, 3.0, 3.0, RIM))
					blocks.append(_b(4.0, 0.7, 0, 1.2, 4.0, 6.0, BRASS))
	return blocks


func set_live(data: Dictionary) -> void:
	live_data = data
	visible = not bool(data.get("dead", false)) and (bool(data.get("deployed", false)) or not is_space)
	var powered := bool(data.get("powered", true))
	firing = bool(data.get("firing", false)) if is_space else bool(data.get("fighting", false))
	thruster.visible = is_space and visible and powered
	emitter.visible = visible and powered
	var material: StandardMaterial3D = emitter.material_override
	material.emission_energy_multiplier = 1.5 if firing else 0.25


func animate(delta: float) -> void:
	animation_time += delta
	if thruster.visible:
		thruster.scale.x = 0.88 + sin(animation_time * 28.0) * 0.12
	if tool != null:
		tool.rotation.x = 0.0
		if firing:
			tool.rotation.x = 0.7 + sin(animation_time * 9.0) * 0.5
		elif bool(live_data.get("repairing", false)):
			tool.rotation.x = 0.55 + sin(animation_time * 11.0) * 0.35


func _glow_mesh(blocks: Array, color: Color) -> MeshInstance3D:
	# Interior robots have no exhaust; keep a harmless hidden mesh for the
	# shared animation interface rather than creating an empty surface.
	if blocks.is_empty(): blocks = [_b(0, 0, 0, 0.1, 0.1, 0.1, color)]
	var node := Voxels.make(blocks)
	var material: StandardMaterial3D = node.material_override
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return node


func _b(x: float, y: float, z: float, w: float, h: float, d: float, color: Color) -> Array:
	return Voxels.block(Vector3(x, y, z) * UNIT, Vector3(w, h, d) * UNIT, color)
