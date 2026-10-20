extends "res://tests/m06_target_dash.gd"
## Measure the projected geometric origin separately from the ellipse bounds.
func _measure(label: String) -> void:
	var ring: MeshInstance3D = combat._ring
	var camera: Camera3D = main.get_node("CameraRig").camera
	var foot := player.global_position
	var center := ring.global_position
	var projected := camera.unproject_position(center)
	var lower := Vector2(INF, INF)
	var upper := Vector2(-INF, -INF)
	for i in range(720):
		var angle := TAU * i / 720.0
		var point: Vector3 = center + Vector3(cos(angle), 0, sin(angle)) * combat.equipped_weapon.attack_range
		var screen := camera.unproject_position(point)
		lower = lower.min(screen)
		upper = upper.max(screen)
	print(label, " foot=", foot, " ring=", center, " world_delta=", center-foot,
		" foot_screen=", camera.unproject_position(foot), " origin_screen=", projected,
		" origin_delta_px=", projected-camera.unproject_position(foot),
		" ellipse_bounds_delta_px=", (lower+upper)*0.5-projected)
	_check((center-foot-Vector3.UP*0.04).length() < 0.0001, "Ring remains centered over feet " + label)
	_check(projected.distance_to(camera.unproject_position(foot)) < 3, "Only small height projection offset " + label)
	_check(combat._range_guides.global_position.distance_to(center) < 0.0001, "Guides share the real center")
	var vertices: PackedVector3Array = combat._range_guides.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		_check(is_equal_approx(vertex.length(), combat.equipped_weapon.attack_range), "Guide ends on unchanged radius")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	# Keep the user's saved enemy layout intact; arrange only this test instance.
	enemy = main.get_node("TrainingEnemy")
	enemy.position = Vector3(-3,0,-2)
	target = enemy.get_node("Targetable")
	await _ticks(20)
	_check(not combat._ring.visible and not combat._range_guides.is_visible_in_tree(), "Default gameplay hides range and guides")
	var available_before: Array[Node3D] = combat.valid_candidates()
	combat.show_debug_attack_range = true
	await _ticks(2)
	_check(combat._ring.visible and combat._range_guides.is_visible_in_tree(), "Debug toggle shows both")
	_check(combat.valid_candidates() == available_before, "Display does not change candidates")
	var rig: Node3D = main.get_node("CameraRig")
	for angle in [0,90,180,270]:
		rig.rotation.y = deg_to_rad(angle)
		await _ticks(20)
		_measure("yaw=" + str(angle))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/m07_range_%d.png" % angle)
	Input.action_press("move_right")
	await _ticks(15)
	Input.action_release("move_right")
	await _ticks(10)
	_measure("after movement")
	for action in ["camera_left", "camera_right"]:
		var previous_yaw: float = rig.rotation.y
		Input.action_press(action)
		await _ticks(15)
		Input.action_release(action)
		_check(absf(rig.rotation.y-previous_yaw) > 0.1, "Camera action rotates")
		_measure(action)
	rig.rotation.y = 0
	await _settle(Vector3(-6,0,0))
	_check(combat.request_attack(target), "Attack accepted")
	var next_targets := [main.get_node("TrainingEnemySecond/Targetable"), main.get_node("TrainingEnemyThird/Targetable")]
	var reserved_stage := 0
	combat.hit.connect(func(_target: Node): hits += 1)
	for i in range(300):
		await _ticks(1)
		if not combat.is_busy(): break
		_check(not combat._ring.visible and not combat._range_guides.is_visible_in_tree(), "Range and guides hidden throughout combo")
		_check(combat._ring.global_position.distance_to(player.global_position+Vector3.UP*0.04) < 0.0001, "Center follows during combo")
		if combat.state == combat.State.Attack and combat.combo_hits > reserved_stage and combat.combo_hits < 3:
			_check(combat.request_followup(next_targets[combat.combo_hits-1],true), "Next target accepted")
			reserved_stage = combat.combo_hits
	_check(not combat.is_busy() and hits == 3, "Three-enemy combo returns normally")
	await _ticks(2)
	_measure("after return")
	_check(combat._ring.visible, "Range restored after return")
	if failures.is_empty(): print("PASS M07 range display: world center, projection, orbit, movement, return")
	for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

