extends "res://tests/enemy_tactics.gd"
const Route = preload("res://scripts/combat/dash_path.gd")
const Sector = preload("res://scripts/combat/melee_sweep.gd")
var received_height := -INF
var received_count := 0
var jump_metrics: Array[Dictionary] = []

class JumpTrace extends Node:
	var actor: CharacterBody3D
	var player: CharacterBody3D
	var peak := 0.0
	var aborted := false
	var lock_elapsed := -1.0
	func _ready() -> void: process_physics_priority = 120
	func _physics_process(_delta: float) -> void:
		peak = maxf(peak,player.global_position.y)
		if actor.aim_locked and lock_elapsed < 0.0: lock_elapsed = actor.elapsed
		if actor.attack_count == 0 and actor.state in [actor.State.RECOVERY,actor.State.RETURN]: aborted = true

func _fresh_sword(distance: float) -> void:
	_press("jump",false)
	await super._fresh_sword(distance)
	var trace := JumpTrace.new()
	trace.name = "JumpTrace"
	trace.actor = ai
	trace.player = player
	ai.add_child(trace)
	received_height = -INF
	received_count = 0

func _received(_amount: float, source: Node) -> void:
	if source == ai:
		received_height = player.global_position.y-ai.global_position.y
		received_count += 1

func _jump() -> void:
	_press("jump",true)
	await _ticks(1)
	_press("jump",false)

