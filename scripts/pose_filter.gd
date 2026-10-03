extends RefCounted

var position_deadband := 0.0015
var angle_deadband := deg_to_rad(0.15)
var time_constant := 0.075
var fast_time_constant := 0.025
var initialized := false
var value := Transform3D.IDENTITY


func reset() -> void:
	initialized = false


func update(target: Transform3D, delta: float) -> Transform3D:
	var rotation := target.basis.orthonormalized().get_rotation_quaternion()
	if not initialized:
		value = target
		initialized = true
		return value
	var current := value.basis.orthonormalized().get_rotation_quaternion()
	var distance := value.origin.distance_to(target.origin)
	var angle := current.angle_to(rotation)
	# Reacquired tracking and explicit recentering must not leave a long trail.
	if distance > 0.35 or angle > deg_to_rad(70.0):
		value = target
		return value
	var moving := distance > 0.025 or angle > deg_to_rad(8.0)
	var alpha := 1.0 - exp(-maxf(delta, 0.0) / (fast_time_constant if moving else time_constant))
	if distance > position_deadband:
		value.origin = value.origin.lerp(target.origin, alpha)
	if angle > angle_deadband:
		current = current.slerp(rotation, alpha)
	value.basis = Basis(current).scaled(target.basis.get_scale())
	return value
