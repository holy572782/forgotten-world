extends "res://tests/enemy_tactics.gd"
## Real warning clocks, frozen target jobs, damage and projectile collisions.
var locks: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var aim_metrics: Array[Dictionary] = []
var damage_ticks: Array[int] = []
var attack_ticks: Array[int] = []
var warning_tick := 0

func _record_attack() -> void: attack_ticks.append(Engine.get_physics_frames())

func _record_damage(_amount: float, source: Node) -> void:
	if source == ai: damage_ticks.append(Engine.get_physics_frames())

func _record_lock() -> void:
	locks.append({"position":ai.aimed_position,"facing":ai.facing,"elapsed":ai.elapsed,"tick":Engine.get_physics_frames()})

func _record_release(shot: CharacterBody3D) -> void:
	releases.append({"position":shot.global_position,"direction":shot.direction,"tick":Engine.get_physics_frames()})

func _prepare(kind: int, ratio: float, distance: float = 4.5) -> void:
	player.set_physics_process(true) # Let the normal neutral-input latch reset in the fixture.
	for audio in get_nodes_in_group("projectile_launch_audio"): audio.free()
	if kind == 0: await _fresh_sword(distance)
	else:
		await _fresh(1,Vector3(distance,0,0))
		ai.settings = ai.settings.duplicate()
		ai.settings.attack = ai.settings.attack.duplicate()
	player.set_physics_process(false)
	ai.settings.attack.aim_lock_ratio = ratio
	locks.clear()
	releases.clear()
	damage_ticks.clear()
	attack_ticks.clear()
	cue_count = 0
	ai.aim_committed.connect(_record_lock)
	ai.attack_warning_started.connect(_cue)
	ai.projectile_released.connect(_record_release)
	ai.attack_started.connect(_record_attack)
	warning_tick = Engine.get_physics_frames()
	ai._start_windup()
	ai.set_physics_process(true)
	_check(ai.state == ai.State.WINDUP,"Safe warning starts")

func _await_lock() -> void:
	for tick in range(120):
		if not locks.is_empty(): return
		await _ticks(1)
	_check(false,"One lock event eventually occurs")

func _await_recovery() -> void:
	for tick in range(240):
		if ai.state == ai.State.RECOVERY: return
		await _ticks(1)
	_check(false,"Attack or cancellation reaches recovery")

