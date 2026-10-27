extends "res://tests/enemy_sword_combat.gd"
const Controller = preload("res://scripts/player/player_controller.gd")
var cue_count := 0
var measurements: Array[Dictionary] = []

class ReturnTrace extends Node:
	var actor: CharacterBody3D
	var previous_state := -1
	var last_recovery_position := Vector3.INF
	func _ready() -> void: process_physics_priority = 100
	func _physics_process(_delta: float) -> void:
		if actor.state == actor.State.RECOVERY and previous_state != actor.State.RECOVERY:
			last_recovery_position = actor.global_position
		previous_state = actor.state

func _fresh_sword(distance: float) -> void:
	await super._fresh_sword(distance)
	var trace := ReturnTrace.new()
	trace.name = "ReturnTrace"
	trace.actor = ai
	ai.add_child(trace)

func _cue() -> void:
	cue_count += 1

func _seconds(duration: float) -> void:
	var start := Engine.get_physics_frames()
	while float(Engine.get_physics_frames()-start)/60.0 < duration: await _ticks(1)

func _locked() -> void:
	for tick in range(150):
		if ai.aim_locked: return
		await _ticks(1)
	_check(false, "Late aim eventually commits")

func _dodge(distance: float, window: float, yaw: float, lateral: bool) -> Dictionary:
	await _fresh_sword(distance)
	main.get_node("CameraRig").rotation.y = deg_to_rad(yaw)
	main.get_node("CameraRig").snap_to_target()
	ai.settings.aim_commit_minimum_seconds = window
	await _windup()
	await _locked()
	var locked_tick := Engine.get_physics_frames()
	var locked_position: Vector3 = ai.aimed_position
	var destination: Vector3 = ai.dash_destination
	var direction: Vector3 = ai.facing
	var wanted := direction.cross(Vector3.UP) if lateral else direction
	var best := ""
	var score := -INF
	var actions := ["move_left","move_right","move_up","move_down"]
	var inputs := [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	for index in range(4):
		var dot: float = Controller.input_to_world(inputs[index], player.movement_camera.global_basis).dot(wanted)
		if dot > score:
			score = dot
			best = actions[index]
	_press(best,true)
	var before: Vector3 = player.global_position
	var hit_tick := -1
	for tick in range(180):
		await _ticks(1)
		_check(ai.aimed_position == locked_position and ai.dash_destination == destination and ai.facing == direction, "Committed attack never follows moving player")
		if ai.attack_count > 0:
			hit_tick = Engine.get_physics_frames()
			break
	_press(best,false)
	var result := {"distance":distance,"minimum":window,"yaw":yaw,"lateral":lateral,"hit":health.current_hp < 100,"seconds":float(hit_tick-locked_tick)/60.0,"movement":before.distance_to(player.global_position),"action":best}
	if window >= 0.45:
		_check(hit_tick > 0 and result.seconds >= window - 0.001, "Configured minimum aim-lock-to-hit time is respected")
		_check(not result.hit and result.movement > 0.5, "Actual WASD from rest evades committed sword with unchanged reach")
	await _state(ai.State.RECOVERY)
	_check(ai.get_node("ReturnTrace").last_recovery_position.distance_to(ai.attack_anchor) < 0.001, "Evaded attack still returns to its own anchor")
	measurements.append(result)
	return result

func _movement_fixture() -> void:
	await _fresh_sword(3.5)
	ai.attack_count = 1
	ai.active_attack.recovery_seconds = 12.0
	ai._set_state(ai.State.RECOVERY)
	ai.set_physics_process(true)

func _reload_tactics() -> void:
	var resource: Resource = load("res://.godot/enemy_tactics_saved.tres")
	_check(resource.track_windup_target and is_equal_approx(resource.aim_commit_minimum_seconds,0.55), "Aim settings persist")
	_check(resource.combat_movement_enabled and is_equal_approx(resource.pursuit_speed,1.4) and is_equal_approx(resource.pursuit_step_distance,0.6) and is_equal_approx(resource.preferred_attack_distance,3.2) and is_equal_approx(resource.combat_direction_interval,0.9) and is_equal_approx(resource.combat_wait_seconds,0.3) and resource.combat_strafe_weight == 3, "Movement profile persists")
	for failure in failures: push_error(failure)
	print("ENEMY TACTICS RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_tactics()
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	await _fresh_sword(4.5)
	cue_count = 0
	ai.get_node("AttackWarning").warning_sound_presented.connect(_cue)
	await _windup()
	_check(not ai.aim_locked, "Warning entry does not lock attack position")
	var anchor: Vector3 = ai.attack_anchor
	var first_target: Vector3 = ai.aimed_position
	await _seconds(0.35)
	player.reset_motion(origin+Vector3(0,0,0.7))
	await _ticks(2)
	_check(not ai.aim_locked and ai.aimed_position.distance_to(player.global_position) < 0.001 and ai.aimed_position != first_target and ai.global_position == anchor, "Warning tracks current player without moving enemy")
	_check(String(ai.get_node("AnimatedSprite3D").animation).begins_with("warning_") and ai.get_node("AnimatedSprite3D").frame == 0, "Tracking retains fixed warning pose")
	await _locked()
	_check(ai.elapsed >= ai.active_attack.windup_seconds and cue_count == 1, "Aim locks at warning end; Fire1 remains one cue")
	await _finish_strike()
	_check(ai.attack_count == 1 and health.current_hp == 90 and ai.get_node("ReturnTrace").last_recovery_position.distance_to(anchor) < 0.001, "Tracked target is hit once if player does not evade and enemy returns")
	# Measure the user's initial 0.25s suggestion before choosing a reach-aware default.
	await _dodge(4.5,0.25,0.0,false)
	for yaw in [0.0,90.0,180.0,270.0]:
		await _dodge(1.2,0.45,yaw,false)
		await _dodge(4.5,0.45,yaw,true)
	await _movement_fixture()
	var modes: Dictionary = {}
	var last_mode := ""
	var previous_tick := Engine.get_physics_frames()
	var last_position: Vector3 = ai.global_position
	var changes: Array[Dictionary] = []
	for tick in range(270):
		await _ticks(1)
		if ai.combat_move_mode != last_mode:
			changes.append({"mode":ai.combat_move_mode,"tick":Engine.get_physics_frames()})
			last_mode = ai.combat_move_mode
		modes[ai.combat_move_mode] = true
		_check(ai.global_position.distance_to(last_position) <= 2.0*float(Engine.get_physics_frames()-previous_tick)/60.0+0.0002, "Combat walk never teleports or exceeds configured speed")
		_check(ai.global_position.distance_to(player.global_position) >= 1.099 and ai.global_position.distance_to(ai.home) <= ai.settings.leash_radius, "Combat movement keeps player clearance and leash")
		ai.get_node("AnimatedSprite3D")._process(0.0) # Sample presentation after this physics tick.
		if ai.velocity.length() > 0.01: _check(String(ai.get_node("AnimatedSprite3D").animation).begins_with("walk_"), "Actual combat movement displays Walk")
		last_position = ai.global_position
		previous_tick = Engine.get_physics_frames()
	for mode in ["left","right","approach","retreat","wait"]: _check(modes.has(mode), "Weighted cycle includes " + mode)
	FileAccess.open("res://.godot/enemy_tactics_moves.json",FileAccess.WRITE).store_string(JSON.stringify(changes,"  "))
	for index in range(1,changes.size()):
		var minimum := 0.2 if changes[index-1].mode == "wait" else 0.7
		_check(float(changes[index].tick-changes[index-1].tick)/60.0 >= minimum-0.04, "Direction changes wait for their configured interval")
	ai.active_attack.recovery_seconds = ai.elapsed + 0.1
	await _state(ai.State.WINDUP)
	var new_anchor: Vector3 = ai.attack_anchor
	var at_warning: Vector3 = ai.global_position
	await _seconds(0.25)
	_check(ai.global_position == at_warning and ai.combat_move_mode.is_empty(), "Next warning stops combat walk immediately")
	await _finish_strike()
	_check(ai.attack_anchor == new_anchor and ai.get_node("ReturnTrace").last_recovery_position.distance_to(new_anchor) < 0.001, "Following attack returns to newly chosen position")
	# Safety fixtures hold one chosen direction; blocked goals are not retried each tick.
	await _movement_fixture()
	ai.set_physics_process(false)
	ai._choose_combat_move()
	var wall := _block(ai.global_position.direction_to(ai._combat_move_goal)*0.5+ai.global_position+Vector3.UP,Vector3(2,2,0.15))
	await _ticks(3)
	var stopped: Vector3 = ai.global_position
	for tick in range(20): ai._post_attack_step(1.0/60.0)
	_check(ai.global_position == stopped and ai._combat_move_blocked and ai.velocity == Vector3.ZERO, "Wall cancels the current step and waits without thrashing")
	wall.free()
	await _movement_fixture()
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.global_position = Vector3(0,0,13.1)
	ai.home = ai.global_position
	player.global_position = Vector3(3.5,0,13.1)
	ai._choose_combat_move()
	stopped = ai.global_position
	for tick in range(20): ai._post_attack_step(1.0/60.0)
	_check(ai.global_position == stopped and ai._combat_move_blocked, "Unsupported cliff goal is rejected before walking")
	player.set_physics_process(true)
	await _movement_fixture()
	ai.settings.pursuit_speed = 0.8
	ai.settings.pursuit_step_distance = 0.4
	ai.settings.combat_direction_interval = 0.9
	ai._stop_combat_move()
	stopped = ai.global_position
	var start_tick := Engine.get_physics_frames()
	await _seconds(0.25)
	var actual_time := float(Engine.get_physics_frames()-start_tick)/60.0
	_check(absf(stopped.distance_to(ai.global_position)/actual_time-0.8) < 0.04 and absf(stopped.distance_to(ai._combat_move_goal)-0.4) < 0.001, "Existing speed and step settings independently control combat walk")
	for mode in ["approach","retreat","wait"]:
		await _movement_fixture()
		ai.settings.combat_strafe_weight = 0
		ai.settings.combat_approach_weight = 1 if mode == "approach" else 0
		ai.settings.combat_retreat_weight = 1 if mode == "retreat" else 0
		ai.settings.combat_wait_weight = 1 if mode == "wait" else 0
		if mode == "approach": player.reset_motion(origin-Vector3(0.5,0,0))
		var distance_before := ai.global_position.distance_to(player.global_position)
		await _seconds(0.25)
		var distance_after := ai.global_position.distance_to(player.global_position)
		_check(ai.combat_move_mode == mode and ((distance_after < distance_before) if mode == "approach" else ((distance_after > distance_before) if mode == "retreat" else is_equal_approx(distance_before,distance_after))), "Per-enemy weights select actual " + mode)
	await _movement_fixture()
	ai.settings.combat_movement_enabled = false
	stopped = ai.global_position
	await _seconds(0.3)
	_check(ai.global_position == stopped, "Disabling new movement restores existing in-range pursuit stop")
	await _movement_fixture()
	player.reset_motion(origin-Vector3(3,0,0))
	var initial_distance := ai.global_position.distance_to(player.global_position)
	await _seconds(0.3)
	_check(ai.global_position.distance_to(player.global_position) < initial_distance and ai.combat_move_mode.is_empty(), "Out-of-range actor uses safe approach rather than orbiting farther away")
	for tick in range(150):
		if ai.global_position.distance_to(player.global_position) <= ai.preferred_distance() + 0.01: break
		_check(ai.combat_move_mode.is_empty(), "Pursuit remains latched until reaching preferred distance, without boundary oscillation")
		await _ticks(1)
	_check(ai.global_position.distance_to(player.global_position) <= ai.preferred_distance()+0.01, "Out-of-range pursuit completes before local movement resumes")
	await _movement_fixture()
	ai.health.damage(100,player)
	stopped = ai.global_position
	await _seconds(0.3)
	_check(not is_instance_valid(ai) or (ai.global_position == stopped and ai.combat_move_mode.is_empty()), "Death stops all combat movement and may finish visual cleanup")
	await _fresh(1,Vector3(3.5,0,0))
	_check(not ai.settings.track_windup_target and not ai.settings.combat_movement_enabled, "Ranged profile remains unchanged")
	ai.settings = ai.settings.duplicate()
	ai.settings.combat_movement_enabled = true
	ai.settings.track_windup_target = true
	ai._start_windup()
	var ranged_aim: Vector3 = ai.aimed_position
	player.reset_motion(origin-Vector3(0.2,0,0))
	ai.elapsed = 0.3
	ai._windup_step(1.0/60.0)
	_check(ai.aim_locked and ai.aimed_position == ranged_aim and not ai._can_pursue(), "Melee options never change ranged aiming or movement")
	for node in get_nodes_in_group("combat_targets"):
		_check(node.get_node("Marker/Mesh").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Each target marker casts no shadow")
	await _fresh_sword(3.5)
	var marker: MeshInstance3D = ai.targetable.get_node("Marker/Mesh")
	ai.targetable.set_available(true,true)
	var filled: Mesh = marker.mesh
	ai.targetable.set_available(true,false)
	_check(marker.visible and marker.mesh != filled and ai.targetable.marker.collision_layer == 8, "Marker selected/candidate display and click collider remain unchanged")
	_check(ai.get_node("AnimatedSprite3D/Shadow").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Enemy character shadow remains enabled")
	ai.settings.aim_commit_minimum_seconds = 0.55
	ai.settings.pursuit_speed = 1.4
	ai.settings.pursuit_step_distance = 0.6
	ai.settings.preferred_attack_distance = 3.2
	ai.settings.combat_direction_interval = 0.9
	ai.settings.combat_wait_seconds = 0.3
	ai.settings.combat_strafe_weight = 3
	_check(ResourceSaver.save(ai.settings,"res://.godot/enemy_tactics_saved.tres") == OK, "Tactics tuning saves as Resource")
	FileAccess.open("res://.godot/enemy_tactics_measurements.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("ENEMY TACTICS ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
