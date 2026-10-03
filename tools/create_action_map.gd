extends SceneTree

# Explicit Steam Frame bindings; Godot's generic/Touch bindings remain fallbacks.
func _initialize() -> void:
	var map := OpenXRActionMap.new()
	map.create_default_action_sets()
	var actions := {}
	for action in map.get_action_set(0).get_actions():
		actions[action.resource_name] = action
	var custom := {"page_left":"left","page_right":"left","tactical_button":"left",
		"power_remove":"left","power_previous":"right","power_next":"right","wheel_button":"right"}
	for name in custom:
		var action := OpenXRAction.new()
		action.resource_name = name
		action.localized_name = str(name).replace("_"," ").capitalize()
		action.action_type = OpenXRAction.OPENXR_ACTION_BOOL
		action.toplevel_paths = PackedStringArray(["/user/hand/" + custom[name]])
		map.get_action_set(0).add_action(action)
		actions[name] = action
	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = "/interaction_profiles/valve/frame_controller_valve"
	var bindings: Array[OpenXRIPBinding] = []
	for hand in ["left", "right"]:
		var prefix := "/user/hand/%s/" % hand
		var paths := {"default_pose": "input/aim/pose", "aim_pose": "input/aim/pose",
			"grip_pose": "input/grip/pose", "trigger": "input/trigger/value",
			"trigger_click": "input/trigger/click", "grip": "input/squeeze/value",
			"grip_click": "input/squeeze/click", "primary": "input/thumbstick",
			"primary_click": "input/thumbstick/click", "haptic": "output/haptic",
			"by_button": "input/dpad_up/click" if hand == "left" else "input/b/click",
			"menu_button": "input/view/click" if hand == "left" else "input/menu/click"}
		# The vendor profile in the installed SteamVR Frame driver declares X/Y
		# on the right controller. The left controller has the Dpad and View.
		if hand == "left":
			paths.merge({"page_left":"input/dpad_left/click","page_right":"input/dpad_right/click",
				"tactical_button":"input/dpad_down/click","power_remove":"input/bumper/click"})
		else:
			paths.merge({"ax_button":"input/a/click","power_previous":"input/x/click",
				"power_next":"input/y/click","wheel_button":"input/bumper/click"})
		for name in paths:
			var binding := OpenXRIPBinding.new()
			binding.action = actions[name]
			binding.binding_path = prefix + paths[name]
			bindings.append(binding)
	profile.set_bindings(bindings)
	map.add_interaction_profile(profile)
	var path := "res://openxr_action_map.tres"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): path = argument.trim_prefix("--output=")
	var error := ResourceSaver.save(map, path)
	print("FTLVR action map saved: ", error)
	quit(error)
