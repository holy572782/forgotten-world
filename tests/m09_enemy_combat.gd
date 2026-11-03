extends "res://tests/m06_target_dash.gd"
## Real physics/animation updates, including hostile attacks during player combat.
const EnemyScene = preload("res://scenes/enemies/practice_enemy.tscn")
const Bolt = preload("res://scripts/enemies/practice_projectile.gd")
var ai: CharacterBody3D
var health: HealthComponent
var origin := Vector3(-6, 0, 0)
var assertions := 0

func _check(ok: bool, message: String) -> void:
	assertions += 1
	super._check(ok, message)

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _press(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _fresh(kind: int = 0, offset: Vector3 = Vector3(1.2, 0, 0)) -> void:
	for action in ["guard", "attack", "move_left", "move_right", "move_up", "move_down"]: _press(action, false)
	combat.cancel()
	if is_instance_valid(ai):
		ai.clear_shots()
		ai.free()
	health.heal(1000)
	player.reset_motion(origin)
	combat.stock.set_recovery_allowed(true)
	combat.stock.advance(20)
	main.get_node("CameraRig").snap_to_target()
	ai = EnemyScene.instantiate()
	ai.settings = load("res://tests/fixtures/enemy_stationary.tres" if kind == 0 else "res://resources/enemies/ranged_practice.tres").duplicate()
	ai.player = player
	ai.position = origin + offset
	main.add_child(ai)
	ai.set_physics_process(false)
	ai.facing=ai._horizontal_direction(player.global_position) # Combat fixture starts with the hero in the new acquisition cone.
	await _ticks(3)
	target = ai.targetable

func _state(next: int, limit: int = 200) -> void:
	for i in range(limit):
		if ai.state == next: return
		await _ticks(1)
	_check(false, "Enemy state timeout " + str(next))

func _phase(next: int) -> void:
	for i in range(150):
		if combat.state == next: return
		await _ticks(1)
	_check(false, "Combat state timeout " + str(next))

func _windup() -> void:
	ai.set_physics_process(true)
	await _state(ai.State.WINDUP)

func _shot(at: Vector3, direction: Vector3, speed: float = 3.0) -> CharacterBody3D:
	var shot := Bolt.new()
	shot.settings = ai.settings.attack.duplicate()
	shot.settings.projectile_speed = speed
	shot.player = player
	shot.source = ai
	ai.add_child(shot)
	shot.global_position = at
	shot.direction = direction
	ai.shots.append(shot)
	return shot

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m09_" + label + "_" + str(Engine.max_fps) + ".png")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	# Keep legacy targets intact but outside these isolated trials.
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"):
			child.position = Vector3(12,0,10)
	await _ticks(5)
	await _fresh(0, Vector3(8,0,0))
	ai.set_physics_process(true)
	await _ticks(8)
	_check(ai.state == ai.State.IDLE, "01 outside detection waits")
	player.reset_motion(ai.global_position - Vector3(5,0,0))
	await _ticks(10)
	_check(ai.state == ai.State.CHASE and ai.global_position.distance_to(ai.home) > 0.05, "02 detection and chase")
	player.reset_motion(origin - Vector3(5,0,0))
	await _state(ai.State.RETURN)
	await _state(ai.State.IDLE)
	_check(ai.global_position.distance_to(ai.home) <= 0.04, "08 safe return home")

	await _fresh()
	var wall := _block(origin + Vector3(0.6,1,0), Vector3(0.15,2,3))
	await _ticks(3)
	await _windup_wall_check()
	wall.free()
	await _ticks(3)
	await _fresh(0, Vector3(1.7,0,0))
	await _windup()
	var before := health.current_hp
	await _ticks(15)
	_check(ai.state == ai.State.WINDUP and health.current_hp == before, "05 windup has no damage")
	await _state(ai.State.RECOVERY)
	_check(health.current_hp == before, "04/10 start distance differs from real hit radius")
	var count: int = ai.attack_count
	await _ticks(25)
	_check(ai.state == ai.State.RECOVERY and ai.attack_count == count, "06/07 mandatory recovery without repeats")

	await _fresh()
	await _windup()
	var locked: Vector3 = ai.facing
	await _capture("melee_windup")
	before = health.current_hp
	await _state(ai.State.RECOVERY)
	_check(is_equal_approx(before - health.current_hp,10), "09/12 front melee hits exactly once")
	await _ticks(10)
	_check(is_equal_approx(before - health.current_hp,10), "12 attack does not repeat damage")
	_check(ai.facing == locked, "melee direction locked during windup")
	await _fresh()
	await _windup()
	player.reset_motion(ai.global_position + Vector3(0,0,1.2))
	await _state(ai.State.RECOVERY)
	_check(health.current_hp == 100, "11 moving sideways after windup misses at actual position")
	await _fresh()
	await _windup()
	wall = _block(origin + Vector3(0.6,1,0), Vector3(0.15,2,3))
	await _ticks(3)
	_check(not ai.melee_hits(), "03 wall at attack time rejects melee")
	await _ticks(65)
	_check(health.current_hp == 100, "03 windup obstruction cancels hostile hit")
	wall.free()

	# Natural launch then normal walking perpendicular to its frozen direction.
	await _fresh(1, Vector3(5,0,0))
	await _windup()
	before = health.current_hp
	await _state(ai.State.ATTACK)
	_check(ai.shots.size() == 1 and health.current_hp == before, "13 ranged emits one shot after telegraph")
	var bolt: CharacterBody3D = ai.shots[0]
	var shot_direction: Vector3 = bolt.direction
	var start: Vector3 = bolt.global_position
	_press("move_down", true)
	for i in range(30):
		_press("move_down", true)
		await _ticks(1)
	_press("move_down", false)
	_check(is_instance_valid(bolt) and bolt.direction == shot_direction, "15 no homing after launch")
	if is_instance_valid(bolt):
		var displacement: Vector3 = bolt.global_position - start
		_check(displacement.cross(shot_direction).length() < 0.001, "13 projectile straight trajectory")
	await _ticks(90)
	_check(health.current_hp == before, "14 normal movement sidesteps slow projectile")
	var live_shots := 0
	for shot in ai.shots:
		if is_instance_valid(shot) and not shot.is_queued_for_deletion(): live_shots += 1
	_check(live_shots <= 1, "19 projectile count bounded")
	ai.set_physics_process(false)
	ai.clear_shots()
	await _ticks(2)
	await _fresh(1, Vector3(5,0,0))
	bolt = _shot(origin + Vector3(2,0.9,0), Vector3.LEFT, 300)
	before = health.current_hp
	await _ticks(3)
	_check(not is_instance_valid(bolt) and is_equal_approx(before-health.current_hp,10), "17 swept sphere crosses entire player in one tick, single damage")
	await _fresh(1, Vector3(5,0,0))
	wall = _block(origin + Vector3(1,1,0), Vector3(0.1,2,3))
	await _ticks(2)
	bolt = _shot(origin + Vector3(2,0.9,0), Vector3.LEFT, 300)
	await _ticks(3)
	_check(not is_instance_valid(bolt) and health.current_hp == 100, "16 wall consumes swept shot before player")
	wall.free()
	await _fresh(1, Vector3(5,0,0))
	bolt = _shot(origin + Vector3(2,0.9,0), Vector3.UP)
	bolt.settings.projectile_lifetime = 0.03
	await _ticks(5)
	_check(not is_instance_valid(bolt), "18 lifetime cleanup")
	bolt = _shot(origin + Vector3(2,0.9,0), Vector3.UP)
	bolt.settings.projectile_range = 0.05
	await _ticks(5)
	_check(not is_instance_valid(bolt), "18 range cleanup")
	bolt = _shot(origin + Vector3(0,0.9,0), Vector3.UP)
	await _ticks(3)
	_check(not is_instance_valid(bolt) and health.current_hp == 90, "17 point blank overlap hits once")

	# Existing mitigation receives the enemy origin, not the temporary projectile position.
	for kind in [0,1]:
		for guarded in [true,false]:
			for front in [true,false]:
				await _fresh(kind, Vector3(1.2,0,0))
				if guarded:
					_press("guard",true)
					await _phase(combat.State.Guard)
					combat.selected_target = null
					combat.target = null
				player.facing_world = Vector3.RIGHT if front else Vector3.LEFT
				before = health.current_hp
				if kind == 0:
					await _windup()
					# No selected target, so Guard preserves the explicitly tested direction.
					await _state(ai.State.RECOVERY)
				else:
					bolt = _shot(origin + Vector3(-1,0.9,0), Vector3.RIGHT, 300)
					await _ticks(3)
				var expected := 5.0 if kind == 0 and guarded and front else 10.0 # Mage magic bypasses ordinary guard (ADR-042).
				_check(is_equal_approx(before-health.current_hp,expected), "20/21/22 melee/bolt guard=" + str(guarded) + " front=" + str(front))
				_press("guard",false)

	# Hostile shots remain active during Approach, Attack and Return; no invulnerability.
	for phase in [combat.State.Approach,combat.State.Attack,combat.State.Return]:
		await _fresh(0, Vector3(3,0,0))
		_check(combat.request_attack(target), "start combat for hostile phase " + str(phase))
		if phase == combat.State.Attack: await _phase(phase)
		if phase == combat.State.Return:
			await _phase(combat.State.Attack)
			_press("move_down", true)
			await _phase(phase)
		before = health.current_hp
		bolt = _shot(player.global_position + Vector3(0,0.9,0), Vector3.UP)
		await _ticks(1)
		_check(is_equal_approx(before-health.current_hp,10), "23/24/25 hostile shot hits combat phase " + str(phase))
		if phase == combat.State.Return:
			_press("guard",true)
			await _phase(combat.State.Guard)
			_check(combat._resume_return, "26 return Guard interruption preserved")
			_press("guard",false)
			await _wait_idle()
			var after_return: Vector3 = player.global_position
			for i in range(12):
				_press("move_down", true)
				await _ticks(1)
			_check(player.global_position.distance_to(after_return) > 0.05, "27/28 direction return then held normal walk")
			_press("move_down",false)

	# Moving enemy follows current Targetable position; only locomotion freezes.
	await _fresh(0, Vector3(3.5,0,0))
	ai.set_physics_process(true)
	await _ticks(15)
	_check(ai.global_position.distance_to(ai.home) > 0.1 and target.global_position == ai.global_position, "30 moving Targetable tracks body")
	_check(combat.request_attack(target), "30 select moving enemy")
	var held: Vector3 = ai.global_position
	_check(combat.request_followup(target), "31 reserve one extra strike")
	_check(not combat.request_followup(target), "31 reject second reservation")
	await _phase(combat.State.Attack)
	await _capture("counterattack")
	for i in range(100):
		if combat.combo_hits >= 2: break
		await _ticks(1)
	_check(combat.combo_hits == 2 and ai.global_position.distance_to(held) < 0.001, "30 moving target supports combo without invalidation")
	_check(combat.stock.current == 1 and combat.queued == false, "31 stock spent once per started strike")
	await _wait_idle()
	_check(ai.attack_count >= 1, "enemy windup and counterattack continue while locomotion held")

	# Death cancels pending windup and existing shots, and deselects immediately.
	await _fresh(1, Vector3(4,0,0))
	await _windup()
	bolt = _shot(origin + Vector3(3,0.9,0), Vector3.UP)
	ai.health.damage(100,player)
	await _ticks(5)
	_check(ai.state == ai.State.DEAD and not ai.telegraph.visible and not target.alive() and ai.attack_count == 0 and not is_instance_valid(bolt), "33 enemy death clears telegraph/shots and disables targets")
	await _fresh()
	await _windup()
	health.damage(100,ai)
	await _ticks(5)
	_check(not combat.is_busy() and ai.state in [ai.State.RETURN,ai.State.IDLE] and ai.attack_count == 0, "33 player death cancels combat and new hostile attacks")
	# Physical safety of AI using unchanged full capsule / floor route checks.
	await _fresh(0, Vector3(2,0,0))
	wall = _block(ai.global_position + Vector3(-0.5,1,0),Vector3(0.15,2,2))
	await _ticks(3)
	var old: Vector3 = ai.global_position
	ai._walk_towards(origin,1.0)
	_check(ai.global_position.distance_to(old) < 0.001, "32 AI cannot cross wall")
	wall.free()
	ai.global_position = Vector3(0,0,13.4)
	await _ticks(3)
	old = ai.global_position
	ai._walk_towards(Vector3(0,0,16),1.0)
	_check(ai.global_position.distance_to(old) < 0.001, "32 AI footprint rejects cliff route")

	# Mode switches never activate both enemies; reset and scene teardown clear combat.
	var selector = main.get_node("PracticeSelector")
	selector.select_mode(1)
	await _ticks(3)
	_check(is_instance_valid(selector.active_enemy) and selector.active_enemy.settings.attack.kind == 0, "mode melee")
	var previous_enemy: CharacterBody3D = selector.active_enemy
	selector.select_mode(2)
	await _ticks(3)
	_check(not is_instance_valid(previous_enemy) and selector.active_enemy.settings.attack.kind == 2 and health.current_hp == 100 and not combat.is_busy(), "33 isolated ranged/reset")
	selector.active_enemy._set_state(selector.active_enemy.State.WINDUP)
	previous_enemy = selector.active_enemy
	selector.select_mode(2)
	await _ticks(3)
	_check(not is_instance_valid(previous_enemy) and selector.active_enemy.attack_count == 0, "33 reset during windup clears previous attack")
	selector.select_mode(0)
	await _ticks(3)
	_check(not is_instance_valid(selector.active_enemy), "34 static mode has no AI or battle scene transition")
	_check(sprite.equipped_shield != null and main.get_node("CameraRig").settings != null, "35 existing shield and camera remain")
	await _fresh(1, Vector3(4,0,0))
	await _windup()
	await _state(ai.State.ATTACK)
	await _ticks(15)
	await _capture("ranged_shot")
	main.queue_free()
	await _ticks(3)
	_check(get_nodes_in_group("combat_targets").is_empty(), "33 scene exit frees all combat targets")
	if failures.is_empty(): print("M09 PASS: ", assertions, " assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _windup_wall_check() -> void:
	ai.set_physics_process(true)
	await _ticks(65)
	_check(ai.state == ai.State.IDLE and ai.attack_count == 0 and health.current_hp == 100, "03 wall blocks detection/attack")
