extends "res://tests/m09_enemy_combat.gd"
## Physics-driven dash profiles, fixed aim, safe movement and competing TargetDash.
const Attack = preload("res://scripts/enemies/enemy_attack_data.gd")
var metrics: Array[Dictionary] = []
var phase_frames: Dictionary = {}
var _last_phase := -1

func _ticks(count: int) -> void:
	for i in range(count):
		await super._ticks(1)
		if not is_instance_valid(ai): continue
		if ai.state != _last_phase:
			_last_phase = ai.state
			phase_frames[ai.state] = Engine.get_physics_frames()

func _dash_fresh(profile: String = "res://resources/enemies/melee_attack.tres", distance: float = 1.7) -> void:
	player.set_physics_process(true)
	await _fresh(0,Vector3(distance,0,0))
	ai.settings.attack = load(profile).duplicate(true)
	ai.home = ai.global_position + Vector3(1,0,0) # Distinguish spawn/home from attack origin.
	phase_frames.clear()
	_last_phase = -1

func _capture_dash(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m09_dash_" + label + "_" + str(Engine.max_fps) + ".png")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	for profile in ["res://resources/enemies/melee_attack.tres","res://tests/fixtures/enemy_fast_attack.tres","res://tests/fixtures/enemy_heavy_attack.tres"]:
		await _dash_fresh(profile)
		await _windup()
		var anchor: Vector3 = ai.attack_anchor
		var end: Vector3 = ai.dash_destination
		var frozen_aim: Vector3 = ai.aimed_position
		var frozen_facing: Vector3 = ai.facing
		var before := health.current_hp
		var w_start := Engine.get_physics_frames()
		_check(anchor == ai.global_position and anchor.distance_to(ai.home) > 0.5, "03/15 independent attack anchor and home")
		_check(ai.telegraph.global_position.distance_to(end + Vector3.UP*0.035) < 0.001, "12 warning sector at future attack point")
		await _ticks(5)
		_check(ai.state == ai.State.WINDUP and ai.global_position == anchor and health.current_hp == before, "01/02 no early movement or damage")
		if metrics.is_empty(): await _capture_dash("windup")
		await _state(ai.State.DASH_APPROACH)
		var windup_time := float(Engine.get_physics_frames()-w_start)/Engine.physics_ticks_per_second
		var dash_start := Engine.get_physics_frames()
		if metrics.is_empty(): await _capture_dash("approach")
		var max_distance := 0.0
		while ai.state == ai.State.DASH_APPROACH:
			_check(health.current_hp == before, "07 no damage during approach")
			_check(ai.global_position.distance_to(player.global_position) >= 0.7, "06 original capsules never overlap")
			max_distance = maxf(max_distance,anchor.distance_to(ai.global_position))
			await _ticks(1)
		var dash_time := float(Engine.get_physics_frames()-dash_start)/Engine.physics_ticks_per_second
		_check(ai.state == ai.State.ATTACK and ai.global_position.distance_to(end) < 0.002, "09 real body reaches fixed destination before attack")
		_check(ai.aimed_position == frozen_aim and ai.facing == frozen_facing, "04 fixed aim, no homing")
		_check(anchor.distance_to(ai.global_position) <= ai.active_attack.dash_max_distance+0.001, "05 capped dash distance")
		if metrics.is_empty(): await _capture_dash("attack")
		await _state(ai.State.DASH_RETURN)
		_check(is_equal_approx(before-health.current_hp,10) and ai.attack_count == 1, "10 one attack, one actual hit")
		if metrics.is_empty(): await _capture_dash("return")
		var r_start := Engine.get_physics_frames()
		var enemy_before: float = ai.health.current_hp
		ai.health.damage(1,player)
		_check(ai.health.current_hp == enemy_before-1, "16 return remains vulnerable")
		await _state(ai.State.RECOVERY)
		var return_time := float(Engine.get_physics_frames()-r_start)/Engine.physics_ticks_per_second
		_check(ai.global_position.distance_to(anchor) < 0.002 and ai.global_position.distance_to(ai.home)>0.5, "14/15 return to attack anchor, not home")
		if metrics.is_empty(): await _capture_dash("recovery")
		var recovery_start := Engine.get_physics_frames()
		await _ticks(10)
		_check(ai.state == ai.State.RECOVERY and ai.attack_count == 1 and health.current_hp == before-10, "18/19 mandatory recovery without repeat damage")
		await _state(ai.State.CHASE)
		var recovery_time := float(Engine.get_physics_frames()-recovery_start)/Engine.physics_ticks_per_second
		_check(absf(windup_time-ai.active_attack.windup_seconds)<0.07 and absf(dash_time-ai.active_attack.dash_seconds)<0.07 and absf(return_time-ai.active_attack.return_seconds)<0.07, "21/22/23/39 data-driven phase timing")
		_check(absf(recovery_time-ai.active_attack.recovery_seconds)<0.07, "23 recovery timing from Resource")
		metrics.append({"profile":profile.get_file(),"windup":windup_time,"dash":dash_time,"return":return_time,"recovery":recovery_time,"distance":anchor.distance_to(end),"return_error":anchor.distance_to(ai.global_position)})
		ai.set_physics_process(false)
	_check(metrics[1].dash < metrics[0].dash and metrics[2].dash > metrics[0].dash and metrics[2].recovery > metrics[0].recovery, "21/22/23 standard/fast/heavy differ using only attack Resource")
	for front in [true,false]:
		await _dash_fresh()
		_press("guard",true)
		await _phase(combat.State.Guard)
		combat.selected_target = null
		combat.target = null
		player.facing_world = Vector3.RIGHT if front else Vector3.LEFT
		await _windup()
		await _state(ai.State.RECOVERY)
		_check(health.current_hp == (95 if front else 90), "32 real dash melee front/back guard="+str(front))
		_press("guard",false)

	await _dash_fresh()
	await _windup()
	var aimed: Vector3 = ai.aimed_position
	var destination: Vector3 = ai.dash_destination
	player.reset_motion(origin + Vector3(0,0,2.5))
	await _state(ai.State.RECOVERY)
	_check(ai.aimed_position == aimed and ai.dash_destination == destination and health.current_hp == 100, "04/11 sidestep after windup misses without retargeting")

	# Unsafe approach and dynamically obstructed return are bounded safe failures.
	await _dash_fresh()
	await _windup()
	var wall := _block(origin + Vector3(1.2,0.125,0),Vector3(0.2,0.25,2))
	await _ticks(3)
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count == 0 and ai.last_result.contains("Unsafe approach"), "08 step blocks dash without remote hit")
	wall.free()
	await _dash_fresh()
	wall = _block(origin+Vector3(1.5,1,0.45002),Vector3(4,2,0.1))
	await _windup()
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count == 1, "08 safe wall-parallel route remains usable with original capsule")
	wall.free()
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	wall = _block(ai.global_position + ai.facing*0.65 + Vector3.UP,Vector3(0.1,2,2))
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count == 0 and health.current_hp == 100, "08 new wall during dash cancels attack")
	wall.free()
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_RETURN)
	wall = _block(ai.attack_anchor+Vector3.UP,Vector3(0.25,2,2))
	await _state(ai.State.RECOVERY)
	_check(ai.last_result.contains("Return blocked") and ai.global_position.distance_to(ai.attack_anchor)>0.01, "17 blocked return stops and exits travel")
	wall.free()
	await _dash_fresh()
	player.set_physics_process(false)
	ai.global_position = Vector3(0,0,13.3)
	ai.home = ai.global_position
	player.global_position = Vector3(0,0,15)
	ai.set_physics_process(true)
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count == 0 and ai.global_position.z <= 13.301, "08 whole footprint rejects cliff route")
	player.set_physics_process(true)

	await _dash_fresh()
	await _windup()
	await _state(ai.State.ATTACK)
	ai.health.damage(100,player)
	await _ticks(15)
	_check(ai.state == ai.State.DEAD and health.current_hp == 100 and not target.alive() and not ai.telegraph.visible, "13 death before hit timing cancels pending damage")
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	health.damage(100,ai)
	await _ticks(10)
	_check(ai.state in [ai.State.RETURN,ai.State.IDLE] and ai.attack_count == 0, "34 player death stops dash and attack")
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_RETURN)
	player.reset_motion(origin + Vector3(-9,0,0))
	await _state(ai.State.IDLE,400)
	_check(ai.global_position.distance_to(ai.home) < 0.04, "20 attack return then independent home return")

	# Player reserves a moving enemy at its actual position; no threshold is relaxed.
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	await _ticks(2)
	_check(combat.request_attack(target), "27 player can attack enemy mid-dash")
	var held: Vector3 = ai.global_position
	var player_anchor: Vector3 = combat.return_anchor
	_check(combat.request_followup(target) and not combat.request_followup(target), "33 one queue, no duplicate reservation")
	for i in range(100):
		if combat.combo_hits == 2: break
		await _ticks(1)
	_check(combat.combo_hits == 2 and ai.global_position.distance_to(held)<0.001, "29/30 player combo holds actual enemy position")
	_check(combat.return_anchor == player_anchor and combat.stock.current == 1, "31/33 independent anchors and exact stock")
	await _wait_idle()
	_check(not combat.last_result.contains("moved"), "30 no target movement invalidation")
	# Force a long movement lease with the existing Guard; it must not freeze AI forever.
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	_check(combat.request_attack(target), "lease fixture attack")
	_press("guard",true)
	await _phase(combat.State.Guard)
	await _state(ai.State.WINDUP)
	_check(ai.last_result.contains("new windup") and ai.attack_anchor == ai.global_position and ai.dash_destination == ai.global_position, "lease timeout warns again at actual position")
	await _state(ai.State.ATTACK)
	await _ticks(5)
	_check(ai.attack_count == 1, "28 held movement does not disable counterattack")
	_press("guard",false)
	await _wait_idle()

	# An already warned in-place counterattack can hit during the player's Approach.
	await _dash_fresh("res://resources/enemies/melee_attack.tres",1.2)
	ai._start_windup(true)
	ai.set_physics_process(true)
	await _state(ai.State.DASH_APPROACH)
	while ai._travel_elapsed < 0.18: await _ticks(1)
	_check(combat.request_attack(target), "28 player approach during enemy counterattack")
	await _state(ai.State.ATTACK)
	await _ticks(4)
	_check(health.current_hp == 90 and combat.state == combat.State.Approach, "28 actual hostile hit while player approaches")
	await _wait_idle()

	# Simultaneous return reservations must resolve without a warp or stuck state.
	await _dash_fresh()
	await _windup()
	await _state(ai.State.DASH_RETURN)
	_check(combat.request_attack(target), "31 attack enemy during its return")
	await _phase(combat.State.Attack)
	_press("move_down",true)
	await _phase(combat.State.Return)
	await _wait_idle()
	_press("move_down",false)
	for i in range(100):
		if ai.state not in [ai.State.DASH_APPROACH,ai.State.DASH_RETURN]: break
		await _ticks(1)
	_check(not combat.is_busy() and ai.state not in [ai.State.DASH_APPROACH,ai.State.DASH_RETURN], "31 overlapping returns resolve")

	await _dash_fresh()
	var original_damage: float = ai.settings.attack.damage
	ai.active_attack.damage = 999
	_check(ai.settings.attack.damage == original_damage, "26 active snapshot never mutates shared data")
	var other: CharacterBody3D = EnemyScene.instantiate()
	other.settings = ai.settings
	other.player = player
	other.position = Vector3(8,0,8)
	main.add_child(other)
	other.set_physics_process(false)
	_check(other.active_attack != ai.active_attack and other.attack_count == 0 and other.active_attack.damage == original_damage, "26 two enemies sharing Resource have independent snapshots and state")
	other.free()
	var selector = main.get_node("PracticeSelector")
	ai.set_physics_process(true)
	await _state(ai.State.DASH_APPROACH)
	ai.free()
	selector.select_mode(1)
	await _ticks(3)
	selector.select_mode(2)
	await _ticks(3)
	_check(selector.active_enemy.settings.attack.kind == Attack.Kind.PROJECTILE and not combat.is_busy(), "24/34 mode reset preserves ranged attack kind")
	selector.select_mode(0)
	var file := FileAccess.open("res://.godot/m09_dash_metrics_"+str(Engine.max_fps)+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics))
	print(metrics)
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("M09 DASH PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
