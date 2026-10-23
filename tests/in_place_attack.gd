extends "res://tests/iron_sword_animation.gd"
## Real physics / animation / HP; never invoke a hit callback.
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
var accepted: Array[int] = []
var accepted_positions: Array[Vector3] = []
var victim_ids: Array[int] = []
var events: Array[int] = []
var anchor := Vector3.ZERO
var start_tick := 0
var ending_tick := 0
var maximum_drift := 0.0
var metrics: Array[Dictionary] = []

func _prepare(distance := 1.3, yaw := 0.0, duration := 0.48) -> void:
	for action in ["move_left","move_right","move_up","move_down","jump"]: _press(action,false)
	await _reset(yaw,duration)
	combat.equipped_weapon.motion = initial_weapon.motion.duplicate()
	target.get_parent().position = origin+Vector3(0,0,-distance)
	for path in ["TrainingEnemySecond","TrainingEnemyThird"]: main.get_node(path).position = Vector3(12,0,10)
	await _ticks(3)
	anchor = player.global_position
	maximum_drift = 0.0
	accepted.clear()
	accepted_positions.clear()
	victim_ids.clear()
	events.clear()
	hits = 0
	ending_tick = 0

func _begin() -> void:
	await physics_frame # Match the receiving physics tick of actual attack input.
	start_tick = Engine.get_physics_frames()
	_check(combat.request_attack(target), "Safe target accepted")
	_check(combat.return_anchor == anchor, "Original anchor saved even without travel")

