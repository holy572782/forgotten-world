extends "res://tests/m06_target_dash.gd"
var second: Node3D
var start_times: Array[float] = []
var end_times: Array[float] = []
var stance_ticks := 0

func _action(action: String, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _tap(action: String) -> void:
	_action(action)
	_action(action, false)

func _ticks(count: int) -> void:
	for i in range(count):
		await super._ticks(1)
		if combat._waiting:
			stance_ticks += 1
			_check(sprite.state == &"Stance" and String(sprite.animation).begins_with("walk_"), "Directional walk stance")
			_check(not sprite.is_playing() and sprite.frame == 0, "Stance is a still frame")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = load("res://scenes/main.tscn").instantiate()
	# Use a named fixture so cyclic-order assertions remain independent of demo setup.
	main.get_node("TrainingEnemySecond").free()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	second = load("res://scenes/enemies/training_enemy.tscn").instantiate()
	second.name = "SecondCandidate"
	main.add_child(second)
	second.global_position = Vector3(-8,0,-2)
	var other = second.get_node("Targetable")
	await _ticks(20)
	var origin := player.global_position
	combat.selected_target = null
	player.facing_world = (other.global_position - origin).normalized()
	await _ticks(2)
	_check(combat.selected_target == other, "Initial selection closest to facing")
	_check(other.selected and not target.selected and target.marker.visible, "Filled selected and hollow candidate")
	_check(other.get_node("Marker/Mesh").mesh == other._filled_mesh and target.get_node("Marker/Mesh").mesh == target._hollow_mesh, "Distinct marker meshes")
	player.facing_world = (target.global_position - origin).normalized()
	await _ticks(2)
	_check(combat.selected_target == other, "Existing selection retained despite changed facing")
	var ordered = combat.valid_candidates()
	_tap("lock_on")
	await _ticks(2)
	_check(combat.selected_target == target and target.selected and not other.selected, "L changes selected marker")
	_tap("lock_on")
	await _ticks(2)
	_check(combat.selected_target == other and combat.valid_candidates() == ordered, "Stable cyclic order")
	_tap("lock_on")
	_tap("lock_on")
	await _ticks(2)
	_check(combat.selected_target == other, "Each cycle press retained within one physics tick")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m07_controls_markers.png")
	# Both left and right clicks over UI are consumed.
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		_click(Vector2(20,20),button)
		await _ticks(2)
		_check(not combat.is_busy() and not sprite._attacking, "UI click has no attack or preview")
	_click(Vector2(1100,690),MOUSE_BUTTON_LEFT)
	await _ticks(2)
	_check(not combat.is_busy() and combat.stock.current == 3, "Empty click does not auto-select attack")
	combat.hit.connect(func(_t: Node): hits += 1; _check(sprite.frame == combat.settings.hit_frame, "Hit frame synchronized"))
	combat.attack_accepted.connect(func(_id: int, _count: int): start_times.append(Time.get_ticks_msec()/1000.0))
	sprite.attack_completed.connect(func(): end_times.append(Time.get_ticks_msec()/1000.0))
	var camera: Camera3D = main.get_node("CameraRig").camera
	_click(camera.unproject_position(enemy.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	await _ticks(2)
	_check(combat.target == target and combat.combo_hits == 0, "Left click starts approach to explicit body")
	var anchor: Vector3 = combat.return_anchor
	_tap("lock_on")
	_click(camera.unproject_position(second.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	_check(combat.queued and combat.stock.current == 3, "Click other enemy reserves same target without spending")
	for i in range(5): _tap("attack")
	await _ticks(2)
	_check(combat.target == target and combat.selected_target == target, "Combo target fixed; L ignored")
	for i in range(120):
		await _ticks(1)
		if combat.combo_hits == 2: break
	_check(combat.combo_hits == 2 and combat.stock.current == 1 and stance_ticks > 0, "Second strike after stance")
	_check(start_times.size() == 2 and end_times.size() >= 1, "Timing events present")
	if start_times.size() == 2 and not end_times.is_empty():
		var attack_seconds := end_times[0] - start_times[0]
		var stance_seconds := start_times[1] - end_times[0]
		print("TIMING attack=",attack_seconds," stance=",stance_seconds)
		_check(absf(attack_seconds - 0.32) < 0.07, "Attack near 0.32 seconds")
		_check(stance_seconds >= 0.10 and stance_seconds < 0.19, "Stance near 0.12 seconds")
	_tap("attack")
	_click(Vector2(1100,690),MOUSE_BUTTON_LEFT)
	await _wait_idle()
	_check(hits == 3 and target.health.current_hp == 10 and other.health.current_hp == 40, "All three hits stay on first enemy")
	_check(player.global_position.distance_to(anchor) < 0.03 and not combat.queued, "Safe return after combo")
	await _settle(origin)
	# Selected target is retained after mouse attack while valid; J needs no cursor.
	_check(combat.selected_target == target, "Mouse choice retained after recovery")
	_tap("lock_on")
	await _ticks(2)
	_check(combat.selected_target == other, "L works again in FREE")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _ticks(2)
	_check(combat.target == other, "J/action attacks filled target")
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_J
	echo.pressed = true
	echo.echo = true
	Input.parse_input_event(echo)
	Input.flush_buffered_events()
	await _wait_idle()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	_check(other.health.current_hp == 30 and hits == 4, "Held attack and key echo do not combo")
	# A lost candidate chooses the best remaining one, then 1/0 candidate cycling.
	second.hide()
	await _ticks(3)
	_check(combat.selected_target == target, "Lost selected candidate reselects")
	_tap("lock_on")
	await _ticks(2)
	_check(combat.selected_target == target, "Single candidate retained")
	enemy.hide()
	await _ticks(2)
	_tap("lock_on")
	_tap("attack")
	await _ticks(2)
	_check(combat.selected_target == null and not combat.is_busy(), "Zero candidates clear and reject attack")
	enemy.show()
	second.show()
	await _settle(origin)
	# Existing gamepad bindings use the same action paths.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_STICK
	pad.pressed = true
	var previous = combat.selected_target
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	pad.pressed = false
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	await _ticks(2)
	_check(combat.selected_target != previous, "Pad lock_on cycles")
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	await _ticks(2)
	_check(combat.is_busy() and combat.target == combat.selected_target, "Pad west starts selected attack")
	pad.pressed = false
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	await _wait_idle()
	await _settle(origin)
	target.health.heal(40.0)
	await _ticks(2) # Revival must reach the normal marker/collider update first.
	_click(camera.unproject_position(target.marker.global_position),MOUSE_BUTTON_LEFT)
	await _ticks(2)
	_check(combat.target == target, "Left click gold marker selects explicitly")
	await _wait_idle()
	await _settle(origin)
	# New obstacle during stance cancels the queued attack.
	target.health.heal(40.0)
	_check(combat.request_attack(target) and combat.request_followup(), "Obstacle test starts")
	for i in range(120):
		await _ticks(1)
		if combat._waiting: break
	_check(combat._waiting and combat.queued, "Reached queued stance before obstacle")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m07_controls_stance.png")
	var wall := _block(player.global_position.lerp(target.global_position,0.5)+Vector3.UP,Vector3(0.2,2,0.2))
	await _wait_idle()
	_check(not combat.queued and combat.stock.current == 2, "Blocked stance discards unpaid queue")
	wall.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M07 controls: selection, markers, cycle, mouse/action, target lock, stance, hold, safety")
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
