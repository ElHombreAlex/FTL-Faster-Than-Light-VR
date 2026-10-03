extends "res://scripts/main.gd"
var commands: Array = []
func _command(action: String, data: Dictionary) -> void:
	commands.append({"action": action, "data": data})
