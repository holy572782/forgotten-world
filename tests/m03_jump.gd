extends SceneTree
## Real engine physics ticks and production callbacks; synthetic inputs, not manual play.
const STEP := 1.0 / 60.0
var main: Node3D
var player: CharacterBody3D
var failures: Array[String] = []
var direction := Vector2.ZERO
var jump_held := false
var jump_sent := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	player = main.get_node("Player")
	player.set_physics_process(false)
	main.get_node("TestArena/Preview/Camera3D").rotation = Vector3.ZERO
	# Use the established world-aligned fixture; M04 tests live camera integration.
	main.get_node("CameraRig").set_physics_process(false)
	player.movement_camera = main.get_node("TestArena/Preview/Camera3D")
	await _reset(Vector3(0, 0, 6))
	jump_held = true
	await _ticks(1)
	_check(player.velocity.y == player.movement.jump_speed and not player.is_on_floor(), "Ground jump initial velocity")
	var apex := player.position.y
	for tick in range(65):
		await _ticks(1)
		apex = maxf(apex, player.position.y)
	_check(player.is_on_floor() and absf(player.position.y) < 0.02, "Held jump lands without automatic repeat")
	_check(apex > 1.15 and apex < 1.35, "Jump apex: " + str(apex))
	jump_held = false
	await _ticks(1)
	jump_held = true
	await _ticks(1)
	_check(player.velocity.y > 6.9, "Jump again after landing and release")
	jump_held = false
	await _ticks(8)
	var before := player.velocity.y
	jump_held = true
	await _ticks(1)
	_check(player.velocity.y < before, "Air repress cannot double jump")
	jump_held = false
	await _ticks(70)
	_check(player.is_on_floor(), "Expired airborne press does not bounce on landing")
	# Short physical-key tap entirely between physics updates.
	await _reset(Vector3(0, 0, 6))
	_key(true)
	_key(false)
	await _ticks(1)
	_check(player.velocity.y > 6.9, "Short key tap is retained")
	# Gamepad south uses the same jump action.
	await _reset(Vector3(0, 0, 6))
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _ticks(1)
	_check(player.velocity.y > 6.9, "Gamepad south jumps")
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	# Leave the existing 2m landing sideways, and jump inside/outside coyote time.
	for delay_ticks in [3, 8]:
		await _reset(Vector3(-4.5, 2, -8))
		direction = Vector2.RIGHT
		var guard := 0
		while player.is_on_floor() and guard < 90:
			await _ticks(1)
			guard += 1
		_check(guard < 90, "Walk off landing")
		await _ticks(delay_ticks)
		jump_held = true
		await _ticks(1)
		_check((player.velocity.y > 6.9) == (delay_ticks == 3), "Coyote window delay ticks=" + str(delay_ticks))
	# Press shortly before touchdown, or too early; only the former bounces.
	for height in [0.25, 2.0]:
		await _reset(Vector3(0, 0, 6))
		player.reset_motion(Vector3(0, height, 6))
		await _ticks(1)
		jump_held = true
		var bounced := false
		for tick in range(80):
			await _ticks(1)
			if player.velocity.y > 6.9:
				bounced = true
		_check(bounced == (height < 1.0), "Landing buffer expiry height=" + str(height))
	# Ramp jump and landing use unchanged M01 collision geometry.
	await _reset(Vector3(-6, 1.1, -3))
	var ramp_y := player.position.y
	jump_held = true
	await _ticks(1)
	_check(not player.is_on_floor() and player.position.y > ramp_y, "Ramp jump detaches from snap")
	jump_held = false
	await _ticks(80)
	_check(player.is_on_floor() and absf(player.position.y - ramp_y) < 0.02, "Land on ramp")
	# Approach each existing riser from its lower neighbour.
	for item in [[3.0, 0.0, 0.25], [1.0, 0.25, 0.5], [-1.0, 0.5, 1.0]]:
		await _reset(Vector3(5, item[1], item[0]))
		direction = Vector2.UP
		jump_held = true
		await _ticks(28)
		direction = Vector2.ZERO
		jump_held = false
		await _ticks(65)
		_check(player.is_on_floor() and absf(player.position.y - float(item[2])) < 0.03, "Jump onto step y=" + str(item[2]) + " at " + str(player.position))
	# 3m wall exceeds jump height; keep colliding while airborne and after landing.
	await _reset(Vector3(3, 0, -7.6))
	direction = Vector2.UP
	jump_held = true
	for tick in range(70):
		await _ticks(1)
		_check(player.position.z > -8.42, "No wall tunnelling")
	_check(player.is_on_floor() and player.is_on_wall(), "High wall cannot be jumped over")
	# Walk off high platform and land on ground without tunnelling.
	await _reset(Vector3(-4.5, 2, -8))
	direction = Vector2.RIGHT
	await _ticks(60)
	_check(player.is_on_floor() and absf(player.position.y) < 0.02, "High platform fall lands on ground")
	# Air acceleration, diagonal cap, reverse, and touchdown acceleration bound.
	await _reset(Vector3(0, 0, 6))
	jump_held = true
	direction = Vector2(1, 1)
	await _ticks(1)
	_check(absf(_speed() - player.movement.acceleration * player.movement.air_control * STEP) < 0.001, "Air acceleration uses 70 percent")
	for tick in range(70):
		if tick == 18:
			direction = Vector2(-1, -1)
		var previous := Vector2(player.velocity.x, player.velocity.z)
		await _ticks(1)
		_check(_speed() <= player.movement.speed + 0.001, "Air diagonal/reversal speed cap")
		_check(Vector2(player.velocity.x, player.velocity.z).distance_to(previous) <= player.movement.acceleration * STEP + 0.001, "No touchdown horizontal speed pop")
	# Recovery after a real open-edge fall, including stale buffered/held input.
	await _reset(Vector3(13, 0, 6))
	direction = Vector2.RIGHT
	var recovered := false
	for tick in range(240):
		if player.position.y < main.fall_reset_height + 1.0:
			jump_held = true
		await _ticks(1)
		if player.position == main.get_node("TestArena/PlayerSpawn").position:
			recovered = true
			break
	_check(recovered and player.velocity == Vector3.ZERO, "Open edge recovery clears all velocity")
	direction = Vector2.ZERO
	await _ticks(20)
	_check(player.is_on_floor() and player.position.y < 0.02, "Held input cannot jump after recovery")
	jump_held = false
	await _ticks(1)
	jump_held = true
	await _ticks(1)
	_check(player.velocity.y > 6.9, "Fresh jump works after recovery")
	# Automatic engine path with actual render caps; physics remains 60Hz.
	for fps in [30, 60]:
		await _reset(Vector3(0, 0, 6))
		Engine.max_fps = fps
		player.set_physics_process(true)
		var start := player.position
		Input.action_press("move_right")
		Input.action_press("jump")
		var max_height := 0.0
		for tick in range(61):
			await physics_frame
			max_height = maxf(max_height, player.position.y)
		player.set_physics_process(false)
		Input.action_release("move_right")
		Input.action_release("jump")
		print("FPS_CAP ", fps, " apex=", max_height, " distance=", player.position.x - start.x)
		_check(max_height > 1.15 and max_height < 1.35 and player.is_on_floor(), "Automatic jump/land FPS cap=" + str(fps))
		_check(absf(player.position.x - start.x - 4.23) < 0.15, "FPS-independent travel cap=" + str(fps))
	Engine.max_fps = 0
	if failures.is_empty():
		print("PASS M03: jump/landing, hold/double prevention, tap/pad, coyote, buffer, ramp/steps/wall, air control, recovery, automatic 30/60 FPS caps")
	else:
		for failure in failures:
			push_error(failure)
	main.free()
	quit(0 if failures.is_empty() else 1)

func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame
		for item in [["move_left", direction.x < 0], ["move_right", direction.x > 0], ["move_up", direction.y < 0], ["move_down", direction.y > 0]]:
			if item[1]:
				Input.action_press(item[0])
			else:
				Input.action_release(item[0])
		if jump_held != jump_sent:
			_key(jump_held)
			jump_sent = jump_held
		player._physics_process(STEP)
		main._physics_process(STEP)
		var sprite: AnimatedSprite3D = player.get_node("AnimatedSprite3D")
		var texture := sprite.sprite_frames.get_frame_texture(&"default", 0)
		_check(absf(sprite.global_position.y - texture.get_height() * sprite.pixel_size / 2.0 - player.global_position.y) < 0.0001, "Sprite feet follow body")

func _reset(at: Vector3) -> void:
	direction = Vector2.ZERO
	jump_held = false
	jump_sent = false
	_key(false)
	player.reset_motion(at)
	await _ticks(15)

func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

func _check(condition: bool, message: String) -> void:
	if not condition and not message in failures:
		failures.append(message)
