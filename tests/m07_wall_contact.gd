extends "res://tests/m06_target_dash.gd"
## Reproduce contact with actual locomotion, then use normal combat callbacks.
var wall: StaticBody3D
var rig: Node3D
var other: Node3D
var third: Node3D
var anchor := Vector3.ZERO
var held_focus := Vector3.ZERO
var monitor := false
var hit_targets: Array[Node] = []

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

func _gap() -> float:
	var local := wall.to_local(player.global_position)
	return -0.25-local.z-player.get_node("CollisionShape3D").shape.radius

func _ticks(count: int) -> void:
	for i in range(count):
		await super._ticks(1)
		if monitor and combat.is_busy():
			_check(_gap() > -0.0001, "No worsening penetration during approach, combo or return")
			_check(combat.return_anchor.distance_to(anchor) < 0.00001, "Original return anchor retained")
			_check(rig.follow_locked and rig.global_position.distance_to(held_focus) < 0.00001, "Camera fixed through contact combat")

func _contact(angle: float = 0.0) -> void:
	monitor = false
	wall.rotation.y = angle
	rig.rotation.y = angle
	var center := Vector3(wall.global_position.x,0,wall.global_position.z)
	await _settle(center-wall.global_basis.z)
	Input.action_press("move_down")
	await _ticks(45)
	Input.action_release("move_down")
	await _ticks(2)
	anchor = player.global_position
	_check(absf(_gap()) < 0.001, "Real locomotion reached wall contact")
	_check(player.is_on_floor(), "Contact is grounded")
	for candidate in [target,other,third]: candidate.health.heal(40)
	print("CONTACT yaw=",rad_to_deg(angle)," feet=",anchor," capsule_wall_gap_m=",_gap()," safe_margin=",player.safe_margin)

func _diagnose() -> void:
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = collider.shape
	q.transform = player.global_transform*collider.transform
	q.transform.origin.y += 0.01
	q.collision_mask = 5
	q.exclude = [player.get_rid()]
	q.margin = 0.001
	var space := player.get_world_3d().direct_space_state
	var overlaps := space.intersect_shape(q,4)
	q.motion = combat.attack_position(target)-player.global_position
	var legacy_sweep := space.cast_motion(q)
	q.margin = 0.0
	var zero_margin_overlaps := space.intersect_shape(q,4)
	var floor_failures := 0
	var floor_samples := 0
	var count := maxi(1,ceili(q.motion.length()/combat.settings.path_sample_spacing))
	var radius: float = collider.shape.radius*0.95
	for index in range(count+1):
		var point := player.global_position+q.motion*float(index)/count
		for offset in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var sample: Vector3 = point+offset
			var ray := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*0.1,sample-Vector3.UP*0.1,1)
			var floor_hit := space.intersect_ray(ray)
			floor_samples += 1
			if floor_hit.is_empty() or absf(floor_hit.position.y-point.y) > combat.settings.floor_tolerance or floor_hit.normal.y < 0.99:
				floor_failures += 1
	var recovery: Vector3 = combat.Path.contact_position(player,player.global_position,combat.settings)-player.global_position
	print("GATES stock=",combat.stock.current," alive=",target.alive()," grounded=",player.is_on_floor()," attacking=",sprite._attacking,
		" distance=",player.global_position.distance_to(target.global_position)," dy=",target.global_position.y-player.global_position.y,
		" sight=",combat.Path.sight(player,target.global_position)," clear=",combat.Path.clear(player,combat.attack_position(target),combat.settings,player.global_position),
		" can_select=",combat.can_select(target)," legacy_overlap_count=",overlaps.size()," zero_margin_overlaps=",zero_margin_overlaps.size(),
		" legacy_sweep=",legacy_sweep," floor_failures=",floor_failures,"/",floor_samples," native_recovery=",recovery)
	_check(not overlaps.is_empty(), "Reproduces legacy initial-overlap rejection")
	_check(not zero_margin_overlaps.is_empty(), "Removing query padding alone does not resolve contact")
	_check(floor_failures == 0, "Contact does not invalidate footprint floor rays")
	_check(recovery.length() <= combat.settings.contact_recovery_limit, "Contact recovery is bounded")

func _prepare_view() -> void:
	rig.rotation.y = wall.rotation.y+PI
	await _ticks(25)
	anchor = player.global_position
	monitor = true

