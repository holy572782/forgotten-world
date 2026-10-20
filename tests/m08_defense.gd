extends "res://tests/m06_target_dash.gd"
## ADR-014: real input/physics/animation callbacks; old Step results stay in docs/Git.
var health: HealthComponent
var rig: Node3D
var origin := Vector3.ZERO
var expected_anchor := Vector3.ZERO
var source: Node3D
var return_starts := 0
var accepted_ids: Array[int] = []
var hit_counts: Dictionary = {}

func _press(action: String, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _stick(x: float, y: float = 0.0) -> void:
	for pair in [[JOY_AXIS_LEFT_X,x],[JOY_AXIS_LEFT_Y,y]]:
		var event := InputEventJoypadMotion.new()
		event.axis = pair[0]
		event.axis_value = pair[1]
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _neutral() -> void:
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT]: _key(code,false)
	for action in ["move_left","move_right","move_up","move_down"]: _press(action,false)
	_stick(0.0)

func _ticks(count: int) -> void:
	for i in range(count):
		await super._ticks(1)
		if combat.state == combat.State.Guard:
			_check(String(sprite.animation).begins_with("guard_") and sprite.frame == 1, "Actual combat Guard displays equipped shield")
		else:
			_check(not String(sprite.animation).begins_with("guard_"), "Shield cleared outside actual combat Guard")
		if combat._combat_cycle and combat.is_busy():
			_check(rig.follow_locked, "Camera held through combat/guard/return")
			_check(rig.global_position.distance_to(rig.follow_anchor) < 0.00001, "Follow origin fixed each tick")
			_check(combat.return_anchor.distance_to(expected_anchor) < 0.00001, "Initial attack anchor retained each tick")

func _phase(next: int) -> void:
	for i in range(150):
		if combat.state == next: return
		await _ticks(1)
	_check(false,"Phase timeout " + str(next))

func _fresh(at: Vector3) -> void:
	_neutral()
	for code in [KEY_I,KEY_J,KEY_K,KEY_SPACE]: _key(code,false)
	for action in ["guard","attack","dodge","jump","camera_right"]: _press(action,false)
	health.heal(1000)
	target.health.heal(1000)
	rig.rotation.y = 0.0
	await _settle(at)

func _start(stage: String = "approach") -> void:
	await _fresh(origin)
	_check(combat.request_attack(target), "Start " + stage)
	if stage == "approach": return
	await _phase(combat.State.Attack)
	if stage == "after_hit" or stage == "stance":
		for i in range(80):
			if combat._hit_done and (stage != "stance" or combat._waiting): break
			await _ticks(1)
	if stage == "recover":
		_key(KEY_I)
		await _ticks(2)
		_key(KEY_I,false)
		await _phase(combat.State.Recover)

func _damage(expected: float, label: String) -> void:
	var before := health.current_hp
	health.damage(10,source)
	_check(is_equal_approx(before-health.current_hp,expected),label)
	health.heal(1000)