func _fixed_attack(kind: int, ratio: float) -> void:
	await _prepare(kind,ratio)
	var anchor: Vector3 = ai.attack_anchor
	if ratio > 0.0:
		var before: float = ai.active_attack.windup_seconds*ratio*0.5
		await _seconds(before)
		player.global_position = origin+Vector3(0,0,0.25)
		await _ticks(1)
		_check(not ai.aim_locked and ai.aimed_position == player.global_position,"Before lock, current position remains the preview")
	await _await_lock()
	var captured: Vector3 = ai.aimed_position
	var direction: Vector3 = ai.facing
	_check(locks.size() == 1 and captured == player.global_position,"Target captured once at lock")
	var expected: float = ai.active_attack.windup_seconds*ratio
	_check(absf(locks[0].elapsed-expected) <= 0.035,"Lock follows configured warning ratio")
	player.global_position = origin+Vector3(0,0,4.0)
	# Occlude only the escaped player's position, not the fixed aim point.
	var wall: StaticBody3D
	if kind == 1: wall = _block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.3,2.0,0.5))
	for tick in range(220):
		if ai.state == ai.State.RECOVERY: break
		_check(ai.aimed_position == captured and ai.facing == direction,"Post-lock target and direction never follow the player")
		await _ticks(1)
	_check(ai.state == ai.State.RECOVERY and ai.attack_count == 1,"One attack finishes at a fixed target")
	if kind == 0 and not attack_ticks.is_empty():
		var expected_attack: float = ai.active_attack.windup_seconds+ai.settings.aim_commit_minimum_seconds-ai.active_attack.hit_delay_seconds
		_check(absf(float(attack_ticks[0]-warning_tick)/60.0-expected_attack)<0.05,"Earlier aim lock preserves the previous melee attack cadence")
	_check(locks.size() == 1 and cue_count == 1,"One capture and warning cue per attack")
	_check(health.current_hp == 100,"Escaping sideways avoids actual damage")
	if kind == 0:
		# At 30 render FPS, a second physics tick may already start the existing
		# recovery walk. Inspect its actual entry position, not the later draw tick.
		_check(ai.get_node("ReturnTrace").last_recovery_position.distance_to(anchor) < 0.03,"Fixed melee returns to its original anchor")
	else:
		_check(releases.size() == 1,"Caster releases even when the escaped player is occluded")
		if not releases.is_empty():
			var expected_release: float = maxf(ai.active_attack.windup_seconds,locks[0].elapsed+ai.settings.aim_commit_minimum_seconds)
			_check(absf(float(releases[0].tick-warning_tick)/60.0-expected_release)<0.05,"Mage keeps warning duration and adds only a missing avoidance interval")
			var expected_direction: Vector3 = (captured+Vector3.UP*0.9-releases[0].position).normalized()
			_check(releases[0].direction.dot(expected_direction) > 0.99999,"Projectile direction uses the fixed target and actual muzzle")
			var shot: CharacterBody3D = ai.shots[0] if not ai.shots.is_empty() else null
			await _seconds(0.25)
			if is_instance_valid(shot): _check(shot.direction == releases[0].direction,"Projectile stays non-homing in flight")
	if is_instance_valid(wall): wall.free()
	aim_metrics.append({"kind":kind,"ratio":ratio,"lock_elapsed":locks[0].elapsed,"captures":locks.size(),"release_count":releases.size()})
	# The next attack may acquire a different target, with fresh snapshot settings.
	ai.set_physics_process(false)
	player.global_position = origin
	ai._start_windup()
	ai.set_physics_process(true)
	await _seconds(ai.active_attack.windup_seconds*ratio+0.04)
	_check(locks.size() == 2 and locks[1].position == origin,"Next warning captures a new position once")

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		var saved: Resource = load("res://.godot/aim_lock_saved.tres")
		_check(is_equal_approx(saved.aim_lock_ratio,0.7) and is_equal_approx(saved.snapshot().aim_lock_ratio,0.7),"Ratio survives save and fresh-process snapshot")
		print("AIM LOCK RELOAD ","PASS" if failures.is_empty() else "FAIL")
		quit(0 if failures.is_empty() else 1)
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	health.damage_applied.connect(_record_damage)
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	_check(is_equal_approx(load("res://resources/enemies/melee_attack.tres").aim_lock_ratio,0.4) and is_equal_approx(load("res://resources/enemies/ranged_attack.tres").aim_lock_ratio,0.5),"Production attack profiles use 40% / 50%")
	for kind in [0,1]:
		for ratio in [0.0,0.4,0.5,0.7,1.0]: await _fixed_attack(kind,ratio)
	# In-range victim: physical damage still happens once, magic bypasses held guard.
	for kind in [0,1]:
		await _prepare(kind,1.0,1.2)
		player.facing_world = Vector3.RIGHT
		_press("guard",true)
		player.set_physics_process(true)
		await _await_lock()
		var locked_tick: int = locks[0].tick
		await _await_recovery()
		_check(float(Engine.get_physics_frames()-locked_tick)/60.0 >= ai.settings.aim_commit_minimum_seconds-0.035,"Ratio one preserves the minimum avoidance interval")
		await _seconds(0.4)
		print("AIM GUARD kind=",kind," hp=",health.current_hp," state=",combat.state)
		_check(is_equal_approx(health.current_hp,95.0 if kind == 0 else 90.0),"Physical guard and magic penetration retain existing damage")
		_check(damage_ticks.size() == 1 and float(damage_ticks[0]-locked_tick)/60.0 >= ai.settings.aim_commit_minimum_seconds-0.035,"Actual damage, not merely recovery, respects the lock-to-hit interval")
		if kind == 1: _check(float(releases[0].tick-locked_tick)/60.0 >= ai.settings.aim_commit_minimum_seconds-0.035,"Point-blank magic also reserves a pre-release dodge interval")
		if kind == 1: _check(combat.state == combat.State.Guard,"Magic hit leaves held guard available")
		_press("guard",false)
	# No capture refresh while the shared planning budget is exhausted.
	await _prepare(0,0.0)
	ai.set_physics_process(false)
	var fixed: Vector3 = ai.aimed_position
	var budget = load("res://scripts/combat/planning_budget.gd")
	while budget.take(): pass
	ai.elapsed = 1.0
	ai._windup_step(1.0/60.0)
	_check(not ai._aim_plan_ready and ai.state == ai.State.WINDUP,"No movement before a budgeted fixed plan is ready")
	player.global_position += Vector3.BACK*4.0
	await _ticks(1)
	ai.set_physics_process(true)
	await _await_recovery()
	_check(ai.aimed_position == fixed and locks.size() == 1,"Budget waits never re-acquire the moved victim")
	# A wall introduced after lock cannot authorize a stale outward/return route.
	await _prepare(0,0.4)
	await _await_lock()
	var wall := _block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.3,2.0,4.0))
	await _await_recovery()
	_check(ai.attack_count == 0 and health.current_hp == 100 and ai.position.distance_to(ai.attack_anchor)<0.03,"Blocked fixed plan safely cancels without damage or takeoff")
	wall.free()
	await _prepare(1,0.5)
	await _await_lock()
	wall = _block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.3,2.0,4.0))
	await _await_recovery()
	_check(releases.is_empty(),"A new wall in the fixed firing line prevents spawning")
	wall.free()
	await _prepare(1,0.5)
	await _await_lock()
	wall = _block(ai.global_position+Vector3(0,0.9,0.15),Vector3(0.08,0.08,0.08))
	await _ticks(2) # Let the newly created static collider enter the physics space.
	var line_clear: bool = ai.Elevation.Blade._line(ai,ai.global_position+Vector3.UP*0.9,ai.aimed_position+Vector3.UP*0.9)
	_check(line_clear and not ai._projectile_release_clear(),"Muzzle sphere rejects a side overlap even when its centre ray is clear")
	await _await_recovery()
	_check(releases.is_empty(),"No projectile is created inside the muzzle obstruction")
	wall.free()
	await _prepare(0,0.0)
	ai.set_physics_process(false)
	while budget.take(): pass
	ai.elapsed = ai.active_attack.windup_seconds+2.01
	ai._windup_step(1.0/60.0)
	_check(ai.state == ai.State.RECOVERY and ai.attack_count == 0 and ai._aim_job.is_empty(),"A starved plan times out safely instead of leaving an endless warning")
	await _prepare(1,0.7)
	ai.settings.attack.aim_lock_ratio = 0.0
	await _await_lock()
	_check(absf(locks[0].elapsed-0.7)<0.035,"Editing a shared attack setting cannot move an already-started attack's lock")
	# Cancellation/death clears the job and warning visuals; no duplicate event.
	for kind in [0,1]:
		await _prepare(kind,0.7)
		ai.health.damage(100,player)
		await _ticks(2)
		_check(ai.state == ai.State.DEAD and locks.is_empty() and ai._aim_job.is_empty(),"Enemy death before lock leaves no job or capture")
		if kind == 1: _check(not ai.get_node("CastingCircle").is_presenting(),"Caster death clears the existing circle")
		await _prepare(kind,0.5)
		await _await_lock()
		health.damage(1000,ai)
		await _ticks(2)
		_check(ai.state not in [ai.State.WINDUP,ai.State.ATTACK,ai.State.DASH_APPROACH] and locks.size() == 1 and releases.is_empty(),"Player death safely ends a locked attack")
		if kind == 1: _check(not ai.get_node("CastingCircle").is_presenting(),"Target death clears the locked cast's circle")
	var saved: Resource = load("res://resources/enemies/melee_attack.tres").duplicate()
	saved.aim_lock_ratio = 0.7
	_check(ResourceSaver.save(saved,"res://.godot/aim_lock_saved.tres") == OK,"Aim ratio is serializable per attack")
	saved.aim_lock_ratio = NAN
	_check(saved.snapshot().aim_lock_ratio == 0.0,"Invalid ratio has a finite fallback")
	main.free()
	for failure in failures: push_error(failure)
	print("AIM LOCK ","PASS" if failures.is_empty() else "FAIL",": ",assertions," fps cap=",Engine.max_fps," metrics=",JSON.stringify(aim_metrics))
	quit(0 if failures.is_empty() else 1)
