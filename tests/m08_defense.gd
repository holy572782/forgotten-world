extends "res://tests/m06_target_dash.gd"
## Uses real physics/animation/input callbacks and the production HP entry point.
var health: HealthComponent
var rig: Node3D
var origin := Vector3.ZERO
var source: Node3D
var step_starts := 0
var accepted_ids: Array[int] = []
var mode := ""

func _press(action: String, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _direction(input: Vector2) -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	if input.x < 0: Input.action_press("move_left", -input.x)
	if input.x > 0: Input.action_press("move_right", input.x)
	if input.y < 0: Input.action_press("move_up", -input.y)
	if input.y > 0: Input.action_press("move_down", input.y)

func _phase(next: int, count: int = 140) -> void:
	for i in range(count):
		if combat.state == next: return
		await _ticks(1)
	_check(false, mode + " phase timeout " + str(next))

func _fresh(at: Vector3) -> void:
	for action in ["guard", "dodge", "attack", "jump", "camera_right"]: _press(action, false)
	_direction(Vector2.ZERO)
	health.heal(1000)
	target.health.heal(1000)
	combat.defense.step_invulnerability_enabled = false
	rig.rotation.y = 0.0
	await _settle(at)
	combat._step_cooldown = 0.0

func _damage(expected: float, label: String) -> void:
	var before := health.current_hp
	health.damage(10, source)
	_check(is_equal_approx(before - health.current_hp, expected), label)
	health.heal(1000)

func _capture_pose(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m08_" + label + ".png")

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152, 720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	combat.defense = combat.defense.duplicate()
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	health = player.get_node("HealthComponent")
	rig = main.get_node("CameraRig")
	source = Node3D.new()
	main.add_child(source)
	combat.hit.connect(func(_t: Node): hits += 1)
	combat.attack_accepted.connect(func(id: int, _combo: int): accepted_ids.append(id))
	combat.state_changed.connect(func(next: int):
		if next == combat.State.Step:
			step_starts += 1
			if mode == "compare": _damage(10, "Step beginning vulnerable"))
	await _ticks(20)
	origin = player.global_position
	# Movement stops on guard. Facing is toward selected enemy, not the input.
	Input.action_press("move_right")
	_press("guard")
	await _ticks(2)
	var guard_at := player.global_position
	await _ticks(8)
	_check(combat.state == combat.State.Guard and player.global_position.distance_to(guard_at) < 0.00001, "Guard owns movement")
	_check(sprite.state == &"Guard" and sprite.frame == 1 and not sprite.is_playing(), "Walk static guard frame")
	_check(main.get_node("HUD").debug_label.text.contains("GUARD"), "HUD GUARD")
	for degrees in [0, 59, 60, 61, 180]:
		source.global_position = player.global_position + player.facing_world.rotated(Vector3.UP, deg_to_rad(degrees)) * 2
		_damage(5 if degrees <= 60 else 10, "Guard angle " + str(degrees))
	var before := health.current_hp
	health.damage(10)
	_check(before - health.current_hp == 10, "Unknown source full damage")
	health.heal(1000)
	var missing_source := Node3D.new()
	missing_source.free()
	before = health.current_hp
	health.damage(10, missing_source)
	_check(before - health.current_hp == 10, "Freed source sanitized before typed filter")
	health.heal(1000)
	var plain_source := Node.new()
	main.add_child(plain_source)
	before = health.current_hp
	health.damage(10,plain_source)
	_check(before - health.current_hp == 10, "Nonspatial source full damage")
	plain_source.free()
	health.heal(1000)
	source.global_position = player.global_position
	_damage(10, "Coincident source full damage")
	await _capture_pose("guard")
	_press("guard", false)
	_direction(Vector2.ZERO)
	await _ticks(2)
	_check(not combat.is_busy() and not rig.follow_locked, "Standalone guard FREE")
	_damage(10, "Unguarded full damage")
	await _fresh(Vector3(-10,0,-10))
	var slope := _block(Vector3(-10,0.5,-10),Vector3(6,0.4,4))
	slope.rotation.z = 0.2
	player.reset_motion(Vector3(-10,2,-10))
	await _ticks(60)
	_check(player.is_on_floor(), "Test slope grounded")
	_press("guard")
	await _ticks(2)
	_check(combat.state == combat.State.Guard, "Normal grounded slope permits stationary guard")
	_press("guard",false)
	await _ticks(2)
	slope.free()
	# No live target retains facing, including orbit changes.
	await _fresh(Vector3(-10,0,-10))
	player.facing_world = Vector3.LEFT
	_press("guard")
	await _ticks(2)
	Input.action_press("camera_right")
	await _ticks(5)
	_check(player.facing_world == Vector3.LEFT, "No target keeps last world facing")
	_press("guard", false)
	# K without direction never launches. Direction can be added while K is held.
	await _fresh(Vector3(-10,0,-10))
	var start_count := step_starts
	_press("dodge")
	await _ticks(3)
	_check(step_starts == start_count and not combat.is_busy(), "No direction no step")
	_direction(Vector2.RIGHT)
	await _ticks(1)
	_check(combat.state == combat.State.Step, "Held K then direction launches once")
	await _ticks(35)
	_check(step_starts == start_count + 1, "Held K cannot repeat after cooldown")
	_press("dodge",false)
	_press("dodge")
	await _ticks(1)
	_check(step_starts == start_count + 2, "Release and repress allows another step")
	_direction(Vector2.ZERO)
	await _wait_idle()
	# Eight directions at four camera yaws. Release movement as soon as step starts
	# so normal locomotion cannot contaminate the measured step distance.
	for yaw in [0,90,180,270]:
		for vector in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			await _fresh(Vector3(-10,0,-10))
			rig.rotation.y = deg_to_rad(yaw)
			await _ticks(2)
			var start := player.global_position
			var expected: Vector3 = player.input_to_world(vector.normalized(), player._movement_basis()).normalized()
			_direction(vector)
			_press("dodge")
			var started := Time.get_ticks_msec()
			await _ticks(1)
			_direction(Vector2.ZERO)
			_check(combat.state == combat.State.Step, "Step starts " + str(yaw) + str(vector))
			if combat.state != combat.State.Step: print("STEP REFUSED yaw=",yaw," input=",vector," pos=",player.global_position," result=",combat.last_result," direction=",expected)
			await _phase(combat.State.Idle)
			var travel := player.global_position - start
			var duration := (Time.get_ticks_msec() - started) / 1000.0
			_check(absf(travel.length() - 1.2) < 0.015 and travel.normalized().dot(expected) > 0.999, "8-way camera-relative step " + str(yaw) + str(vector))
			_check(absf(duration - 0.18) < 0.10, "Step duration frame independent")
			if yaw == 0 and vector == Vector2.RIGHT: print("STEP cap=",Engine.max_fps," distance=",travel.length()," seconds=",duration)
	# Guard wins over step, attack and jump in either input order.
	for reverse in [false,true]:
		await _fresh(origin)
		start_count = step_starts
		_direction(Vector2.LEFT)
		if reverse: _press("guard")
		_press("attack")
		_press("dodge")
		_press("jump")
		if not reverse: _press("guard")
		await _ticks(2)
		_check(combat.state == combat.State.Guard and step_starts == start_count and combat.stock.current == 3 and player.global_position.y < 0.01, "Same tick priority guard > step > attack > jump")
	await _fresh(origin)
	_direction(Vector2.DOWN)
	_press("attack")
	_press("dodge")
	await _ticks(1)
	_direction(Vector2.ZERO)
	_check(combat.state == combat.State.Step and combat.stock.current == 3, "Step wins simultaneous attack without spending")
	await _wait_idle()
	# Approach, before-hit strike, after-hit strike and stance interruptions.
	for stage in ["approach","before_hit","after_hit","stance"]:
		for defense_action in ["guard","dodge"]:
			mode = stage + " " + defense_action
			await _fresh(origin)
			var hits_before := hits
			_check(combat.request_attack(target), mode + " attack start")
			if stage != "approach": await _phase(combat.State.Attack)
			if stage == "after_hit" or stage == "stance":
				for i in range(80):
					if hits > hits_before and (stage != "stance" or combat._waiting): break
					await _ticks(1)
			_check(combat.request_followup(), mode + " reserve unpaid next")
			var paid: int = combat.stock.current
			var id: int = combat.attack_id
			var delivered := hits
			if defense_action == "dodge": _direction(Vector2.DOWN)
			_press(defense_action)
			await _ticks(1)
			_direction(Vector2.ZERO)
			_check(combat.state == (combat.State.Guard if defense_action == "guard" else combat.State.Step), mode + " interrupts")
			_check(not combat.queued and combat.stock.current == paid and combat.attack_id == id, mode + " queue cleared paid stock unchanged ID retained")
			_check(rig.follow_locked and combat.return_anchor.distance_to(origin) < 0.001, mode + " anchor and camera retained")
			await _capture_pose(defense_action + "_interrupt")
			if defense_action == "guard": _press("guard",false)
			await _phase(combat.State.Recover)
			_check(hits == delivered, mode + " old hit never resumes")
			_press("dodge",false)
			_press("attack")
			_press("attack",false)
			await _wait_idle()
			_check(hits == delivered + 1 and combat.stock.current == paid - 1, mode + " explicit followup hits/spends exactly once")
			_check(player.global_position.distance_to(origin) < 0.03 and not rig.follow_locked, mode + " original return and release")
	# No automatic strike on defense exit; window expires and returns.
	await _fresh(origin)
	combat.request_attack(target)
	await _phase(combat.State.Attack)
	_press("guard")
	await _ticks(2)
	_press("guard",false)
	var accepted_before := accepted_ids.size()
	await _wait_idle()
	_check(accepted_ids.size() == accepted_before and player.global_position.distance_to(origin) < 0.03, "No followup auto return")
	# Returning guard and step resume the original return with no followup window.
	for action in ["guard","dodge"]:
		await _fresh(origin)
		combat.request_attack(target)
		await _phase(combat.State.Return)
		await _ticks(3)
		var focus := rig.global_position
		if action == "dodge": _direction(Vector2.DOWN)
		_press(action)
		await _ticks(1)
		_direction(Vector2.ZERO)
		_check(combat.state == (combat.State.Guard if action == "guard" else combat.State.Step), "Return interrupt " + action)
		_check(rig.follow_locked and rig.global_position == focus, "Return interrupted camera held")
		if action == "guard":
			var at := player.global_position
			await _ticks(5)
			_check(player.global_position == at, "Return guard stops immediately")
			_press(action,false)
		await _wait_idle()
		_check(player.global_position.distance_to(origin) < 0.03 and not rig.follow_locked, "Resume original return " + action)
	# A return blocked after its guard interruption stops safely, releasing camera.
	await _fresh(origin)
	combat.request_attack(target)
	await _phase(combat.State.Return)
	_press("guard")
	await _ticks(1)
	var obstruction := _block(origin.lerp(player.global_position,0.5)+Vector3.UP,Vector3(0.2,2,0.2))
	await _ticks(2)
	_press("guard",false)
	await _wait_idle()
	_check(combat.last_result.contains("blocked") and not rig.follow_locked and combat.return_error > 0.03, "Interrupted return still respects new obstacle")
	obstruction.free()
	# Actual locomotion contact, full capsule remains unchanged. Safe side allowed.
	await _fresh(Vector3(-10,0,-10))
	var wall := _block(Vector3(-10,1,-9), Vector3(8,2,0.5))
	_direction(Vector2.DOWN)
	await _ticks(40)
	_direction(Vector2.ZERO)
	await _ticks(2)
	var contact := player.global_position
	var radius: float = player.get_node("CollisionShape3D").shape.radius
	_direction(Vector2.RIGHT)
	_press("dodge")
	await _ticks(1)
	_direction(Vector2.ZERO)
	_check(combat.state == combat.State.Step, "Wall contact safe tangential step")
	await _wait_idle()
	_check(absf(player.global_position.x-contact.x-1.2) < 0.02 and player.get_node("CollisionShape3D").shape.radius == radius, "Full capsule safe wall step")
	_press("dodge",false)
	await _ticks(20)
	_direction(Vector2.DOWN)
	_press("dodge")
	await _ticks(1)
	_direction(Vector2.ZERO)
	_check(combat.state != combat.State.Step and combat.last_result.contains("Step rejected"), "Into wall rejected")
	wall.free()
	# A new obstacle during travel must stop the step at the last safe point.
	await _fresh(Vector3(-10,0,-10))
	_direction(Vector2.RIGHT)
	_press("dodge")
	await _ticks(2)
	_direction(Vector2.ZERO)
	wall = _block(Vector3(-9.1,1,-10),Vector3(0.2,2,2))
	await _wait_idle()
	_check(player.global_position.x < -9.49 and combat.last_result.contains("unsafe"), "Dynamic step obstacle stops safely")
	wall.free()
	# Higher floor is not automatically climbed by Step.
	await _fresh(Vector3(-10,0,-10))
	wall = _block(Vector3(-8.8,0.125,-10),Vector3(0.7,0.25,1))
	await _ticks(2)
	_direction(Vector2.RIGHT)
	_press("dodge")
	await _ticks(1)
	_direction(Vector2.ZERO)
	_check(combat.state != combat.State.Step, "Raised step refused")
	wall.free()
	# Test-only isolated small platform supplies a deterministic cliff.
	var platform := _block(Vector3(40,-0.5,0), Vector3(4,1,4))
	await _fresh(Vector3(41.1,0,0))
	_direction(Vector2.RIGHT)
	_press("dodge")
	await _ticks(1)
	_direction(Vector2.ZERO)
	_check(combat.state != combat.State.Step and player.global_position.x < 41.2, "Cliff refused without falling")
	platform.free()
	# Compare A/B at beginning, middle, tail. Health.damage remains the entry point.
	for invulnerable in [false,true]:
		await _fresh(Vector3(-10,0,-10))
		mode = "compare"
		combat.defense.step_invulnerability_enabled = invulnerable
		_direction(Vector2.RIGHT)
		_press("dodge")
		await _ticks(1)
		_direction(Vector2.ZERO)
		for i in range(10):
			if combat._elapsed >= 0.06: break
			await _ticks(1)
		_check(combat.state == combat.State.Step, "Comparison mid-step")
		_damage(0 if invulnerable else 10, "Step middle A/B")
		await _capture_pose("step_" + ("b" if invulnerable else "a"))
		for i in range(20):
			if combat._elapsed >= 0.14: break
			await _ticks(1)
		_damage(10, "Step tail vulnerable")
		await _wait_idle()
		print("DAMAGE variant=", "B" if invulnerable else "A", " begin=10 mid=",0 if invulnerable else 10," tail=10")
	mode = ""
	# Approach, attack and return remain vulnerable even with comparison B enabled.
	await _fresh(origin)
	combat.defense.step_invulnerability_enabled = true
	combat.request_attack(target)
	for state in [combat.State.Approach,combat.State.Attack,combat.State.Return]:
		await _phase(state)
		_damage(10, "Combat vulnerable state " + str(state))
	await _wait_idle()
	# Guard/Step do not restore stocks or bypass weapon combo limits.
	for limit in [1,2]:
		await _fresh(origin)
		combat.equipped_weapon = load("res://tests/fixtures/weapon_%d.tres" % limit)
		combat.request_attack(target)
		await _phase(combat.State.Attack)
		_press("guard")
		await _ticks(1)
		_press("guard",false)
		await _ticks(1)
		_check(combat.state == (combat.State.Return if limit == 1 else combat.State.Recover), "Defense keeps weapon combo limit " + str(limit))
		await _wait_idle()
	combat.equipped_weapon = load("res://resources/weapons/one_handed_sword.tres")
	await _fresh(origin)
	combat.request_attack(target)
	await _phase(combat.State.Attack)
	_press("guard")
	await _ticks(1)
	combat.stock._current = 0
	_press("guard",false)
	await _ticks(1)
	_check(combat.state == combat.State.Return, "Zero stock still guards then returns")
	await _wait_idle()
	# Real mapped pad events, using the existing left stick and east button.
	await _fresh(Vector3(-10,0,-10))
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_SHOULDER
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _ticks(1)
	_check(combat.state == combat.State.Guard, "Synthetic LB guard")
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _ticks(2)
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.8
	Input.parse_input_event(axis)
	button = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _ticks(1)
	_check(combat.state == combat.State.Step, "Synthetic east plus left stick")
	axis = axis.duplicate()
	axis.axis_value = 0.0
	Input.parse_input_event(axis)
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	await _wait_idle()
	# Death/reset in defense cancels everything, suppresses held input until release.
	for action in ["guard","dodge"]:
		await _fresh(origin)
		combat.request_attack(target)
		await _phase(combat.State.Attack)
		if action == "dodge": _direction(Vector2.DOWN)
		_press(action)
		await _ticks(1)
		_direction(Vector2.ZERO)
		player.reset_motion(origin)
		await _ticks(2)
		_check(not combat.is_busy() and not rig.follow_locked and not combat.queued and sprite.combat_pose == &"", "Live reset clears " + action)
	for action in ["guard","dodge"]:
		await _fresh(origin)
		combat.request_attack(target)
		await _phase(combat.State.Attack)
		if action == "dodge": _direction(Vector2.DOWN)
		_press(action)
		await _ticks(1)
		_direction(Vector2.ZERO)
		health.damage(1000)
		await _ticks(3)
		_check(not combat.is_busy() and not rig.follow_locked and not combat.queued and player.velocity == Vector3.ZERO and sprite.combat_pose == &"", "Death clears " + action)
		_check(not combat.stock._recovery_allowed and combat.stock.recovery_progress == 0.0, "HP0 stops recovery and clears fractional time")
		health.heal(1000)
		await _ticks(1)
		_check(not combat.is_busy(), "Held defense cannot restart after death")
		player.reset_motion(origin)
		await _ticks(2)
		_check(not combat.is_busy(), "Forced reset clears defense")
	for i in range(1,accepted_ids.size()): _check(accepted_ids[i] > accepted_ids[i-1], "Monotonic unique strike IDs")
	await _fresh(origin)
	for size in [Vector2i(640,360),Vector2i(1152,720)]:
		root.size = size
		await _ticks(3)
		_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(main.get_node("HUD").panel.get_global_rect()), "M08 HUD fits " + str(size))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M08: inputs, 8 directions x 4 yaws, guard damage, interrupts, stock/hits, followup, return, terrain, camera, A/B, death, HUD")
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