func _single(label: String, mouse: bool = false) -> void:
	await _prepare_view()
	_check(combat.can_select(target) and target.marker.visible, label+" marker visible")
	player.facing_world = (target.global_position-player.global_position).normalized()
	combat.selected_target = null
	combat._manual_selection = false
	await _ticks(2)
	_check(combat.selected_target == target and target.selected, label+" gold selected")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m07_wall_"+label+".png")
	var before := hits
	if mouse: _click(rig.camera.unproject_position(target.global_position+Vector3.UP*0.75),MOUSE_BUTTON_LEFT)
	else: _tap("attack")
	await _ticks(2)
	_check(combat.is_busy(), label+" input starts combat")
	await _wait_idle()
	_check(hits == before+1 and combat.stock.current == 2, label+" exactly one hit and spend")
	_check(combat.return_error <= combat.settings.contact_recovery_limit and not rig.follow_locked, label+" safe return and camera release")
	_check(not "blocked" in combat.last_result.to_lower(), label+" no immediate snag")
	monitor = false

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	rig = main.get_node("CameraRig")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	other = main.get_node("TrainingEnemySecond/Targetable")
	third = main.get_node("TrainingEnemyThird/Targetable")
	other.get_parent().position = Vector3(-20,0,-20)
	third.get_parent().position = Vector3(-22,0,-20)
	wall = _block(Vector3(-6,1.5,1),Vector3(8,3,0.5))
	wall.name = "ContactWall"
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8,3,0.5)
	visual.mesh = box
	wall.add_child(visual)
	combat.hit.connect(func(t: Node):
		hits += 1
		hit_targets.append(t)
		_check(sprite.frame == combat.settings.hit_frame, "Wall contact preserves hit-frame sync"))
	combat.state_changed.connect(func(next: int):
		if next == combat.State.Approach and combat.combo_hits == 0:
			# Capture at hold_follow(), not while FREE camera smoothing still runs.
			held_focus = rig.global_position
			_check(rig.follow_locked, "Camera locked when first approach starts"))
	await _contact()
	enemy.global_position = anchor+Vector3(3,0,0)
	await _ticks(2)
	_diagnose()
	await _single("parallel")
	await _contact()
	enemy.global_position = Vector3(-6,0,-3)
	await _ticks(2)
	await _single("away",true)
	await _contact(PI/4)
	enemy.global_position = anchor+wall.global_basis.x*3
	await _ticks(2)
	_diagnose()
	await _single("rotated_parallel")
	# Center-line visibility and capsule clearance are independent gates.
	await _contact()
	enemy.global_position = Vector3(-6,0,2.5)
	await _ticks(2)
	_check(not combat.Path.sight(player,target.global_position), "Sight ray really hits opposite-side wall")
	_check(not combat.can_select(target) and not target.marker.visible, "No opposite-side gold marker")
	_check(not combat.request_attack(target) and combat.stock.current == 3, "Opposite-side attack refuses without spend")
	_check(not combat.Path.clear(player,Vector3(-6,0,3),combat.settings,anchor), "Full wall crossing refused")
	var before := player.global_position
	_check(player.move_and_collide(Vector3(0,0,3),true) != null and player.global_position == before, "Native collision still blocks wall")
	# A center ray can miss a corner while the capsule clips it: reject that route.
	wall.get_child(0).shape.size = Vector3(2,3,0.5)
	box.size = Vector3(2,3,0.5)
	await _settle(Vector3(-7.31,0,0.45))
	var corner_clip := Vector3(-6.8,0,0.65)
	_check(combat.Path.sight(player,corner_clip), "Corner center ray is unobstructed")
	_check(not combat.Path.clear(player,corner_clip,combat.settings,player.global_position), "Capsule clips corner and is refused")
	_check(combat.Path.clear(player,Vector3(-7.31,0,2.5),combat.settings,player.global_position), "Open route beside corner allowed")
	_check(not combat.Path.clear(player,Vector3(-6,0,2.5),combat.settings,player.global_position), "Diagonal through corner refused")
	# Deep overlaps may not be treated as normal contact.
	wall.get_child(0).shape.size = Vector3(8,3,0.5)
	box.size = Vector3(8,3,0.5)
	await _ticks(2)
	player.set_physics_process(false)
	player.global_position = Vector3(-6,0,0.47)
	_check(not combat.Path.contact_position(player,player.global_position,combat.settings).is_finite(), "20mm penetration exceeds recovery allowance")
	_check(not combat.Path.clear(player,Vector3(-3,0,0.47),combat.settings,player.global_position), "Deep penetration route rejected")
	player.set_physics_process(true)
	# Three enemies share the original wall-side return anchor.
	await _contact()
	enemy.global_position = anchor+Vector3(3,0,0)
	other.get_parent().global_position = Vector3(-7.5,0,-1.5)
	third.get_parent().global_position = Vector3(-4.5,0,-2)
	await _ticks(2)
	await _prepare_view()
	_check(combat.request_attack(target), "Wall-side ABC starts")
	var first_hit := hit_targets.size()
	var reserved_stage := 0
	for i in range(300):
		await _ticks(1)
		if not combat.is_busy(): break
		if combat.state == combat.State.Attack and combat.combo_hits > reserved_stage and combat.combo_hits < 3:
			var next: Node3D = other if combat.combo_hits == 1 else third
			_tap("lock_on")
			_check(not combat.queued, "L alone never reserves a hit")
			_check(combat.stock.current == 3-combat.combo_hits, "Selection does not spend stock")
			_click(rig.camera.unproject_position(next.global_position+Vector3.UP*0.75),MOUSE_BUTTON_LEFT)
			_check(combat.queued and combat.queued_attack_target == next, "Mouse reserves exactly next target")
			_check(not combat.request_followup(), "Only one reservation")
			reserved_stage = combat.combo_hits
	_check(hit_targets.slice(first_hit) == [target,other,third], "Wall-side ABC hits each once")
	_check(combat.stock.current == 0 and combat.combo_hits == 3, "ABC consumes three stocks")
	_check(combat.return_error <= combat.settings.contact_recovery_limit and not rig.follow_locked, "ABC returns to original contact within tolerance")
	monitor = false
	# A new wall blocks an already-reserved next enemy; no ignored collider or spend.
	await _contact()
	enemy.global_position = anchor+Vector3(3,0,0)
	await _prepare_view()
	_check(combat.request_attack(target), "Blocked next cycle starts")
	for i in range(90):
		await _ticks(1)
		if combat.state == combat.State.Attack: break
	_check(combat.request_followup(other,true), "Next initially safe")
	var new_wall := _block(player.global_position.lerp(other.global_position,0.5)+Vector3.UP,Vector3(0.5,2,1))
	await _wait_idle()
	_check(combat.combo_hits == 1 and combat.stock.current == 2, "New obstacle cancels next without spend")
	_check(not rig.follow_locked and not combat.queued, "Blocked combo releases camera and queue")
	new_wall.free()
	monitor = false
	if failures.is_empty(): print("PASS M07 wall contact: diagnostics, parallel/away/rotated, opposite, corner, deep overlap, ABC, blocked next, camera/stock")
	for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
