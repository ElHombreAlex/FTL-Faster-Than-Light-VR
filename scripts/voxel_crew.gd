extends Node3D

const Voxels = preload("res://scripts/voxel_mesh.gd")
const UNIT := 0.012
const SPECIES := ["human", "engi", "mantis", "rock", "slug", "energy", "crystal", "lanius"]
var species := "human"
var animation_state := "idle"
var animation_time := 0.0
var torso: Node3D
var head: Node3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var tool: Node3D
var facing := 0.0
var viewer_facing_valid := false


func build(race: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	arms.clear()
	legs.clear()
	species = canonical_species(race)
	if not SPECIES.has(species):
		species = "human"
	torso = Node3D.new()
	torso.name = "Torso"
	add_child(torso)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 8.4, 0) * UNIT
	torso.add_child(head)
	var dark := Color("253744")
	var light := Color("b9c8cc")
	var eye := Color("a4f4ff")
	var body_blocks: Array = []
	var head_blocks: Array = []
	var arm_blocks: Array = []
	var leg_blocks: Array = []
	match species:
		"human":
			body_blocks = [_b(0, 5.4, 0, 4.2, 4.8, 2.6, Color("467da6")), _b(0, 3.3, 0, 4.3, 0.7, 2.8, dark), _b(0, 6.3, -1.5, 1.4, 1.4, 0.5, Color("ffd777"))]
			head_blocks = [_b(0, 0.8, 0, 3.2, 3.1, 3.0, Color("c89571")), _b(0, 2.2, 0.2, 3.4, 0.8, 3.2, Color("5a392c")), _b(-0.7, 0.9, -1.55, 0.55, 0.6, 0.2, dark), _b(0.7, 0.9, -1.55, 0.55, 0.6, 0.2, dark)]
			arm_blocks = [_b(0, -1.5, 0, 1.4, 3.3, 1.7, Color("467da6")), _b(0, -3.25, -0.2, 1.3, 1.0, 1.4, Color("c89571"))]
			leg_blocks = [_b(0, -1.5, 0, 1.6, 3.2, 1.8, dark), _b(0, -3.2, -0.4, 1.7, 0.9, 2.5, Color("16232e"))]
		"engi":
			body_blocks = [_b(0, 5.0, 0, 4.6, 3.8, 3.2, light), _b(0, 5.2, -1.8, 2.1, 2.2, 0.6, dark), _b(0, 5.2, -2.15, 1.2, 0.6, 0.2, eye), _b(0, 7.1, 0, 2.0, 1.0, 2.0, dark)]
			head_blocks = [_b(0, 0.5, 0, 3.4, 2.6, 3.0, light), _b(0, 0.7, -1.6, 2.5, 1.1, 0.4, dark), _b(-0.65, 0.7, -1.85, 0.6, 0.6, 0.15, eye), _b(0.65, 0.7, -1.85, 0.6, 0.6, 0.15, eye)]
			arm_blocks = [_b(0, -0.8, 0, 1.6, 1.6, 1.7, light), _b(0, -2, 0, 0.7, 1.1, 0.9, dark), _b(0, -3, -0.2, 1.8, 1.4, 1.7, light)]
			leg_blocks = [_b(0, -0.7, 0, 1.4, 1.5, 1.8, light), _b(0, -1.9, 0, 0.7, 1.0, 1.0, dark), _b(0, -3, -0.5, 1.9, 1.4, 2.7, light)]
		"mantis":
			body_blocks = [_b(0, 5.2, 0, 2.7, 4.5, 2.4, Color("568e3b")), _b(0, 4.1, 1.2, 3.5, 2.3, 3.0, Color("759f45")), _b(0, 7, 0, 2.0, 1.4, 2.1, Color("375d29"))]
			head_blocks = [_b(0, 0.5, -0.5, 3.7, 2.8, 2.7, Color("8fb654")), _b(-1.5, 0.8, -2.0, 0.9, 1.2, 0.7, Color("df5146")), _b(1.5, 0.8, -2.0, 0.9, 1.2, 0.7, Color("df5146")), _b(-1.2, 2.9, 0, 0.35, 2.2, 0.4, dark), _b(1.2, 2.9, 0, 0.35, 2.2, 0.4, dark), _b(-0.9, -1.0, -2.0, 0.5, 1.2, 1.2, Color("e7d09a")), _b(0.9, -1.0, -2.0, 0.5, 1.2, 1.2, Color("e7d09a"))]
			arm_blocks = [_b(0, -1.3, 0, 0.8, 3.3, 1.0, Color("568e3b")), _b(0, -3.2, -0.7, 0.9, 2.3, 1.8, Color("bdd887")), _b(0, -4.5, -1.4, 0.7, 1.2, 0.7, Color("e7d09a"))]
			leg_blocks = [_b(0, -1.4, 0.5, 0.9, 2.8, 1.1, Color("568e3b")), _b(0, -3.0, -0.7, 0.8, 1.4, 2.3, Color("759f45"))]
		"rock":
			body_blocks = [_b(0, 5.1, 0, 6.4, 4.8, 4.3, Color("8c7252")), _b(-2.4, 6.3, 0, 2.5, 3.1, 3.4, Color("ac9065")), _b(2.4, 5.8, 0, 2.3, 3.3, 3.8, Color("74624b")), _b(0.7, 3.4, -2.3, 2.3, 1.9, 0.7, Color("6a563f"))]
			head_blocks = [_b(0, 0.4, 0, 4.6, 3.5, 3.7, Color("ac9065")), _b(-1.8, 1.4, 0.2, 1.2, 2.5, 2.7, Color("8c7252")), _b(0, 0.3, -2.0, 3.1, 0.7, 0.4, dark), _b(-0.8, 0.3, -2.25, 0.7, 0.35, 0.2, Color("ffe4a0")), _b(0.8, 0.3, -2.25, 0.7, 0.35, 0.2, Color("ffe4a0"))]
			arm_blocks = [_b(0, -1.3, 0, 2.3, 3.7, 3.1, Color("8c7252")), _b(0, -3.2, -0.3, 2.6, 1.9, 3.0, Color("ac9065"))]
			leg_blocks = [_b(0, -1.6, 0, 2.3, 3.3, 2.7, Color("74624b")), _b(0, -3.1, -0.5, 2.6, 1.1, 3.4, Color("8c7252"))]
		"slug":
			body_blocks = [_b(0, 3.2, 0.9, 5.4, 3.0, 6.5, Color("846aa8")), _b(0, 5.0, 0, 4.6, 3.8, 4.0, Color("a887c1")), _b(0, 2.0, 3.4, 3.3, 1.7, 3.6, Color("725793")), _b(0, 1.25, 1.0, 5.8, 0.7, 8.2, Color("58446e"))]
			head_blocks = [_b(0, -0.5, 0, 4.5, 2.6, 3.8, Color("a887c1")), _b(-1.5, 1.6, -1.1, 0.7, 3.5, 0.7, Color("a887c1")), _b(1.5, 1.6, -1.1, 0.7, 3.5, 0.7, Color("a887c1")), _b(-1.5, 3.2, -1.2, 1.3, 1.0, 1.1, Color("e1e791")), _b(1.5, 3.2, -1.2, 1.3, 1.0, 1.1, Color("e1e791")), _b(-1.5, 3.2, -1.8, 0.5, 0.7, 0.2, dark), _b(1.5, 3.2, -1.8, 0.5, 0.7, 0.2, dark)]
			arm_blocks = [_b(0, -1.5, -0.3, 1.0, 3.1, 1.4, Color("a887c1")), _b(0, -2.8, -1.1, 1.5, 1.0, 1.5, Color("846aa8"))]
		"energy":
			body_blocks = [_b(0, 5.2, 0, 3.5, 4.7, 2.4, Color("57c282")), _b(0, 5.5, -1.35, 1.0, 3.1, 0.4, Color("b4ffb0")), _b(-1.9, 6.4, 0, 0.6, 2.0, 2.6, Color("91e999")), _b(1.9, 6.4, 0, 0.6, 2.0, 2.6, Color("91e999"))]
			head_blocks = [_b(0, 0.8, 0, 2.7, 3.5, 2.5, Color("8be891")), _b(0, 2.8, 0, 1.8, 1.0, 1.7, Color("b4ffb0")), _b(0, 0.9, -1.4, 1.7, 0.6, 0.3, Color("e6ffd1"))]
			arm_blocks = [_b(0, -1.7, 0, 1.0, 3.7, 1.3, Color("8be891")), _b(0, -3.7, 0, 1.1, 0.6, 1.4, Color("b4ffb0"))]
			leg_blocks = [_b(0, -1.7, 0, 1.1, 3.5, 1.6, Color("57c282")), _b(0, -3.4, -0.3, 1.3, 0.8, 2.1, Color("b4ffb0"))]
		"crystal":
			body_blocks = [_b(0, 5.1, 0, 4.7, 5.0, 3.5, Color("65a6bf")), _b(-1.9, 6.2, 0, 1.7, 4.4, 2.7, Color("b3e3ed")), _b(1.9, 5.4, -0.2, 1.7, 3.2, 3.2, Color("85c4d7")), _b(0, 5.4, -2.0, 1.6, 2.5, 0.7, Color("c9f5f8"))]
			head_blocks = [_b(0, 0.6, 0, 3.5, 3.4, 3.1, Color("85c4d7")), _b(-0.9, 2.8, 0.2, 1.3, 2.0, 1.9, Color("c9f5f8")), _b(1.0, 2.1, 0.4, 1.4, 1.2, 2.2, Color("b3e3ed")), _b(0, 0.8, -1.7, 2.2, 0.6, 0.3, dark)]
			arm_blocks = [_b(0, -1.6, 0, 1.8, 3.8, 2.3, Color("85c4d7")), _b(0, -3.6, -0.2, 1.9, 1.4, 2.4, Color("b3e3ed"))]
			leg_blocks = [_b(0, -1.8, 0, 1.8, 3.7, 2.3, Color("65a6bf")), _b(0, -3.5, -0.5, 2.0, 1.0, 2.8, Color("85c4d7"))]
		"lanius":
			body_blocks = [_b(0, 5.2, 0, 3.4, 4.5, 2.3, Color("9eaaaf")), _b(-1.6, 6.6, 0, 1.3, 2.0, 2.4, Color("d0d8dc")), _b(1.6, 6.6, 0, 1.3, 2.0, 2.4, Color("d0d8dc")), _b(0, 5.0, -1.5, 0.7, 2.7, 0.8, Color("667f8c"))]
			head_blocks = [_b(0, 0.9, 0, 2.7, 3.2, 2.7, Color("d0d8dc")), _b(-1.25, 2.8, 0.3, 0.6, 2.5, 0.7, Color("9eaaaf")), _b(1.25, 2.8, 0.3, 0.6, 2.5, 0.7, Color("9eaaaf")), _b(0, 0.5, -1.6, 1.9, 0.6, 0.4, Color("e7f788"))]
			arm_blocks = [_b(0, -1.5, 0, 1.0, 3.5, 1.4, Color("9eaaaf")), _b(0, -3.4, -0.6, 0.6, 2.2, 1.5, Color("d0d8dc"))]
			leg_blocks = [_b(0, -1.7, 0, 1.0, 3.7, 1.4, Color("9eaaaf")), _b(0, -3.5, -0.7, 0.9, 1.2, 2.9, Color("d0d8dc"))]
	torso.add_child(Voxels.make(body_blocks))
	head.add_child(Voxels.make(head_blocks))
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * (3.4 if species == "rock" else 2.5), 7.0, 0) * UNIT
		arm.add_child(Voxels.make(arm_blocks))
		torso.add_child(arm)
		arms.append(arm)
		if species != "slug":
			var leg := Node3D.new()
			leg.position = Vector3(side * (1.6 if species == "rock" else 1.0), 3.6, 0) * UNIT
			leg.add_child(Voxels.make(leg_blocks))
			torso.add_child(leg)
			legs.append(leg)
	tool = Voxels.make([_b(0, 0, 0, 0.8, 3.5, 0.8, light), _b(0, -1.5, 0, 2.2, 0.8, 1.1, Color("ffc967"))])
	tool.position = Vector3(0, -3.6, -0.8) * UNIT
	arms[1].add_child(tool)
	tool.visible = false
	animate(0.0)


