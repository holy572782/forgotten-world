extends "res://tests/m06_target_dash.gd"
var rig: Node3D
var b: Node3D
var c: Node3D
var hit_targets: Array[Node] = []
var recorded_anchor := Vector3.ZERO
var held_focus := Vector3.ZERO
var check_lock := false

func _tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _ticks(count: int) -> void:
	for i in range(count):
		await super._ticks(1)
		if check_lock and combat.is_busy():
			_check(rig.follow_locked, "Lock through approach/strike/stance/return")
			_check(rig.global_position.distance_to(held_focus) < 0.0001, "Follow origin never follows player")
			_check(combat.return_anchor.distance_to(recorded_anchor) < 0.0001, "Original return anchor")

func _phase(next: int, combo: int = -1) -> void:
	for i in range(180):
		await _ticks(1)
		if combat.state == next and (combo < 0 or combat.combo_hits == combo): return
	_check(false, "Phase timeout " + str(next) + "/" + str(combo))

func _face(candidate: Node3D) -> void:
	player.facing_world = (candidate.global_position - player.global_position).normalized()

func _start() -> bool:
	await _settle(recorded_anchor)
	for candidate in [target,b,c]: candidate.health.heal(40)
	await _ticks(2)
	held_focus = rig.global_position
	check_lock = true
	return combat.request_attack(target)

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	combat.show_debug_attack_range = "--debug-range" in OS.get_cmdline_user_args()
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	b = main.get_node("TrainingEnemySecond/Targetable")
	c = main.get_node("TrainingEnemyThird/Targetable")
	rig = main.get_node("CameraRig")
	combat.hit.connect(func(t: Node):
		hit_targets.append(t)
		_check(sprite.frame == combat._active_motion.hit_frame, "Central frame damage"))
	await _ticks(20)
	recorded_anchor = player.global_position
	# Automatic aiming follows player world facing, not orbit yaw.
	combat.selected_target = null
	_face(target)
	await _ticks(2)
	_check(combat.selected_target == target, "Front target selected")
	# ADR-012: B is nearer inside the forward cone; keep it through angle jitter.
	combat.selected_target = b
	var boundary := ((b.global_position-player.global_position).normalized()+(c.global_position-player.global_position).normalized()).normalized()
	for i in range(20):
		player.facing_world = boundary.rotated(Vector3.UP, deg_to_rad(1 if i % 2 else -1))
		await _ticks(1)
		_check(combat.selected_target == b, "Distance-priority selection prevents boundary flicker")
	_face(b)
	await _ticks(15)
	_check(combat.selected_target == b, "Clear facing change selects new target")
	_tap("lock_on")
	await _ticks(2)
	var manual = combat.selected_target
	var manual_facing: Vector3 = player.facing_world
	for i in range(20):
		player.facing_world = manual_facing.rotated(Vector3.UP, deg_to_rad(2 if i % 2 else -2))
		await _ticks(1)
		_check(combat.selected_target == manual, "Manual lock survives small jitter")
	_face(target)
	await _ticks(15)
	_check(combat.selected_target == target, "Clear turn releases manual lock")
	var picked = combat.selected_target
	Input.action_press("camera_right")
	await _ticks(6)
	Input.action_release("camera_right")
	_check(combat.selected_target == picked, "Orbit alone does not change aim")
	rig.rotation.y = 0
	await _ticks(3)
	# Reject fixed-radius growth even when an enemy is near the current strike.
	_check(await _start(), "Start chain")
	await _phase(combat.State.Attack,1)
	var original_eye: Vector3 = rig.camera.global_position
	_check(player.global_position.distance_to(recorded_anchor) > 1 and rig.global_position == held_focus, "Approach without camera translation")
	var camera: Camera3D = rig.camera
	_click(camera.unproject_position(b.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	_check(combat.queued_attack_target == b and combat.target == target and combat.stock.current == 2, "B reserved without retargeting active A")
	_click(camera.unproject_position(c.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	_check(combat.queued_attack_target == c and combat.queued and combat.stock.current == 2, "Replace queued B with C without spending")
	# L changes both selected and existing reservation, never starts a strike.
	var before_combo: int = combat.combo_hits
	_tap("lock_on")
	await _ticks(1)
	_check(combat.queued_attack_target == combat.selected_target and combat.combo_hits == before_combo and combat.stock.current == 2, "L changes reservation only")
	_click(camera.unproject_position(b.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	_check(combat.queued_attack_target == b, "Restore B queue")
	await _phase(combat.State.Attack,2)
	_check(combat.target == b and hit_targets == [target], "Only completed A damaged before B hit")
	_click(camera.unproject_position(c.global_position + Vector3.UP * 0.75),MOUSE_BUTTON_LEFT)
	_check(combat.queued_attack_target == c and combat.stock.current == 1, "C queued")
	await _ticks(1)
	_check(c.selected and combat.selected_target == c, "Marker matches reserved C")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m07_chain_second.png")
	Input.action_press("camera_right")
	await _ticks(4)
	Input.action_release("camera_right")
	_check(rig.camera.global_position.distance_to(original_eye) > 0.1 and rig.global_position == held_focus, "Orbit and safety remain active while locked")
	await _wait_idle()
	_check(hit_targets == [target,b,c], "A B C exactly once each")
	for candidate in [target,b,c]: _check(candidate.health.current_hp == 30, "One 10 damage hit per enemy")
	_check(combat.stock.current == 0 and combat.combo_hits == 3 and not combat.queued, "Independent combo/stock and queue bounds")
	_check(not rig.follow_locked and player.global_position.distance_to(recorded_anchor) < 0.03, "Unlock on safe return")
	_check(rig.settings.occlusion_mode == 1 and is_equal_approx(rig.camera.fov,75.0) and is_equal_approx(rig.arm.spring_length,10.0), "B mode and distance/FOV preserved")
	_check(rig.global_position.distance_to(held_focus) < 0.03, "Return unlock has no snap")
	check_lock = false
	Input.action_press("move_right")
	var before_position: Vector3 = player.global_position
	var before_focus: Vector3 = rig.global_position
	await _ticks(10)
	Input.action_release("move_right")
	_check(player.global_position.distance_to(before_position) > 0.1 and rig.global_position.distance_to(before_focus) > 0.01, "Movement and follow resume")
	Input.action_press("jump")
	await _ticks(5)
	Input.action_release("jump")
	_check(player.global_position.y > 0.1, "Jump resumes")
	await _ticks(70)
	rig.rotation.y = 0
	# L with no queue only changes aim; no automatic follow-up.
	_check(await _start(), "Start L-only test")
	await _phase(combat.State.Attack,1)
	_tap("lock_on")
	await _ticks(1)
	_check(not combat.queued and combat.combo_hits == 1, "L alone never attacks")
	await _wait_idle()
	_check(combat.combo_hits == 1, "L-only cycle ends after one hit")
	# Invalid next targets leave the paid current strike intact and cancel before spending.
	for mode in ["wall","dead","removed","range","offscreen"]:
		_check(await _start(), "Start invalid queue " + mode)
		await _phase(combat.State.Attack,1)
		_check(combat.request_followup(b,true), "Reserve B before invalidation")
		var obstacle: StaticBody3D
		var saved: Vector3 = b.get_parent().global_position
		if mode == "wall":
			obstacle = _block(combat.attack_position(b).lerp(player.global_position,0.5)+Vector3.UP,Vector3(0.3,2,0.3))
		elif mode == "dead": b.health.damage(1000)
		elif mode == "removed": b.get_parent().queue_free()
		elif mode == "range": b.get_parent().global_position = recorded_anchor + Vector3(-6,0,0)
		elif mode == "offscreen":
			rig.camera.fov = 15
		await _wait_idle()
		_check(not combat.queued and combat.queued_attack_target == null and combat.stock.current == 2, "Invalid next cancels without spending " + mode)
		_check(not rig.follow_locked, "Invalid cycle unlocks " + mode)
		if obstacle != null: obstacle.free()
		if mode == "removed":
			var replacement = load("res://scenes/enemies/training_enemy.tscn").instantiate()
			main.add_child(replacement)
			b = replacement.get_node("Targetable")
		b.get_parent().global_position = saved
		rig.camera.fov = 75
		await _ticks(3)
	# Origin radius stays fixed even if the player has approached the next enemy.
	_check(await _start(), "Range rejection start")
	await _phase(combat.State.Attack,1)
	var saved_b: Vector3 = b.get_parent().global_position
	b.get_parent().global_position = recorded_anchor + Vector3(5.1,0,0)
	await _ticks(2)
	_check(not combat.can_combo_select(b) and not combat.request_followup(b,true), "Origin radius rejects range growth")
	b.get_parent().global_position = saved_b
	await _wait_idle()
	# Aborted return: unlock interpolates from the held pivot instead of snapping to player.
	_check(await _start(), "Blocked return start")
	await _phase(combat.State.Attack,1)
	var return_wall := _block(recorded_anchor+Vector3.UP,Vector3(1,2,1))
	await _wait_idle()
	_check(combat.return_error > 0.5 and not rig.follow_locked, "Blocked return releases camera")
	var difference := rig.global_position.distance_to(player.global_position + rig.settings.target_offset)
	await _ticks(1)
	var next_difference := rig.global_position.distance_to(player.global_position + rig.settings.target_offset)
	_check(next_difference < difference and next_difference > 0.01, "Blocked return smoothly resumes follow")
	return_wall.free()
	check_lock = false
	# The lock pauses only following. Existing B fade, shadow proxy and eye safety
	# still run with exactly the same player-based visibility rays.
	await _settle(recorded_anchor)
	rig.hold_follow()
	var pivot: Vector3 = rig.global_position
	var blocker := _block(rig.camera.global_position.lerp(player.global_position+Vector3.UP*0.8,0.55),Vector3.ONE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	blocker.add_child(mesh)
	await _ticks(20)
	_check(rig.fader.entries.has(mesh.get_instance_id()), "Existing fade continues during follow lock")
	if rig.fader.entries.has(mesh.get_instance_id()):
		var entry: Dictionary = rig.fader.entries[mesh.get_instance_id()]
		_check(entry.opacity < 1.0 and is_instance_valid(entry.shadow_proxy), "Fade retains shadow proxy while locked")
	var old_eye: Vector3 = rig.camera.global_position
	var eye_block := _block(old_eye,Vector3.ONE*0.5)
	await _ticks(10)
	_check(not rig.safety_failed and rig.camera.global_position.distance_to(old_eye) > 0.1, "Eye collision correction remains active")
	_check(rig.global_position.distance_to(pivot) < 0.0001, "Safety does not move the locked pivot")
	var eye_before_toggle: Vector3 = rig.camera.global_position
	rig.release_follow()
	rig.hold_follow()
	_check(rig.camera.global_position == eye_before_toggle and rig.global_position == pivot, "Lock toggle does not teleport camera")
	eye_block.free()
	blocker.free()
	rig.release_follow()
	await _ticks(30)
	# A next destination can be inside the ORIGINAL radius and still cross a ledge.
	enemy.global_position = Vector3(10,0,0)
	b.get_parent().global_position = Vector3(15.5,0,0)
	c.get_parent().global_position = Vector3(9,0,-3)
	await _settle(Vector3(12,0,0))
	target.health.heal(40)
	_check(combat.request_attack(target), "Edge fixture first strike valid")
	await _phase(combat.State.Attack,1)
	_check(b.global_position.distance_to(combat.return_anchor) < 5, "Ledge target within origin radius")
	_check(not combat.Path.clear(player,combat.attack_position(b),combat.settings,player.global_position), "Next route crosses missing floor")
	_check(not combat.can_combo_select(b) and not combat.request_followup(b,true), "Ledge next attack rejected")
	await _wait_idle()
	if failures.is_empty(): print("PASS M07 chain: facing aim, manual release, pivot lock, orbit, ABC, replacement, invalid next, return")
	for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
