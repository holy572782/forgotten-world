extends SceneTree
## Exercise the real F5 defaults and GUI buttons, rather than an isolated fixture.
var failures: Array[String] = []
var main: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _ticks(3)

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _ticks(5)
	var selector = main.get_node("PracticeSelector")
	var player: CharacterBody3D = main.get_node("Player")
	_check(selector.mode == 1 and is_instance_valid(selector.active_enemy), "F5 automatically creates melee enemy")
	_check(not main.get_node("TrainingEnemy").visible, "stationary enemies isolated at startup")
	var ai: CharacterBody3D = selector.active_enemy
	var home: Vector3 = ai.global_position
	await _ticks(180)
	_check(ai.global_position.distance_to(home) > 1.0 and ai.attack_count >= 1, "default enemy approaches and attacks without pressing trial buttons")
	player.reset_motion(ai.global_position + ai.facing * 1.2)
	var health: HealthComponent = player.get_node("HealthComponent")
	var before := health.current_hp
	for i in range(240):
		if health.current_hp < before: break
		await _ticks(1)
	_check(is_equal_approx(before - health.current_hp,10), "default enemy really damages player in hit range")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m09_startup_melee.png")
	await _click(selector.buttons[2])
	_check(selector.mode == 2 and selector.buttons[2].button_pressed, "Japanese ranged GUI button activates ranged trial")
	_check(not player.combat.is_busy() and health.current_hp == 100, "trial GUI resets without a player attack")
	await _ticks(150)
	_check(selector.active_enemy.attack_count >= 1, "ranged trial actually fires")
	await _click(selector.buttons[0])
	_check(selector.mode == 0 and not is_instance_valid(selector.active_enemy) and main.get_node("TrainingEnemy").visible, "Japanese static GUI button restores legacy trial")
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("M09 STARTUP PASS: default enemy attacks, GUI switches and resets")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