func set_state(crew: Dictionary) -> void:
	var previous_state := animation_state
	if bool(crew.get("fighting", false)):
		animation_state = "fight"
	elif bool(crew.get("repairing", false)):
		animation_state = "repair"
	elif bool(crew.get("running", false)):
		animation_state = "run"
	elif bool(crew.get("working", false)):
		animation_state = "work"
	else:
		animation_state = "idle"
	tool.visible = animation_state == "repair"
	if animation_state != previous_state:
		# Native state changes must select the right pose even when an actor is
		# first seen while paused. Preserve the frozen animation phase.
		animate(0.0)


func face_viewer(deck_direction: Vector3, delta: float) -> void:
	# Rotate around the deck normal only. Looking straight down at an actor
	# must not tip its body or cause unstable yaw from a near-zero projection.
	if animation_state == "run" or Vector2(deck_direction.x, deck_direction.z).length_squared() < 0.0004:
		return
	var target := atan2(-deck_direction.x, -deck_direction.z)
	var difference := wrapf(target - facing, -PI, PI)
	if not viewer_facing_valid:
		facing = target
		viewer_facing_valid = true
	elif absf(difference) > 0.012:
		facing = lerp_angle(facing, target, 1.0 - exp(-delta * 12.0))
	rotation.y = facing