func _capture_pose(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m08_return_"+label+".png")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	health = player.get_node("HealthComponent")
	rig = main.get_node("CameraRig")
	source = Node3D.new()
	main.add_child(source)
	combat.hit.connect(func(_t: Node):
		hits += 1
		var id: int = combat.attack_id
		hit_counts[id] = hit_counts.get(id,0)+1
		_check(hit_counts[id] == 1,"At most one hit per attack ID"))
	combat.attack_accepted.connect(func(id: int,_combo: int): accepted_ids.append(id))
	combat.state_changed.connect(func(next: int):
		if next == combat.State.Return: return_starts += 1
		if next == combat.State.Approach and combat.combo_hits == 0: expected_anchor = combat.return_anchor)
	await _ticks(20)
	origin = player.global_position
	_check(not combat.State.has("Step"), "Step state removed")
	for property in combat.defense.get_property_list():
		_check(not String(property.name).begins_with("step_"), "Step-only resource fields removed")
	# FREE never uses stale anchors; movement, facing and ordinary jump remain live.
	await _fresh(Vector3(-10,0,-10))
	combat.return_anchor = Vector3(100,0,100)
	var before_position := player.global_position
	_key(KEY_D)
	await _ticks(10)
	_check(not combat.is_busy() and player.global_position.x > before_position.x+0.1,"FREE is ordinary movement")
	_neutral()
	await _ticks(5)
	_key(KEY_SPACE)
	await _ticks(5)
	_check(player.global_position.y > 0.1,"FREE jump")
	_key(KEY_SPACE,false)
	# Stages include unpaid approach, paid strike before/after hit, stance, recovery.
	for pair in [["approach",KEY_W],["attack",KEY_A],["after_hit",KEY_LEFT],["stance",KEY_S],["recover",KEY_D]]:
		var stage: String = pair[0]
		await _start(stage)
		_check(combat.request_followup(),stage+" reserve one unpaid followup")
		var paid: int = combat.stock.current
		var id: int = combat.attack_id
		var delivered := hits
		var returns_before := return_starts
		_key(pair[1])
		await _ticks(1)
		_check(combat.state == combat.State.Return,stage+" input enters Return in receiving physics tick")
		_check(not combat.queued and combat.stock.current == paid and combat.attack_id == id,stage+" clears queue without refund/spend/new ID")
		_check(not combat._hit_pending and not sprite._attacking,stage+" stops strike and pending hit")
		await _capture_pose(stage)
		await _wait_idle()
		var at := player.global_position
		await _ticks(6)
		_check(player.global_position.distance_to(at) < 0.00001,stage+" held key cannot walk after return")
		_check(return_starts == returns_before+1 and hits == delivered,stage+" one return, no canceled hit")
		_check(at.distance_to(expected_anchor) < 0.03 and not rig.follow_locked,stage+" safe original return and release")
		_neutral()
		await _ticks(1)
		_key(KEY_D)
		await _ticks(8)
		_key(KEY_D,false)
		_check(player.global_position.distance_to(at) > 0.05,stage+" fresh input restores walk")
		await _ticks(10)
		_key(KEY_SPACE)
		await _ticks(5)
		_key(KEY_SPACE,false)
		_check(player.global_position.y > 0.1,stage+" jump after return")
	# All 8 arrow directions return to the same saved point, never toward the input.
	for keys in [[KEY_UP],[KEY_DOWN],[KEY_LEFT],[KEY_RIGHT],[KEY_UP,KEY_LEFT],[KEY_UP,KEY_RIGHT],[KEY_DOWN,KEY_LEFT],[KEY_DOWN,KEY_RIGHT]]:
		await _start("attack")
		for code in keys: _key(code)
		await _ticks(1)
		_check(combat.state == combat.State.Return,"Eight-direction return " + str(keys))
		_neutral()
		await _wait_idle()
		_check(player.global_position.distance_to(expected_anchor) < 0.03,"Same destination for every direction")
	# A complete key tap between ticks survives until the next physical update.
	await _start("attack")
	var serial: int = player.movement_press_serial
	_key(KEY_W)
	_key(KEY_W,false)
	_check(player.movement_press_serial == serial+1,"Short event tap recorded by controller")
	await _ticks(1)
	_check(combat.state == combat.State.Return,"Short tap not lost between ticks")
	await _wait_idle()
	# Start a real clicked attack while W is already held. Echo/additional keys
	# cannot arm it; every movement action must first return to neutral.
	await _fresh(origin)
	_key(KEY_W)
	await _ticks(1)
	var camera: Camera3D = rig.camera
	_click(camera.unproject_position(target.global_position+Vector3.UP*0.75),MOUSE_BUTTON_LEFT)
	await _phase(combat.State.Attack)
	_check(return_starts >= 1 and combat._combat_cycle,"Held movement permits clicked attack")
	for i in range(3): _key(KEY_W,true,true)
	_key(KEY_A)
	await _ticks(2)
	_key(KEY_W,false)
	await _ticks(2)
	_check(combat.state == combat.State.Attack,"Partial release and repeat do not cancel")
	_key(KEY_A,false)
	_key(KEY_D)
	_key(KEY_D,false)
	await _ticks(1)
	_check(combat.state == combat.State.Return,"Full release then short repress cancels")
	await _wait_idle()
	# Opposing keys are still held actions, not a neutral vector.
	await _fresh(origin)
	_key(KEY_W)
	_key(KEY_S)
	_check(combat.request_attack(target),"Opposing-held attack begins")
	await _phase(combat.State.Attack)
	_key(KEY_W,false)
	await _ticks(1)
	_check(combat.state == combat.State.Attack,"Opposing keys never fake full release")
	_neutral()
	_key(KEY_A)
	await _ticks(1)
	_check(combat.state == combat.State.Return,"Opposing keys rearm after real neutral")
	_neutral()
	await _wait_idle()
	# Pad stick hysteresis: 0.35 press / 0.20 release are provisional values.
	await _fresh(origin)
	_stick(0.6)
	_check(combat.request_attack(target),"Already-held stick permits attack")
	await _phase(combat.State.Attack)
	_stick(0.3)
	await _ticks(1)
	_check(combat.state == combat.State.Attack,"Non-neutral held stick does not rearm")
	_stick(0.1)
	for value in [0.12,0.25,0.3,0.21]:
		_stick(value)
		await _ticks(1)
		_check(combat.state == combat.State.Attack,"Analog noise below press threshold ignored")
	_stick(0.7)
	_stick(0.0)
	await _ticks(1)
	_check(combat.state == combat.State.Return,"New short stick input after neutral returns")
	await _wait_idle()
	# Repeated/held direction cannot restart or extend the existing return.
	await _start("attack")
	_key(KEY_A)
	await _ticks(1)
	var travel_start: Vector3 = combat._travel_start
	var duration: float = combat._duration
	var last_elapsed: float = combat._elapsed
	var count := return_starts
	var began := Time.get_ticks_msec()
	for i in range(100):
		if not combat.is_busy(): break
		_key(KEY_D)
		_key(KEY_D,false)
		_key(KEY_A,true,true)
		await _ticks(1)
		if combat.state == combat.State.Return:
			_check(combat._travel_start == travel_start and combat._duration == duration and combat._elapsed >= last_elapsed,"Return interpolation never restarted")
			last_elapsed = combat._elapsed
	var seconds := (Time.get_ticks_msec()-began)/1000.0
	_check(not combat.is_busy() and return_starts == count,"Repeated input has exactly one Return")
	_check(seconds <= duration+0.12,"No arrival delay from repeated input")
	before_position = player.global_position
	await _ticks(6)
	_check(player.global_position.distance_to(before_position) < 0.00001,"Held A blocked after Return")
	print("RETURN cap=",Engine.max_fps," seconds=",seconds," planned=",duration," error=",combat.return_error)
	# Guard still takes precedence over direction and attack in both event orders.
	for guard_first in [false,true]:
		await _start("attack")
		count = return_starts
		if guard_first: _key(KEY_I)
		_key(KEY_A)
		_press("attack")
		_press("attack",false)
		if not guard_first: _key(KEY_I)
		await _ticks(2)
		_check(combat.state == combat.State.Guard and return_starts == count and not combat.queued,"Guard wins simultaneous input")
		var guard_at := player.global_position
		for degrees in [0,59,60,61,180]:
			source.global_position = player.global_position+player.facing_world.rotated(Vector3.UP,deg_to_rad(degrees))*2
			_damage(5 if degrees <= 60 else 10,"Guard angular damage " + str(degrees))
		var hp := health.current_hp
		health.damage(10)
		_check(hp-health.current_hp == 10,"Unknown source not guarded")
		health.heal(1000)
		await _capture_pose("guard")
		_key(KEY_I,false)
		await _phase(combat.State.Recover)
		await _ticks(2)
		_check(combat.state == combat.State.Recover and player.global_position == guard_at,"Guard input never defers a return")
		_neutral()
		_key(KEY_D)
		await _ticks(1)
		_check(combat.state == combat.State.Return,"Fresh direction after guard release returns")
		_neutral()
		await _wait_idle()
	# Standalone guard never returns, even with an obsolete anchor and held input.
	await _fresh(Vector3(-10,0,-10))
	combat.return_anchor = Vector3(100,0,100)
	_key(KEY_I)
	_key(KEY_D)
	await _ticks(4)
	_check(combat.state == combat.State.Guard,"FREE guard")
	_key(KEY_I,false)
	await _ticks(6)
	_check(not combat.is_busy() and player.global_position.x > -10 and player.global_position.distance_to(Vector3(-10,0,-10)) < 1,"FREE guard resumes ordinary movement")
	# Guard followup still uses existing stock and weapon limits; no automatic hit.
	await _start("recover")
	var paid: int = combat.stock.current
	var delivered := hits
	_key(KEY_J)
	_key(KEY_J,false)
	await _wait_idle()
	_check(hits == delivered+1 and combat.stock.current == paid-1,"Explicit guard followup remains one hit/one stock")
	await _start("attack")
	await _wait_idle()
	_check(combat.combo_hits == 1,"No input preserves automatic return")
	# K and pad east are inert reserved bindings, not Step or invulnerability.
	for pad in [false,true]:
		await _start("attack")
		if pad:
			var button := InputEventJoypadButton.new()
			button.button_index = JOY_BUTTON_B
			button.pressed = true
			Input.parse_input_event(button)
			Input.flush_buffered_events()
			button = button.duplicate()
			button.pressed = false
			Input.parse_input_event(button)
			Input.flush_buffered_events()
		else:
			_key(KEY_K)
			_key(KEY_K,false)
		await _ticks(1)
		_check(combat.state == combat.State.Attack,"K/east no gameplay action")
		_damage(10,"K/east gives no invulnerability")
		await _wait_idle()
	# Return continues to receive full damage and permits I interruption.
	await _start("attack")
	_key(KEY_A)
	await _ticks(1)
	_neutral()
	_damage(10,"Direction Return takes full damage")
	_key(KEY_I)
	await _ticks(1)
	_check(combat.state == combat.State.Guard and combat._resume_return,"I interrupts Return")
	before_position = player.global_position
	source.global_position = before_position+player.facing_world*2
	_damage(5,"Return guard retains mitigation")
	_key(KEY_D)
	await _ticks(3)
	_check(player.global_position == before_position,"Return guard stops movement")
	_key(KEY_I,false)
	await _phase(combat.State.Return)
	_damage(10,"Resumed Return vulnerable")
	_neutral()
	await _wait_idle()
	# Dynamic obstruction in the same original return route cannot be crossed.
	await _start("attack")
	_key(KEY_I)
	await _ticks(1)
	var block := _block(expected_anchor.lerp(player.global_position,0.5)+Vector3.UP,Vector3(0.2,2,0.2))
	await _ticks(2)
	_key(KEY_I,false)
	await _phase(combat.State.Recover)
	_key(KEY_A)
	await _wait_idle()
	_check(combat.last_result.contains("blocked") and combat.return_error > 0.03 and not rig.follow_locked,"Obstructed direction Return stops safely")
	block.free()
	# Actual wall contact uses unchanged native recovery and the full capsule.
	await _fresh(origin)
	var wall := _block(Vector3(-6,1,1),Vector3(8,2,0.5))
	_key(KEY_S)
	await _ticks(40)
	_neutral()
	await _ticks(2)
	before_position = player.global_position
	var radius: float = player.get_node("CollisionShape3D").shape.radius
	_check(combat.request_attack(target),"Wall contact permits safe same-side attack")
	await _phase(combat.State.Attack)
	_key(KEY_A)
	await _wait_idle()
	_neutral()
	_check(player.global_position.distance_to(before_position) < 0.03 and player.global_position.z <= 0.451,"Wall-side Return preserves contact safety")
	_check(player.get_node("CollisionShape3D").shape.radius == radius,"No capsule shrink")
	wall.free()
	# HP0, live reset, and scene exit clean up return/guard and pending intent.
	for phase in ["return","guard"]:
		for death in [true,false]:
			await _start("attack")
			if phase == "return": _key(KEY_A)
			else: _key(KEY_I)
			await _ticks(1)
			if death: health.damage(1000)
			else: player.reset_motion(origin)
			_key(KEY_D)
			await _ticks(2)
			_check(not combat.is_busy() and not rig.follow_locked and not combat.queued and sprite.combat_pose == &"","Death/reset clears " + phase)
			if death: _check(not combat.stock._recovery_allowed,"Dead stock recovery inhibited")
	await _fresh(origin)
	for i in range(1,accepted_ids.size()): _check(accepted_ids[i] > accepted_ids[i-1],"Monotonic unique attack IDs")
	for size in [Vector2i(640,360),Vector2i(1152,720)]:
		root.size = size
		await _ticks(3)
		_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(main.get_node("HUD").panel.get_global_rect()),"HUD fits " + str(size))
	combat.request_attack(target)
	root.remove_child(main)
	_check(not combat.queued and not rig.follow_locked and not health.damage_filter.is_valid(),"Scene exit clears queue/camera/damage filter")
	main.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M08 return: directional intent, hold/neutral/taps/noise, guard, stock/hits, safe Return, camera, reset, reserved K/east")
	quit(0 if failures.is_empty() else 1)
