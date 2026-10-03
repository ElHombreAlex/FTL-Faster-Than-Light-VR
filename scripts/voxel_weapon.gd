extends Node3D

const Voxels = preload("res://scripts/voxel_mesh.gd")
var kind := "laser"
var weapon_name := ""
var body: Node3D
var emitter: MeshInstance3D
var charge_strip: MeshInstance3D
var charge_fill: MeshInstance3D
var charge_pips: Array[MeshInstance3D] = []
var charge_level := 0
var charge_max := 1
var live_signature := ""
var muzzle_color := Color.WHITE
var charge := 0.0
var powered := false
var recoil := 0.0
var last_firing := false


func build(data: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	charge_pips.clear()
	live_signature = ""
	last_firing = false
	recoil = 0.0
	kind = canonical_kind(str(data.get("kind", "laser")))
	weapon_name = str(data.get("name", ""))
	body = Node3D.new()
	add_child(body)
	var steel := Color("778e9b")
	var dark := Color("293944")
	var black := Color("141f28")
	var rim := Color("c2ccd0")
	var blocks := [Voxels.block(Vector3(0, 0.0, 0), Vector3(0.12, 0.035, 0.12), dark),
		Voxels.block(Vector3(0, -0.065, 0), Vector3(0.06, 0.115, 0.06), steel),
		Voxels.block(Vector3(0, -0.13, 0), Vector3(0.14, 0.015, 0.12), dark),
		Voxels.block(Vector3(-0.047, 0.007, 0), Vector3(0.013, 0.048, 0.086), rim)]
	var glow := Color("ef4940")
	var emitter_position := Vector3(0.171, 0.047, 0)
	var emitter_size := Vector3(0.008, 0.023, 0.025)
	var emitter_blocks: Array = []
	match kind:
		"missile":
			blocks.append(Voxels.block(Vector3(0.01, 0.048, 0), Vector3(0.17, 0.075, 0.118), steel))
			blocks.append(Voxels.block(Vector3(-0.06, 0.052, 0), Vector3(0.026, 0.099, 0.135), dark))
			for z in [-0.028, 0.028]:
				blocks.append(Voxels.block(Vector3(0.098, 0.05, z), Vector3(0.025, 0.050, 0.049), rim))
				blocks.append(Voxels.block(Vector3(0.112, 0.05, z), Vector3(0.006, 0.035, 0.033), black))
				blocks.append(Voxels.block(Vector3(-0.04, 0.091, z), Vector3(0.10, 0.013, 0.015), Color("e3ae68")))
				emitter_blocks.append(Voxels.block(Vector3(0.117, 0.05, z), Vector3(0.008, 0.027, 0.027), Color("ffbf5c")))
			emitter_position = Vector3(0.117, 0.05, 0)
			emitter_size = Vector3(0.008, 0.011, 0.077)
			glow = Color("ffbf5c")
		"beam":
			blocks.append(Voxels.block(Vector3(0.0, 0.044, 0), Vector3(0.12, 0.065, 0.08), steel))
			blocks.append(Voxels.block(Vector3(0.075, 0.064, 0), Vector3(0.15, 0.028, 0.10), dark))
			for z in [-0.045, 0.045]:
				blocks.append(Voxels.block(Vector3(0.13, 0.054, z), Vector3(0.12, 0.045, 0.018), rim))
				blocks.append(Voxels.block(Vector3(0.152, 0.056, z), Vector3(0.017, 0.061, 0.028), Color("a79566")))
			blocks.append(Voxels.block(Vector3(-0.032, 0.066, 0), Vector3(0.038, 0.024, 0.10), rim))
			emitter_position = Vector3(0.17, 0.055, 0)
			emitter_size = Vector3(0.011, 0.025, 0.062)
			glow = Color("ffdd75")
		"bomb":
			blocks.append(Voxels.block(Vector3(0, 0.06, 0), Vector3(0.12, 0.10, 0.10), steel))
			blocks.append(Voxels.block(Vector3(0.075, 0.06, 0), Vector3(0.055, 0.07, 0.075), dark))
			for z in [-0.06, 0.06]:
				blocks.append(Voxels.block(Vector3(0, 0.06, z), Vector3(0.065, 0.07, 0.018), Color("b591b7")))
			blocks.append(Voxels.block(Vector3(0.039, 0.073, 0), Vector3(0.014, 0.087, 0.098), rim))
			blocks.append(Voxels.block(Vector3(0.008, 0.106, 0), Vector3(0.049, 0.016, 0.049), dark))
			emitter_position = Vector3(0.109, 0.062, 0)
			emitter_size = Vector3(0.011, 0.039, 0.040)
			glow = Color("cf83ff")
		"ion":
			blocks.append(Voxels.block(Vector3(0, 0.04, 0), Vector3(0.115, 0.06, 0.09), steel))
			for x in [0.045, 0.075, 0.105]:
				blocks.append(Voxels.block(Vector3(x, 0.044, 0), Vector3(0.018, 0.075, 0.075), Color("548dba")))
				blocks.append(Voxels.block(Vector3(x, 0.084, 0), Vector3(0.016, 0.006, 0.059), rim))
			blocks.append(Voxels.block(Vector3(0.083, 0.044, 0), Vector3(0.12, 0.025, 0.025), dark))
			blocks.append(Voxels.block(Vector3(0.146, 0.044, 0), Vector3(0.016, 0.045, 0.045), dark))
			emitter_position = Vector3(0.155, 0.044, 0)
			emitter_size = Vector3(0.006, 0.028, 0.028)
			glow = Color("6ae0ff")
		"flak":
			blocks.append(Voxels.block(Vector3(0, 0.048, 0), Vector3(0.12, 0.075, 0.115), steel))
			for z in [-0.038, 0.0, 0.038]:
				blocks.append(Voxels.block(Vector3(0.098, 0.05, z), Vector3(0.145, 0.027, 0.027), dark))
				blocks.append(Voxels.block(Vector3(0.157, 0.05, z), Vector3(0.022, 0.035, 0.035), rim))
				emitter_blocks.append(Voxels.block(Vector3(0.170, 0.05, z), Vector3(0.006, 0.018, 0.018), Color("f9a451")))
			for z in [-0.070, 0.070]:
				blocks.append(Voxels.block(Vector3(-0.024, 0.041, z), Vector3(0.082, 0.057, 0.028), Color("988e72")))
			emitter_position = Vector3(0.170, 0.05, 0)
			emitter_size = Vector3(0.006, 0.018, 0.090)
			glow = Color("f9a451")
		_:
			blocks.append(Voxels.block(Vector3(0, 0.041, 0), Vector3(0.13, 0.065, 0.085), steel))
			var barrels := 2 if weapon_name.contains("BURST") or weapon_name.contains("DUAL") else 1
			for i in range(barrels):
				var z := (i - (barrels - 1) * 0.5) * 0.043
				blocks.append(Voxels.block(Vector3(0.10, 0.047, z), Vector3(0.14, 0.033, 0.026), dark))
				blocks.append(Voxels.block(Vector3(0.165, 0.047, z), Vector3(0.02, 0.046, 0.04), rim))
				emitter_blocks.append(Voxels.block(Vector3(0.176, 0.047, z), Vector3(0.007, 0.025, 0.026), glow))
			blocks.append(Voxels.block(Vector3(-0.025, 0.079, 0), Vector3(0.07, 0.013, 0.055), Color("a06155")))
			blocks.append(Voxels.block(Vector3(0.074, 0.046, 0), Vector3(0.019, 0.055, 0.094), steel))
			if weapon_name.contains("HEAVY"):
				blocks.append(Voxels.block(Vector3(0.122, 0.047, 0), Vector3(0.086, 0.057, 0.071), steel))
	# Cooling fins and a green charge strip on the upper armor remain readable
	# from a tabletop angle, rather than a subtle glow hidden inside a barrel.
	for x in [-0.052, -0.035, -0.018]:
		for z in [-0.052, 0.052]:
			blocks.append(Voxels.block(Vector3(x, 0.037, z), Vector3(0.008, 0.055, 0.012), rim))
	for x in [-0.046, 0.049]:
		blocks.append(Voxels.block(Vector3(x, 0.101, 0), Vector3(0.014, 0.043, 0.034), steel))
	body.add_child(Voxels.make(blocks))
	muzzle_color = glow
	if emitter_blocks.is_empty():
		emitter_blocks.append(Voxels.block(emitter_position, emitter_size, glow))
	emitter = Voxels.make(emitter_blocks)
	var material: StandardMaterial3D = emitter.material_override
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 0.0
	body.add_child(emitter)
	charge_strip = Voxels.make([Voxels.block(Vector3(0.004, 0.122, 0), Vector3(0.125, 0.012, 0.047), dark),
		Voxels.block(Vector3(0.004, 0.129, -0.024), Vector3(0.127, 0.005, 0.006), rim),
		Voxels.block(Vector3(0.004, 0.129, 0.024), Vector3(0.127, 0.005, 0.006), rim)])
	body.add_child(charge_strip)
	charge_fill = _indicator(Vector3.ZERO, Vector3(1.0, 0.006, 0.033))
	charge_fill.position.y = 0.131
	body.add_child(charge_fill)
	charge_max = clampi(int(data.get("charge_max", 1)), 1, 8)
	if charge_max > 1:
		for i in range(charge_max):
			var pip := _indicator(Vector3.ZERO, Vector3(0.014, 0.007, 0.013))
			pip.position = Vector3(-0.046 + i * 0.018, 0.134, -0.037)
			body.add_child(pip)
			charge_pips.append(pip)
	set_live(data)


func _indicator(center: Vector3, size: Vector3) -> MeshInstance3D:
	var indicator: MeshInstance3D = Voxels.make([Voxels.block(center, size, Color.WHITE)])
	var material: StandardMaterial3D = indicator.material_override
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color("84dc7c")
	material.emission_energy_multiplier = 0.3
	return indicator


func set_live(data: Dictionary) -> void:
	powered = bool(data.get("powered", false))
	charge = clampf(float(data.get("charge_fraction", float(data.get("charge", 0)) / maxf(float(data.get("cooldown", 1)), 0.001))), 0.0, 1.0)
	charge_level = clampi(int(data.get("charge_level", 0)), 0, charge_max)
	var firing := bool(data.get("firing", false))
	if firing and not last_firing:
		recoil = 0.018
	last_firing = firing
	var next := str(powered) + ":" + str(charge) + ":" + str(charge_level)
	if live_signature != next:
		live_signature = next
		var material: StandardMaterial3D = emitter.material_override
		material.emission_energy_multiplier = (0.15 + charge * 1.8) if powered else 0.0
		emitter.visible = powered
		charge_fill.visible = powered and charge > 0.001
		charge_fill.scale.x = maxf(0.001, charge * 0.11)
		charge_fill.position.x = -0.051 + charge * 0.055
		var indicator_material: StandardMaterial3D = charge_fill.material_override
		indicator_material.albedo_color = Color("92e87d") if charge > 0.995 else Color("b8d97a")
		for i in range(charge_pips.size()):
			charge_pips[i].material_override.albedo_color = Color("92e87d") if powered and i < charge_level else Color("2a4245")


func animate(delta: float) -> void:
	recoil = maxf(0.0, recoil - delta * 0.12)
	body.position.x = -recoil


static func canonical_kind(native_kind: String) -> String:
	return {"missiles": "missile", "burst": "flak"}.get(native_kind.to_lower(), native_kind.to_lower())