func face_movement(deck_direction: Vector3) -> void:
	if animation_state != "run" or deck_direction.length_squared() < 0.00004:
		return
	facing = atan2(-deck_direction.x, -deck_direction.z)
	rotation.y = facing
	viewer_facing_valid = false


func animate(delta: float) -> void:
	animation_time += delta
	var t := animation_time
	for part in arms + legs:
		part.rotation = Vector3.ZERO
	torso.position = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	match animation_state:
		"run":
			for i in range(legs.size()):
				legs[i].rotation.x = sin(t * 14.0 + i * PI) * 0.65
			for i in range(arms.size()):
				arms[i].rotation.x = sin(t * 14.0 + i * PI + PI) * 0.5
			torso.position.y = absf(sin(t * 14.0)) * 0.004
			torso.rotation.x = -0.12
			if species == "slug":
				torso.scale.z = 1.0 + sin(t * 9.0) * 0.08
		"work":
			arms[0].rotation.x = 0.9 + sin(t * 5.0) * 0.14
			arms[1].rotation.x = 0.9 + sin(t * 5.0 + PI) * 0.14
			head.rotation.x = -0.12
		"repair":
			arms[0].rotation.x = 0.8
			arms[1].rotation.x = 1.0 + sin(t * 11.0) * 0.45
			torso.rotation.x = -0.2
			torso.position.y = -0.005
			head.rotation.x = -0.18
		"fight":
			arms[0].rotation.x = 0.9 + sin(t * 9.0) * 0.65
			arms[1].rotation.x = 0.9 + sin(t * 9.0 + PI) * 0.65
			torso.rotation.y = sin(t * 9.0) * 0.12
			torso.position.z = sin(t * 9.0) * 0.004
		_:
			head.rotation.y = sin(t * 1.4) * 0.06
			torso.position.y = sin(t * 2.0) * 0.001
	if animation_state != "run":
		torso.scale.z = 1.0
	rotation.y = facing


func _b(x: float, y: float, z: float, w: float, h: float, d: float, color: Color) -> Array:
	return Voxels.block(Vector3(x, y, z) * UNIT, Vector3(w, h, d) * UNIT, color)


static func canonical_species(race: String) -> String:
	return {"zoltan": "energy", "anaerobic": "lanius"}.get(race.to_lower(), race.to_lower())