func _done(queue := false) -> void:
	for tick in range(700):
		if not combat.is_busy(): break
		if queue and target.alive() and not combat.queued and combat.can_combo_select(target): combat.request_followup(target)
		await _ticks(1)
		maximum_drift = maxf(maximum_drift, player.global_position.distance_to(anchor))
		_check(combat.return_anchor == anchor, "Combo never replaces original anchor")
		if combat._empty_slot: _check(not sprite._attacking and not sword.visible and not player.get_node("SlashEffect").visible, "Empty slot has no fake swing")
	_check(not combat.is_busy() and not rig.follow_locked, "Normal exit releases state and camera")
	_check(not combat.queued and not sword.visible and not player.get_node("SlashEffect").visible, "Exit clears queue and visuals")
	_check(combat.return_error < 0.03, "Ends at original anchor")

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	sword = player.get_node("WeaponSwing")
	health = player.get_node("HealthComponent")
	rig = main.get_node("CameraRig")
	target = main.get_node("TrainingEnemy/Targetable")
	var saved_ratios: PackedFloat32Array = load("res://resources/weapons/default_attack_motion.tres").frame_time_ratios.duplicate()
	initial_weapon = combat.equipped_weapon.duplicate()
	initial_weapon.motion = Motion.new() # Reproducible fixture, not the editable F5 settings.
	visual = initial_weapon.attack_visual
	combat.attack_accepted.connect(func(_id: int,_combo: int):
		accepted.append(Engine.get_physics_frames())
		accepted_positions.append(player.global_position))
	combat.hit.connect(func(victim: Node): hits += 1; victim_ids.append(victim.get_instance_id()))
	combat.state_changed.connect(func(next: int):
		events.append(next)
		if next in [combat.State.Return,combat.State.Idle] and ending_tick == 0: ending_tick = Engine.get_physics_frames())
	await _ticks(15)
	var end_after_strike := 0
	for distance in [1.3,3.0]:
		await _prepare(distance)
		await _begin()
		_check(combat.state == (combat.State.Attack if distance < 1.4 else combat.State.Approach), "Close starts Attack, far starts Approach")
		if distance < 1.4:
			_check(accepted == [start_tick] and combat.stock.current == 2, "In-place strike starts and pays immediately")
		await _done()
		_check(hits == 1 and combat.stock.current == 2, "One normal hit and cost")
		if distance < 1.4:
			_check(maximum_drift < 0.00001 and not combat.State.Approach in events and not combat.State.Return in events, "No translation or timed zero-distance states")
			end_after_strike = ending_tick-accepted[0]
		else:
			_check(combat.State.Approach in events and combat.State.Return in events and maximum_drift > 1.0, "Far target retains visible travel and return")
			_check(abs(ending_tick-accepted[0]-end_after_strike) <= 2, "Same swing and ending rhythm after arrival")
		metrics.append({"distance":distance,"accepted":accepted[0]-start_tick,"natural_end":ending_tick-accepted[0],"drift":maximum_drift})
	# Exact reach edge: one decision, with no repeated tiny approaches.
	for distance in [1.399,1.4,1.401]:
		await _prepare(distance)
		await _begin()
		_check(combat.state == (combat.State.Attack if distance <= 1.4 else combat.State.Approach), "Shared reach boundary "+str(distance))
		await _done()
		_check(events.count(combat.State.Approach) == (0 if distance <= 1.4 else 1), "Boundary never oscillates")
		_check(hits == 1, "Boundary hit uses same geometry")
	# Weapon reach changes the branch, without changing target-mark range.
	for config in [Vector2(0.9,1.0),Vector2(2.0,1.8)]:
		await _prepare(config.y)
		combat.equipped_weapon.melee_reach = config.x
		await _ticks(1)
		_check(target.marker.visible, "Gold target remains selectable independently of reach")
		await _begin()
		_check(combat.state == (combat.State.Attack if config.y <= config.x else combat.State.Approach), "Weapon-specific reach selects branch")
		await _done()
		_check(hits == 1, "Short reach stops within its real hit range")
	# Legacy single-target geometry is reused rather than introducing another hitbox.
	for distance in [1.15,1.25]:
		await _prepare(distance)
		combat.equipped_weapon.hit_shape = WeaponData.HitShape.SINGLE_TARGET
		await _begin()
		_check(combat.state == (combat.State.Attack if distance < 1.2 else combat.State.Approach), "Legacy single-target range shared")
		await _done()
		_check(hits == 1, "Legacy single-target damage unchanged")
	# Weighted frames, all directions and live Q/E still share the body clock.
	for yaw in [0.0,90.0,180.0,270.0]:
		await _prepare(1.3,yaw,0.72)
		combat.equipped_weapon.motion.frame_time_ratios = PackedFloat32Array([1,0.4,1])
		await _begin()
		var seen: Dictionary = {}
		while sprite._attacking:
			await _ticks(1)
			if not sprite._attacking: break
			_check_sync()
			var slash: AnimatedSprite3D = player.get_node("SlashEffect")
			_check(slash.visible and slash.frame == sprite.frame and is_equal_approx(slash.frame_progress,sprite.frame_progress), "In-place slash shares weighted clock")
			if not seen.has(sprite.frame):
				seen[sprite.frame] = true
				await _capture_iron("in_place_"+str(int(yaw))+"_"+str(sprite.frame))
		_check(seen.size() == 3, "Three weighted frames in each direction")
		await _done()
		_check(maximum_drift < 0.00001 and hits == 1, "Direction does not cause travel or extra hits")
	await _prepare(1.3,0,0.72)
	await _begin()
	_press("camera_right",true)
	for tick in range(35):
		await _ticks(1)
		if sprite._attacking: _check_sync()
	_press("camera_right",false)
	await _done()
	_check(not combat.State.Approach in events and maximum_drift < 0.00001, "Q/E orbit never adds a step")
	# Live and lethal rhythms retain three planned slots without phantom costs.
	var reference_end := 0
	for lethal_at in [0,1,2]:
		await _prepare(1.3,0,0.48)
		if lethal_at > 0: target.health.damage(target.health.current_hp-lethal_at*10)
		await _begin()
		await _done(true)
		if lethal_at == 0: reference_end = ending_tick-start_tick
		else: _check(abs(ending_tick-start_tick-reference_end) <= 4, "Lethal rhythm within existing render/physics quantization bound")
		var actual: int = 3 if lethal_at == 0 else lethal_at
		_check(hits == actual and accepted.size() == actual and combat.stock.current == 3-actual, "Real hits only, even after lethal hit")
		_check(combat._sequence_slots == 3 and not combat.State.Approach in events and not combat.State.Return in events, "Three slots without travel")
		metrics.append({"lethal_at":lethal_at,"sequence_ticks":ending_tick-start_tick})
	# A near -> B far -> C near: only B approaches; all return to the original start.
	await _prepare(1.2)
	var b: Node3D = main.get_node("TrainingEnemySecond/Targetable")
	var c: Node3D = main.get_node("TrainingEnemyThird/Targetable")
	b.get_parent().position = origin+Vector3(2.7,0,-1.2)
	c.get_parent().position = origin+Vector3(1.6,0,-1.9)
	await _ticks(3)
	await _begin()
	_check(combat.request_followup(b), "Reserve far B from near A")
	var reserved_c := false
	for tick in range(400):
		if not combat.is_busy(): break
		if combat.combo_hits == 2 and not reserved_c:
			reserved_c = combat.request_followup(c)
		await _ticks(1)
		_check(combat.return_anchor == anchor, "ABC preserves first anchor")
	_check(reserved_c and hits == 3 and victim_ids == [target.get_instance_id(),b.get_instance_id(),c.get_instance_id()], "ABC damages the intended targets once")
	_check(events.count(combat.State.Approach) == 1 and events.count(combat.State.Return) == 1, "Only far B approaches; mixed sequence returns")
	_check(accepted_positions.size() == 3 and accepted_positions[0] == anchor and accepted_positions[1].is_equal_approx(accepted_positions[2]), "C attacks from B's ending position")
	_check(combat.return_error < 0.03 and not rig.follow_locked, "ABC ends safely at original anchor")
	# Existing cancellation / defense / jump input with no travel to resume.
	await _prepare()
	await _begin()
	_press("move_right",true)
	await _ticks(2)
	_check(not combat.is_busy() and not combat.State.Return in events and hits == 0, "Direction ends in-place attack immediately")
	_press("move_right",false)
	await _prepare()
	await _begin()
	_press("guard",true)
	await _ticks(2)
	_check(combat.state == combat.State.Guard and not sword.visible, "Guard cancels in-place presentation")
	_press("guard",false)
	await _ticks(2)
	_check(combat.request_followup(target), "Defense follow-up accepted")
	await _ticks(2)
	_check(combat.state == combat.State.Attack and not combat.State.Approach in events, "Close defense follow-up needs no approach")
	await _done()
	await _prepare()
	await _begin()
	await _done()
	await _ticks(2) # Existing jump release gate clears on a neutral FREE tick.
	_press("jump",true)
	await _ticks(4)
	_check(player.global_position.y > anchor.y+0.1 and not combat.request_attack(target), "Jump resumes; airborne start still rejected")
	_press("jump",false)
	# Walls, including a low obstacle below the old sight ray.
	for height in [0.25,2.0]:
		await _prepare()
		var wall := _block(origin+Vector3(0,height/2.0,-0.65),Vector3(0.8,height,0.1))
		await _ticks(3)
		_check(not combat.can_select(target) and not combat.request_attack(target), "Close wall rejects attack at height "+str(height))
		_check(combat.stock.current == 3 and hits == 0, "Blocked attack is unpaid")
		wall.free()
	# A new wall after acceptance cancels before impact, without refund/extra hit.
	await _prepare()
	await _begin()
	var wall := _block(origin+Vector3(0,1,-0.65),Vector3(0.8,2,0.1))
	await _ticks(3)
	_check(not combat.is_busy() and hits == 0 and combat.stock.current == 2, "Late obstruction cancels existing strike safely")
	wall.free()
	# Sweep recipients behind a low side obstacle also stay unharmed.
	await _prepare(1.2)
	b.get_parent().position = origin+Vector3(0.9,0,-0.9)
	b.health.heal(100)
	wall = _block(origin+Vector3(0.45,0.2,-0.45),Vector3(0.15,0.4,0.15))
	await _ticks(3)
	await _begin()
	await _done()
	_check(hits == 1 and b.health.current_hp == 40, "Incidental sweep cannot hit through low terrain")
	wall.free()
	# Gap between two supported endpoints: sight and distance alone are insufficient.
	await _prepare()
	var ground: StaticBody3D = main.get_node("TestArena/Terrain/FlatGround")
	var ground_layer := ground.collision_layer
	ground.collision_layer = 0
	var near_floor := _block(origin+Vector3(0,-0.5,0.6),Vector3(4,1,2))
	var far_floor := _block(origin+Vector3(0,-0.5,-1.8),Vector3(4,1,1.8))
	await _ticks(3)
	_check(combat.Path.sight(player,target.global_position) and combat._in_place(target,combat.equipped_weapon), "Gap fixture is close and visible")
	_check(not combat.can_select(target) and not combat.request_attack(target) and combat.stock.current == 3, "Gap between attacker and target blocks attack")
	ground.collision_layer = ground_layer
	near_floor.free()
	far_floor.free()
	await _prepare()
	target.get_parent().position.y += 0.1
	await _ticks(3)
	_check(not combat.request_attack(target), "Step height still rejected")
	_check(load("res://resources/weapons/default_attack_motion.tres").frame_time_ratios == saved_ratios, "User's saved frame tuning is untouched")
	FileAccess.open("res://.godot/in_place_metrics_"+str(Engine.max_fps)+".json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print(JSON.stringify(metrics))
	main.queue_free()
	await _ticks(2)
	if failures.is_empty(): print("IN PLACE ATTACK PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
