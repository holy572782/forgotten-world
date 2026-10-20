extends SceneTree
## Actual physics and animation callbacks; no manual invocation of hit callbacks.
var failures: Array[String] = []
var main: Node3D
var player: CharacterBody3D
var combat: Node
var sprite: AnimatedSprite3D
var enemy: Node3D
var target: Node3D
var hits := 0
var capture := false
var captured: Dictionary = {}
var states: Array[int] = []
var max_camera_step := 0.0
var previous_camera := Vector3.ZERO
var hit_frames: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame
		var camera: Camera3D = main.get_node("CameraRig").camera
		max_camera_step = maxf(max_camera_step, camera.global_position.distance_to(previous_camera))
		previous_camera = camera.global_position
		if capture and not captured.has(combat.state):
			captured[combat.state] = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/m06_%dfps_state_%d.png" % [Engine.max_fps, combat.state])

func _settle(at: Vector3) -> void:
	combat.stock.set_recovery_allowed(true)
	combat.stock.advance(10.0)
	player.reset_motion(at)
	main.get_node("CameraRig").snap_to_target()
	await _ticks(12)

func _wait_idle() -> void:
	for index in range(150):
		await _ticks(1)
		if not combat.is_busy(): return
	_check(false, "State timeout")

func _click(position: Vector2, button: int = MOUSE_BUTTON_RIGHT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _block(at: Vector3, size: Vector3) -> StaticBody3D:
	var block := StaticBody3D.new()
	block.collision_layer = 1
	block.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	block.add_child(shape)
	main.add_child(block)
	block.global_position = at
	return block

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1152, 720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	combat.settings = combat.settings.duplicate()
	combat.equipped_weapon = combat.equipped_weapon.duplicate()
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	combat.hit.connect(func(_target: Node): hits += 1)
	combat.hit.connect(func(_target: Node): hit_frames.append(sprite.frame))
	combat.state_changed.connect(func(next: int): states.append(next))
	await _ticks(20)
	print("Initial player=", player.global_position, " enemy=", target.global_position, " grounded=", player.is_on_floor(), " sight=", combat.Path.sight(player, target.global_position), " path=", combat.Path.clear(player, combat.attack_position(target), combat.settings, player.global_position))
	_check(combat.can_select(target) and target.marker.visible, "In-range marker")
	var origin := player.global_position
	var camera: Camera3D = main.get_node("CameraRig").camera
	_check(combat.pick_target(camera.unproject_position(target.marker.global_position)) == target, "Ray selects visible marker")
	_click(Vector2(20, 20))
	await _ticks(2)
	_check(not combat.is_busy(), "HUD right click ignored")
	_click(camera.unproject_position(target.global_position + Vector3(1.5, 0, 0)))
	await _ticks(2)
	_check(not combat.is_busy(), "Empty ground does not start attack")
	max_camera_step = 0.0
	previous_camera = camera.global_position
	var start_time := Time.get_ticks_msec()
	_click(camera.unproject_position(target.marker.global_position))
	await _ticks(3)
	print("Click screen=", camera.unproject_position(target.marker.global_position), " viewport=", root.size, " state=", combat.state, " sprite=", sprite.state, " pending=", combat._pending_click)
	_check(combat.state == combat.State.Approach and sprite.state == &"Approach", "Right click starts approach")
	_check(sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).atlas.resource_path.ends_with("player_jump.png"), "Approach jump image")
	_check(player.global_position.distance_to(origin) > 0.01 and player.global_position.distance_to(origin) < 3.0, "Visible intermediate position")
	for index in range(120):
		_check(not combat.request_attack(target), "Busy rejects repeated attack")
		if combat.state == combat.State.Attack:
			_check(String(sprite.animation).begins_with("walk_") if combat._waiting else String(sprite.animation).begins_with("attack_"), "Attack / inter-hit stance image")
			_check(player.facing_world.dot((target.global_position - player.global_position).normalized()) > 0.99, "Faces target")
		Input.action_press("move_left")
		Input.action_press("jump")
		await _ticks(1)
		if not combat.is_busy(): break
	Input.action_release("move_left")
	Input.action_release("jump")
	_check(not combat.is_busy(), "Returns to Idle")
	_check(hits == 1 and target.health.current_hp == 30.0, "Exactly one damage event")
	_check(hit_frames == [combat.settings.hit_frame], "Damage matches visible hit frame")
	_check(player.global_position.distance_to(origin) < 0.03, "Returns to saved 3D anchor")
	_check(states == [1, 2, 3, 0], "Ordered state transitions")
	_check(max_camera_step < 0.6, "No abrupt camera movement")
	_check(is_equal_approx(camera.fov, 75.0), "Camera FOV retained")
	print("Cycle ms=", Time.get_ticks_msec() - start_time, " max_camera_step=", max_camera_step, " return_error=", combat.return_error)
	await _ticks(5)
	Input.action_press("jump")
	await _ticks(4)
	_check(player.global_position.y > origin.y + 0.1, "Jump resumes after return")
	_check(not combat.request_attack(target), "Airborne start rejected")
	Input.action_release("jump")
	await _ticks(65)
	Input.action_press("move_right")
	await _ticks(8)
	Input.action_release("move_right")
	_check(Vector2(player.velocity.x, player.velocity.z).length() > 0.1, "Movement resumes")
	await _settle(origin - Vector3(6, 0, 0))
	_check(not target.marker.visible and not combat.request_attack(target), "Out of range rejected")
	await _settle(origin)
	combat.equipped_weapon.attack_range = 2.0
	await _ticks(2)
	_check(not target.marker.visible, "Resource radius applied")
	combat.equipped_weapon.attack_range = 5.0
	await _ticks(2)
	# Wall and step in the actual route must both reject selection.
	var midpoint := origin.lerp(target.global_position, 0.5)
	for height in [3.0, 0.25]:
		var block := _block(midpoint + Vector3.UP * height * 0.5, Vector3(0.4, height, 2.0))
		await _ticks(3)
		_check(not target.marker.visible and not combat.request_attack(target), "Wall/step rejected " + str(height))
		block.queue_free()
		await _ticks(3)
	# Moving destination/removed target cancels approach, then returns safely.
	_check(combat.request_attack(target), "Start before moved target")
	await _ticks(4)
	enemy.position.z -= 1.0
	await _wait_idle()
	_check(hits == 1 and player.global_position.distance_to(origin) < 0.03, "Moved target cancels without damage")
	enemy.position.z += 1.0
	await _ticks(3)
	_check(combat.request_attack(target), "Start blocked return")
	for index in range(60):
		await _ticks(1)
		if combat.state == combat.State.Attack: break
	var return_block := _block(origin + Vector3.UP, Vector3(1.0, 2.0, 1.0))
	await _wait_idle()
	_check(combat.return_error > 0.5 and combat.return_error < 1.4, "Blocked anchor stops nearby safely")
	_check(combat.last_result.contains("blocked"), "Blocked return diagnostic")
	return_block.queue_free()
	await _settle(origin)
	# A new obstacle during Approach must abort before entering it.
	var before_hits := hits
	_check(combat.request_attack(target), "Start dynamic approach block")
	await _ticks(2)
	var approach_block := _block(midpoint + Vector3.UP, Vector3(0.4, 2.0, 2.0))
	await _wait_idle()
	_check(hits == before_hits and player.global_position.distance_to(origin) < 0.03, "Dynamic approach obstacle aborts safely")
	approach_block.queue_free()
	await _ticks(3)
	# Lethal hit still completes the visible attack and return; dead mark stays off.
	target.health.damage(target.health.current_hp - 10.0)
	_check(combat.request_attack(target), "Start lethal attack")
	await _wait_idle()
	_check(target.health.current_hp == 0.0 and hits == before_hits + 1, "Lethal single hit")
	_check(not target.marker.visible and not combat.request_attack(target), "Dead target rejected")
	target.health.heal(40.0)
	await _ticks(3)
	# Health remains active during combat; death cancels without a stranded state.
	_check(combat.request_attack(target), "Start player damage check")
	await _ticks(2)
	player.get_node("HealthComponent").damage(10.0)
	_check(player.get_node("HealthComponent").current_hp == 90.0 and combat.is_busy(), "No combat invulnerability")
	player.get_node("HealthComponent").damage(90.0)
	_check(not combat.is_busy(), "Player death cancels state")
	player.get_node("HealthComponent").heal(100.0)
	await _settle(origin)
	_check(combat.request_attack(target), "Start before target removed")
	await _ticks(4)
	enemy.queue_free()
	await _wait_idle()
	_check(player.global_position.distance_to(origin) < 0.03, "Removed target returns safely")
	for phase in [combat.State.Attack, combat.State.Return]:
		enemy = load("res://scenes/enemies/training_enemy.tscn").instantiate()
		main.add_child(enemy)
		enemy.global_position = Vector3(-3, 0, -2)
		target = enemy.get_node("Targetable")
		await _ticks(3)
		_check(combat.request_attack(target), "Start phase deletion " + str(phase))
		for index in range(90):
			await _ticks(1)
			if combat.state == phase: break
		_check(combat.state == phase, "Reach deletion phase " + str(phase))
		enemy.queue_free()
		await _wait_idle()
		_check(player.global_position.distance_to(origin) < 0.03, "Deleted in Attack/Return recovers")
	# Edge support: level endpoints do not allow a route over missing terrain.
	_check(not combat.Path.clear(player, Vector3(16, 0, 0), combat.settings, Vector3(12, 0, 0)), "Arena edge rejected")
	if failures.is_empty(): print("PASS M06: selection, images, single hit, return, collisions, cancellation, input and camera")
	else:
		for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
