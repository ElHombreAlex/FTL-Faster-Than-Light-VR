extends RefCounted

# Follow the headset first. Only the panel's path toward the ship engages the
# world-height stop, so a distant or side-on table never drags the HUD around.
const CLEARANCE := 0.08
const HEAD_OFFSET := Vector3(0.0, -0.12, -1.30)
const POSITION_TIME := 0.12
const PANEL_THICKNESS := 0.008
var initialized := false
var blocked := false
var lift := 0.0
var pose := Transform3D.IDENTITY


func reset() -> void:
	initialized = false
	blocked = false
	lift = 0.0


static func transformed_bounds(local: AABB, transform: Transform3D) -> AABB:
	var result := AABB(transform * local.position, Vector3.ZERO)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				result = result.expand(transform * (local.position + local.size * Vector3(x, y, z)))
	return result


static func panel_bounds(transform: Transform3D, dimensions: Vector2) -> AABB:
	var half := transform.basis.x.abs() * dimensions.x * 0.5 + transform.basis.y.abs() * dimensions.y * 0.5
	return AABB(transform.origin - half, half * 2.0)


static func _boxes_intersect(first: Transform3D, first_box: AABB, second: Transform3D, second_box: AABB, margin := 0.0) -> bool:
	# Separate the oriented boxes on face normals and edge cross products. A
	# world AABB alone can stop the HUD beside a rotated ship with empty space.
	var first_axes: Array[Vector3] = [first.basis.x.normalized(), first.basis.y.normalized(), first.basis.z.normalized()]
	var second_axes: Array[Vector3] = [second.basis.x.normalized(), second.basis.y.normalized(), second.basis.z.normalized()]
	var first_half := first_box.size * Vector3(first.basis.x.length(), first.basis.y.length(), first.basis.z.length()) * 0.5
	var second_half := second_box.size * Vector3(second.basis.x.length(), second.basis.y.length(), second.basis.z.length()) * 0.5 + Vector3.ONE * margin
	var separation := second * second_box.get_center() - first * first_box.get_center()
	var axes: Array[Vector3] = []
	axes.append_array(first_axes)
	axes.append_array(second_axes)
	for first_axis in first_axes:
		for second_axis in second_axes:
			var cross := first_axis.cross(second_axis)
			if cross.length_squared() > 0.000001:
				axes.append(cross.normalized())
	for axis in axes:
		var first_radius := 0.0
		var second_radius := 0.0
		for index in range(3):
			first_radius += absf(axis.dot(first_axes[index])) * first_half[index]
			second_radius += absf(axis.dot(second_axes[index])) * second_half[index]
		if absf(axis.dot(separation)) > first_radius + second_radius:
			return false
	return true


static func overlaps_ship(panel: Transform3D, dimensions: Vector2, ship_transform: Transform3D, local_bounds: AABB, margin := 0.0) -> bool:
	var half := Vector3(dimensions.x * 0.5, dimensions.y * 0.5, PANEL_THICKNESS)
	return _boxes_intersect(panel, AABB(-half, half * 2.0), ship_transform, local_bounds, margin)


static func _facing(point: Vector3, viewer: Transform3D) -> Basis:
	var toward := viewer.origin - point
	if toward.length_squared() < 0.0001:
		toward = viewer.basis.z
	var up := viewer.basis.y.normalized()
	if absf(toward.normalized().dot(up)) > 0.98:
		up = viewer.basis.z.normalized()
	return Basis.looking_at(toward, up, true)


static func _clear_position(point: Vector3, basis: Basis, dimensions: Vector2, ship: AABB) -> Vector3:
	var half := basis.x.abs() * dimensions.x * 0.5 + basis.y.abs() * dimensions.y * 0.5
	point.y = maxf(point.y, ship.end.y + CLEARANCE + half.y + PANEL_THICKNESS)
	return point


func update(ship_transform: Transform3D, local_bounds: AABB, viewer: Transform3D, dimensions: Vector2, delta: float, snap := false) -> Transform3D:
	var desired := viewer * Transform3D(Basis.IDENTITY, HEAD_OFFSET)
	var path_length := viewer.origin.distance_to(desired.origin)
	var path := Transform3D(Basis.looking_at(desired.origin - viewer.origin, viewer.basis.y), (viewer.origin + desired.origin) * 0.5)
	var path_box := AABB(Vector3(0, 0, -path_length * 0.5), Vector3(0, 0, path_length))
	# The full panel handles edge contact. Its center's viewing path also stops
	# a large downward head motion tunnelling the panel entirely below the hull.
	# Sweeping its full width all the way to the face would unnecessarily clamp
	# it when looking away from a table close behind the viewer.
	blocked = overlaps_ship(desired, dimensions, ship_transform, local_bounds, CLEARANCE) or _boxes_intersect(path, path_box, ship_transform, local_bounds, CLEARANCE)
	var target_lift := 0.0
	var ship := transformed_bounds(local_bounds, ship_transform)
	if blocked:
		var target := desired.origin
		var target_basis := desired.basis
		for iteration in range(6):
			target = _clear_position(target, target_basis, dimensions, ship)
			target_basis = _facing(target, viewer)
		target_lift = maxf(0.0, target.y - desired.origin.y)
	# Head motion itself is immediate. Smooth only release of the clearance
	# offset; raising it immediately prevents a fast grab crossing the panel.
	if not initialized or snap or target_lift >= lift:
		lift = target_lift
	else:
		var amount := 1.0 - exp(-maxf(delta, 0.0) / POSITION_TIME)
		lift = lerpf(lift, target_lift, amount)
		if lift < 0.0001:
			lift = 0.0
	pose = desired
	pose.origin.y += lift
	if lift > 0.0:
		pose.basis = _facing(pose.origin, viewer)
	# A raised ship can meet the releasing panel even after the desired head
	# pose has left its path. Enforce clearance for that actual pose as well.
	if blocked or overlaps_ship(pose, dimensions, ship_transform, local_bounds, CLEARANCE):
		for iteration in range(6):
			pose.origin = _clear_position(pose.origin, pose.basis, dimensions, ship)
			pose.basis = _facing(pose.origin, viewer)
		lift = maxf(0.0, pose.origin.y - desired.origin.y)
	initialized = true
	return pose
