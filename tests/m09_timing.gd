extends "res://tests/m09_enemy_combat.gd"
## Measure elapsed physics time, rather than using display-frame counts as time.
func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	health = player.get_node("HealthComponent")
	sprite = player.get_node("AnimatedSprite3D")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _fresh(0, Vector3(5,0,0))
	ai.set_physics_process(true)
	await _state(ai.State.CHASE)
	var start: Vector3 = ai.global_position
	var frame_start := Engine.get_physics_frames()
	while Engine.get_physics_frames() - frame_start < 30: await _ticks(1)
	var chase_time := float(Engine.get_physics_frames() - frame_start) / Engine.physics_ticks_per_second
	var chase_speed: float = start.distance_to(ai.global_position) / chase_time
	_check(absf(chase_speed - 2.0) < 0.01, "36 chase speed 2 m/s")
	await _state(ai.State.WINDUP)
	frame_start = Engine.get_physics_frames()
	await _state(ai.State.ATTACK)
	var melee_windup := float(Engine.get_physics_frames() - frame_start) / Engine.physics_ticks_per_second
	_check(absf(melee_windup - 0.9) < 0.05, "36 melee telegraph 0.9 seconds")
	await _state(ai.State.RECOVERY)
	frame_start = Engine.get_physics_frames()
	await _state(ai.State.CHASE)
	var recovery := float(Engine.get_physics_frames() - frame_start) / Engine.physics_ticks_per_second
	_check(absf(recovery - 1.2) < 0.05, "36 recovery 1.2 seconds")
	await _fresh(1,Vector3(5,0,0))
	await _windup()
	frame_start = Engine.get_physics_frames()
	await _state(ai.State.ATTACK)
	var ranged_windup := float(Engine.get_physics_frames() - frame_start) / Engine.physics_ticks_per_second
	_check(absf(ranged_windup - 1.0) < 0.05, "36 ranged telegraph 1 second")
	var launch_frame := Engine.get_physics_frames()
	var bolt: CharacterBody3D = ai.shots[0]
	start = bolt.global_position
	frame_start = Engine.get_physics_frames()
	while Engine.get_physics_frames() - frame_start < 20: await _ticks(1)
	var flight_time := float(Engine.get_physics_frames() - frame_start) / Engine.physics_ticks_per_second
	var speed: float = start.distance_to(bolt.global_position) / flight_time
	_check(absf(speed - 5.0) < 0.01, "36 mage projectile speed 5 m/s (ADR-042)")
	# Stay alive long enough to observe the next actual launch.
	while ai.attack_count < 2:
		health.heal(100)
		await _ticks(1)
	var interval := float(Engine.get_physics_frames() - launch_frame) / Engine.physics_ticks_per_second
	_check(interval >= 2.5, "19 minimum interval between actual releases")
	_check(ai.shots.size() == 1 and is_instance_valid(ai.shots[0]), "19 second release prunes freed projectile and creates exactly one")
	var metrics := {"fps_cap":Engine.max_fps,"chase_speed":chase_speed,"melee_windup":melee_windup,"recovery":recovery,"ranged_windup":ranged_windup,"projectile_speed":speed,"release_interval":interval}
	var file := FileAccess.open("res://.godot/m09_timing"+str(Engine.max_fps)+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics))
	print(metrics)
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("M09 TIMING PASS")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
