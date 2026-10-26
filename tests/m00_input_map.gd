extends SceneTree
## M00 only: validate the loaded InputMap against system specification section 2.
## Run: godot --headless --path . --script res://tests/m00_input_map.gd

var failures: Array[String] = []
var checked_events := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var expected := {
		"move_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
		"move_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
		"move_up": [["key", KEY_W], ["key", KEY_UP], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
		"move_down": [["key", KEY_S], ["key", KEY_DOWN], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
		"jump": [["key", KEY_SPACE], ["button", JOY_BUTTON_A]],
		"attack": [["key", KEY_J], ["mouse", MOUSE_BUTTON_LEFT], ["button", JOY_BUTTON_X]],
		"dodge": [["key", KEY_K], ["button", JOY_BUTTON_B]],
		"guard": [["key", KEY_I], ["button", JOY_BUTTON_LEFT_SHOULDER], ["mouse", MOUSE_BUTTON_RIGHT]],
		"target_attack": [], # Reserved legacy action; no mouse attack binding.
		"camera_left": [["key", KEY_Q], ["axis", JOY_AXIS_RIGHT_X, -1.0]],
		"camera_right": [["key", KEY_E], ["axis", JOY_AXIS_RIGHT_X, 1.0]],
		"lock_on": [["key", KEY_L], ["button", JOY_BUTTON_RIGHT_STICK]],
		"interact": [["key", KEY_F], ["button", JOY_BUTTON_Y]],
		"pause": [["key", KEY_ESCAPE], ["button", JOY_BUTTON_START]],
	}
	for action in expected:
		_check(InputMap.has_action(action), "Missing action: " + action)
		if not InputMap.has_action(action):
			continue
		_check(is_equal_approx(InputMap.action_get_deadzone(action), 0.2), action + ": deadzone")
		var actual: Array = []
		for event in InputMap.action_get_events(action):
			actual.append(_describe(event))
		_check(actual.size() == expected[action].size(), action + ": binding count")
		for binding in expected[action]:
			_check(binding in actual, action + ": missing binding " + str(binding))
			var event := _make_event(binding)
			_check(InputMap.event_is_action(event, action), action + ": event not recognized " + str(binding))
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_check(Input.is_action_pressed(action), action + ": press not recognized " + str(binding))
			event = event.duplicate()
			if event is InputEventJoypadMotion:
				event.axis_value = 0.0
			else:
				event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			_check(not Input.is_action_pressed(action), action + ": release not recognized " + str(binding))
			checked_events += 1
	_check(Engine.physics_ticks_per_second == 60, "Physics tick rate must be 60")
	var scene = load(ProjectSettings.get_setting("application/run/main_scene"))
	_check(scene is PackedScene, "Main scene did not load")
	if scene is PackedScene:
		var instance = scene.instantiate()
		_check(instance is Node3D, "Main scene root must be Node3D")
		instance.free()
	if failures.is_empty():
		print("PASS M00: 14 actions, %d bindings, deadzones, synthetic press/release, 60 physics ticks, main scene" % checked_events)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _describe(event: InputEvent) -> Array:
	if event is InputEventKey:
		return ["key", event.physical_keycode]
	if event is InputEventMouseButton:
		return ["mouse", event.button_index]
	if event is InputEventJoypadButton:
		return ["button", event.button_index]
	if event is InputEventJoypadMotion:
		return ["axis", event.axis, event.axis_value]
	return ["unexpected"]

func _make_event(binding: Array) -> InputEvent:
	var event: InputEvent
	match binding[0]:
		"key":
			event = InputEventKey.new()
			event.physical_keycode = binding[1]
			event.pressed = true
		"mouse":
			event = InputEventMouseButton.new()
			event.button_index = binding[1]
			event.pressed = true
		"button":
			event = InputEventJoypadButton.new()
			event.button_index = binding[1]
			event.pressed = true
		"axis":
			event = InputEventJoypadMotion.new()
			event.axis = binding[1]
			event.axis_value = binding[2]
	return event
