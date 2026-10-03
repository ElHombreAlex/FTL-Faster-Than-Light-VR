extends "res://scripts/main.gd"

var profile_poll_ms: Array[float] = []
var profile_process_ms: Array[float] = []


func _poll_bridge_state() -> void:
	var started := Time.get_ticks_usec()
	super._poll_bridge_state()
	profile_poll_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	super._process(delta)
	profile_process_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
