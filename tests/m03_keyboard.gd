extends SceneTree
## Synthetic keyboard regression; -- --diagnose displays live input without injecting it.
var main: Node3D
var player: CharacterBody3D
var failures: Array[String] = []
var label: Label
var diagnostic := false
var space_count := 0
var space_was_pressed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode = 0 # Isolate this legacy trial from the F5 enemy.
	# Fixed fixture coordinates; do not change the saved arena placement.
	if not "--diagnose" in OS.get_cmdline_user_args():
		main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	player = main.get_node("Player")
	if "--diagnose" in OS.get_cmdline_user_args():
		label = main.get_node("TestArena/Preview/Instructions/Label")
		diagnostic = true
		return
	main.set_physics_process(false)
	player.set_physics_process(false)
	main.get_node("TestArena/Preview/Camera3D").rotation = Vector3.ZERO
	var directions := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for keys in [[KEY_A, KEY_D, KEY_W, KEY_S], [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]]:
		for direction in directions:
			player.reset_motion(Vector3(0, 0, 6))
			await _ticks(12)
			var selected: Array[int] = []
			if direction.x < 0: selected.append(keys[0])
			if direction.x > 0: selected.append(keys[1])
			if direction.y < 0: selected.append(keys[2])
			if direction.y > 0: selected.append(keys[3])
			for key in selected: _key(key, true)
			await _ticks(5)
			for attempt in range(2):
				_key(KEY_SPACE, true)
				await _ticks(1)
				if player.velocity.y < 6.9 or player.is_on_floor():
					failures.append("Jump failed keys=" + str(selected) + " attempt=" + str(attempt))
				_key(KEY_SPACE, false)
				await _ticks(45)
			for key in selected: _key(key, false)
			await _ticks(1)
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS M03 keyboard: WASD/arrows, all 8 directions + Space, two jumps per combination (32 jumps). Synthetic events only.")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _process(_delta: float) -> bool:
	if diagnostic:
		var space := Input.is_physical_key_pressed(KEY_SPACE)
		if space and not space_was_pressed: space_count += 1
		space_was_pressed = space
		label.text = "KEYBOARD DIAGNOSTIC | Focus this game window\nArrows L:%s R:%s U:%s D:%s\nSpace physical:%s | jump action:%s | Space edges:%d\nGround:%s | vertical velocity:%.2f\nCompare arrows + Space with WASD + Space on flat ground.\nClose this window to exit." % [Input.is_physical_key_pressed(KEY_LEFT), Input.is_physical_key_pressed(KEY_RIGHT), Input.is_physical_key_pressed(KEY_UP), Input.is_physical_key_pressed(KEY_DOWN), space, Input.is_action_pressed("jump"), space_count, player.is_on_floor(), player.velocity.y]
	return false

func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame
		player._physics_process(1.0 / Engine.physics_ticks_per_second)

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