func _reload_jump() -> void:
	var saved: Resource = load("res://.godot/enemy_jump_saved.tres")
	var snapshot: Resource = saved.snapshot()
	_check(saved.override_weapon_hit_height and is_equal_approx(saved.hit_height_tolerance,0.8) and is_equal_approx(saved.target_ground_probe_depth,3.0), "Enemy override and independent floor search depth persist")
	_check(is_equal_approx(snapshot.weapon.hit_height_tolerance,0.8) and is_equal_approx(SharedSword.hit_height_tolerance,0.3), "Reload preserves private enemy height without changing player")
	for failure in failures: push_error(failure)
	print("ENEMY JUMP RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_jump()
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	health.damage_applied.connect(_received)
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	var sword_hash := FileAccess.get_sha256("res://resources/weapons/one_handed_sword.tres")
	await _fresh_sword(2.0)
	_check(is_equal_approx(ai.active_attack.hit_height_tolerance,1.4) and is_equal_approx(ai.active_attack.weapon.hit_height_tolerance,1.4) and is_equal_approx(SharedSword.hit_height_tolerance,0.3), "Soldier 1.4m override is separate from shared 0.3m player weapon")
	cue_count = 0
	ai.get_node("AttackWarning").warning_sound_presented.connect(_cue)
	await _windup()
	await _seconds(0.1)
	ai.get_node("AttackWarning")._process(0.0)
	_check(ai.get_node("AnimatedSprite3D").material_override.get_shader_parameter("attack_warning_strength") > 0.0, "Jump starts during an actual red pulse")
	await _jump()
	await _ticks(10)
	_check(ai.state == ai.State.WINDUP and ai.aimed_position.distance_to(player.global_position) < 0.001 and ai.dash_destination.y == ai.attack_anchor.y, "Airborne feet remain tracked while the route stays grounded")
	await _finish_strike()
	var trace: Node = ai.get_node("JumpTrace")
	_check(not trace.aborted and trace.peak > 1.1 and cue_count == 1 and received_count == 1, "A real jump during red warning never aborts or retriggers Fire1")
	_check(absf(trace.lock_elapsed-ai.active_attack.windup_seconds) < 0.035 and ai.get_node("ReturnTrace").last_recovery_position.distance_to(ai.attack_anchor) < 0.001, "Original lock time and return anchor remain unchanged")
	# Normal Space jump timed so the actual enemy hit occurs at its real apex.
	for distance in [2.0,4.5]:
		await _fresh_sword(distance)
		await _windup()
		await _locked()
		await _seconds(0.1)
		await _jump()
		await _finish_strike()
		trace = ai.get_node("JumpTrace")
		_check(received_height > 1.1 and received_height <= 1.4 and received_count == 1 and health.current_hp == 90, "Real jump apex is hit once at near/far range with unchanged damage")
		_check(not trace.aborted and ai.get_node("ReturnTrace").last_recovery_position.distance_to(ai.attack_anchor) < 0.001, "Apex strike completes its existing approach/return")
		jump_metrics.append({"distance":distance,"peak":trace.peak,"height_at_damage":received_height,"lock_elapsed":trace.lock_elapsed})
		await _seconds(0.5)
		_check(player.is_on_floor(), "Player lands normally after the strike")
		await _state(ai.State.WINDUP)
		await _finish_strike()
		_check(received_count == 2 and health.current_hp == 80, "Next grounded attack still works after landing")
	# Actual hit uses actual height; planning uses the independently detected floor.
	for height in [0.3,1.2,1.4,1.401,1.8]:
		await _fresh_sword(2.0)
		player.set_physics_process(false)
		player.global_position.y = height
		ai._start_windup()
		_check(ai.state == ai.State.WINDUP and ai._in_place and ai.dash_destination == ai.attack_anchor, "Air height alone never causes movement or unsafe-plan cancellation")
		_check(ai.melee_hits() == (height <= 1.4), "Actual hit height boundary is respected: "+str(height))
		player.set_physics_process(true)
	await _fresh_sword(2.0)
	var profile: Resource = ai.settings.attack.snapshot()
	for height in [-1.4,1.4]:
		_check(Sector.contains(ai.global_position,Vector3.LEFT,origin+Vector3.UP*height,profile.weapon), "Symmetric enemy hit shape accepts +/-1.4m independently of terrain permission")
	_check(not Sector.contains(ai.global_position,Vector3.LEFT,origin+Vector3.UP*1.2,SharedSword), "Player's existing 0.3m hit shape still rejects a high enemy")
	ai.settings.attack.hit_height_tolerance = 0.5
	ai._start_windup()
	player.set_physics_process(false)
	player.global_position.y = 1.2
	ai._plan_attack()
	_check(ai.state == ai.State.WINDUP and ai._in_place and not ai.melee_hits(), "A short enemy blade misses the jump without turning it into a path failure")
	player.set_physics_process(true)
	# Real guard remains unchanged while the player is above the floor.
	await _fresh_sword(2.0)
	player.facing_world = Vector3.RIGHT
	_press("guard",true)
	await _phase(combat.State.Guard)
	player.set_physics_process(false)
	player.global_position.y = 1.2
	await _windup()
	await _finish_strike()
	_check(received_count == 1 and health.current_hp == 95, "Existing directional guard still halves an airborne accepted hit")
	player.set_physics_process(true)
	_press("guard",false)
	combat.cancel()
	# Walls, real platforms, low barriers, gaps, no floor and depth bounds stay unsafe.
	for kind in ["wall","low_wall","gap","no_floor","too_high"]:
		await _fresh_sword(2.0)
		player.set_physics_process(false)
		var barrier: StaticBody3D
		if kind in ["wall","low_wall"]:
			barrier = _block(origin+Vector3(1,1.0 if kind == "wall" else 0.125,0),Vector3(0.2,2.0 if kind == "wall" else 0.25,2))
			player.global_position.y = 1.2
		elif kind in ["platform","jump_platform"]:
			barrier = _block(origin+Vector3(0,0.4,0),Vector3(1.5,0.8,1.5))
			player.global_position.y = 2.0 if kind == "jump_platform" else 0.8
		elif kind in ["gap","no_floor"]:
			ai.global_position = Vector3(0,0,13.1)
			ai.home = ai.global_position
			player.global_position = Vector3(0,1.2,16.0)
			if kind == "gap": barrier = _block(Vector3(0,-0.1,16),Vector3(2,0.2,2))
		else: player.global_position.y = 3.0
		await _ticks(2)
		var before: Vector3 = ai.global_position
		ai._start_windup()
		_check(ai.state == ai.State.RECOVERY and ai.attack_count == 0 and not ai.melee_hits() and ai.global_position == before, "Unsafe terrain is not bypassed by jump handling: "+kind)
		if barrier != null: barrier.free()
		player.set_physics_process(true)
	for height in [0.8,2.0]:
		await _fresh_sword(2.0)
		player.set_physics_process(false)
		var platform := _block(origin+Vector3(0,0.4,0),Vector3(1.5,0.8,1.5))
		player.global_position.y=height
		await _ticks(2)
		ai._start_windup()
		_check(ai.state==ai.State.WINDUP and ai._in_place and ai.melee_hits()==(height<=1.4),"ADR-046: reachable step permits in-place planning, actual jump height still limits the hit")
		platform.free()
		player.set_physics_process(true)
	# Keep the user's real WASD dodge regression using the original shared timing.
	await _dodge(4.5,0.45,0.0,true)
	await _fresh(1,Vector3(5,0,0))
	var original_ranged: Resource = ai.settings.attack.snapshot()
	_check(original_ranged.weapon == null and is_equal_approx(original_ranged.hit_height_tolerance,ai.settings.attack.hit_height_tolerance), "Projectile profile does not use the melee override")
	await _windup()
	await _seconds(0.7)
	await _jump()
	await _state(ai.State.ATTACK)
	_check(ai.shots.size() == 1 and ai.shots[0].direction.y > 0.15 and is_equal_approx(ai.shots[0].settings.projectile_speed,5.0), "Mage still releases its original 3D projectile toward actual airborne height")
	ai.clear_shots()
	await _fresh_sword(2.0)
	ai.settings.attack.hit_height_tolerance = 0.8
	ai.settings.attack.target_ground_probe_depth = 3.0
	_check(ResourceSaver.save(ai.settings.attack,"res://.godot/enemy_jump_saved.tres") == OK, "Enemy height and ground probe tuning save")
	_check(FileAccess.get_sha256("res://resources/weapons/one_handed_sword.tres") == sword_hash and is_equal_approx(SharedSword.hit_height_tolerance,0.3), "Authored player weapon and its runtime resource remain unchanged")
	FileAccess.open("res://.godot/enemy_jump_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(jump_metrics,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("ENEMY JUMP ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
