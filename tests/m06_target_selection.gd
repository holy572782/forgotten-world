extends "res://tests/m06_target_dash.gd"
## Selection volumes are independent of the ground-level approach/hit point.
func _run() -> void:
	root.size = Vector2i(1152, 720)
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	combat.hit.connect(func(selected: Node):
		hits += 1
		_check(selected == target, "Hit resolves to selected attack point"))
	await _ticks(20)
	var origin := player.global_position
	var camera: Camera3D = main.get_node("CameraRig").camera
	for height in [0.25, 0.75, 1.25]:
		var screen := camera.unproject_position(enemy.global_position + Vector3.UP * height)
		_check(combat.pick_target(screen) == target, "Body lower/middle/upper selects " + str(height))
	_check(combat.pick_target(camera.unproject_position(target.marker.global_position)) == target, "Gold marker retained")
	_click(camera.unproject_position(enemy.global_position + Vector3.UP * 0.75))
	await _ticks(3)
	_check(combat.state == combat.State.Approach, "Body right click starts approach")
	await _wait_idle()
	_check(hits == 1 and target.health.current_hp == 30.0, "Body click deals one hit")
	_check(player.global_position.distance_to(origin) < 0.03, "Body click returns to origin")
	await _ticks(3)
	# A blocker in the camera ray is rejected even when the player-to-enemy route is clear.
	var blocker := _block(camera.global_position.lerp(enemy.global_position + Vector3.UP * 0.75, 0.5), Vector3.ONE)
	await _ticks(3)
	_check(combat.pick_target(camera.unproject_position(enemy.global_position + Vector3.UP * 0.75)) == null, "No selection through foreground wall")
	blocker.queue_free()
	await _settle(origin - Vector3(6, 0, 0))
	_check(combat.pick_target(camera.unproject_position(enemy.global_position + Vector3.UP * 0.75)) == null, "Out-of-range body rejected")
	await _settle(origin)
	# Boss-style fixture: whole-body picking disabled, two independent Targetables share HP.
	var body_target: Node3D = target
	body_target.click_collider_paths.clear()
	var part := Area3D.new()
	part.name = "AttackPart"
	part.collision_layer = 8
	part.collision_mask = 0
	part.monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	part.add_child(shape)
	enemy.add_child(part)
	part.position = Vector3(-0.9, 0.75, 0)
	target = body_target.duplicate()
	target.name = "PartTarget"
	target.position = Vector3(-0.9, 0, 0)
	var part_paths: Array[NodePath] = [NodePath("../AttackPart")]
	target.click_collider_paths = part_paths
	enemy.add_child(target)
	await _ticks(4)
	_check(combat.pick_target(camera.unproject_position(enemy.global_position + Vector3.UP * 0.75)) == null, "Unassigned boss body not selectable")
	_check(combat.pick_target(camera.unproject_position(part.global_position)) == target, "Part collider selects its own attack point")
	_check(combat.pick_target(camera.unproject_position(body_target.marker.global_position)) == body_target, "Other point marker remains distinct")
	_click(camera.unproject_position(part.global_position))
	await _ticks(3)
	_check(combat.target == target and combat.state == combat.State.Approach, "Part right click selects intended point")
	await _wait_idle()
	_check(hits == 2 and target.health.current_hp == 20.0, "Part shares enemy HP and deals one hit")
	_check(player.global_position.distance_to(origin) < 0.03, "Part attack returns")
	target.health.damage(100.0)
	await _ticks(3)
	_check(combat.pick_target(camera.unproject_position(part.global_position)) == null, "Dead part rejected")
	if failures.is_empty(): print("PASS M06 selection: whole body, markers, assigned parts, shared HP, occlusion, range and return")
	else:
		for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
