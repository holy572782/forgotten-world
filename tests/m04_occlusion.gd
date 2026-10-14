extends "res://tests/m04_camera.gd"
## Camera-distance A/B, real-world fading, material ownership and volume safety.
var wall: MeshInstance3D
var wall_body: StaticBody3D
var base_material: Material
var comparison: Array[Vector3] = []

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	rig = main.get_node("CameraRig")
	camera = rig.camera
	wall_body = main.get_node("TestArena/Terrain/Wall")
	wall = wall_body.get_node("Mesh")
	base_material = wall.get_active_material(0)
	await _ticks(5)
	# Identical 360-degree wall orbit; exclude initial placement from per-tick deltas.
	for mode in [0, 1]:
		rig.settings = rig.settings.duplicate()
		rig.settings.occlusion_mode = mode
		await _reset(Vector3(3, 0, -7.5), 0)
		var minimum := 100.0
		var maximum := 0.0
		var max_change := 0.0
		var previous := camera.global_position.distance_to(rig.global_position)
		held.camera_right = 1.0
		for tick in range(216):
			await _ticks(1)
			var distance := camera.global_position.distance_to(rig.global_position)
			minimum = minf(minimum, distance)
			maximum = maxf(maximum, distance)
			max_change = maxf(max_change, absf(distance - previous))
			previous = distance
			_check(_clear(camera.global_position), "Camera volume clear in A/B orbit")
		comparison.append(Vector3(minimum, maximum, max_change))
		print("DISTANCE mode=", mode, " min/max/max_tick_change=", comparison[-1])
		await _reset(Vector3(3, 0, -7.5), 180)
		await _ticks(25)
		await _image("mode_%d_wall" % mode)
	_check(comparison[0].x < 3.0 and comparison[1].x > 9.9, "B avoids A wall zoom")
	_check(comparison[1].z < 0.01, "B no sudden distance change for sightline blockers")
	_check(wall.get_active_material(0) != base_material, "Per-instance material copy")
	_check(is_equal_approx(base_material.albedo_color.a, 1.0), "Original alpha remains unchanged")
	_check(absf(wall.get_active_material(0).albedo_color.a - 0.3) < 0.001, "Occluded opacity 0.3")
	_check(wall_body.collision_layer == 1 and wall_body.get_node("Collision").disabled == false, "Fading preserves collision")
	# Multiple collinear blockers, using shared source material. Unrelated clone stays opaque.
	var second := _box(Vector3(3, 3, -10.2), Vector3(8, 6, 0.4), base_material)
	var unrelated := _box(Vector3(11, 1.5, -9), Vector3(2, 3, 0.6), base_material)
	await _ticks(25)
	var second_mesh: MeshInstance3D = second.get_node("Mesh")
	_check(second_mesh.get_active_material(0) != base_material and wall.get_active_material(0) != base_material, "All collinear walls fade")
	_check(unrelated.get_node("Mesh").get_active_material(0) == base_material, "Shared material neighbour unchanged")
	await _image("multiple")
	second.free()
	await _ticks(2)
	_check(rig.fader.entries.size() >= 1, "Deleted occluder pruned without losing remaining wall")
	unrelated.free()
	# Jump and orbit refresh the targets without resetting material ownership.
	held.jump = 1.0
	await _ticks(18)
	await _image("jump_wall")
	_check(player.position.y > 0.5 and rig.fader.entries.has(wall.get_instance_id()), "Jump refreshes occlusion")
	held.clear()
	await _ticks(60)
	# Small, brief visibility changes retain the fade rather than toggling the pipeline.
	var faded_material := wall.get_active_material(0)
	rig.rotation.y = 0
	rig.snap_to_target()
	await _ticks(3)
	_check(wall.get_active_material(0) == faded_material, "Release hysteresis avoids material flicker")
	rig.rotation.y = PI
	rig.snap_to_target()
	await _ticks(3)
	_check(wall.get_active_material(0) == faded_material, "Reacquisition reuses fade state")
	await _reset(Vector3(3, 0, -7.5), 0)
	await _ticks(30)
	_check(wall.get_active_material(0) == base_material and wall.get_surface_override_material(0) == null, "Exact original binding restored")
	_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Shadow state restored")
	await _image("restored")
	# Shared ramp/landing materials: only the obstructing mesh receives overrides.
	for item in [[Vector3(-3.3, 0, -4), "Ramp"], [Vector3(-3.3, 0, -8), "Landing"]]:
		await _reset(item[0], 270)
		await _ticks(25)
		var mesh: MeshInstance3D = main.get_node("TestArena/Terrain/" + item[1] + "/Mesh")
		_check(mesh.get_surface_override_material(0) != null, "Fade M01 " + item[1])
		_check(absf(camera.global_position.distance_to(rig.global_position) - 10) < 0.01, "Distance on " + item[1])
		await _image(item[1].to_lower())
	# Actual body collision at the nominal eye: retain >=8m rather than collapsing.
	await _reset(Vector3(0, 0, 6), 0)
	var desired := camera.global_position
	var eye_obstacle := _box(desired, Vector3(1, 1, 1), base_material)
	await _ticks(4)
	_check(_clear(camera.global_position) and not rig.safety_failed, "Eye overlap resolved")
	_check(camera.global_position.distance_to(rig.global_position) >= 8.0, "Local correction avoids large zoom")
	await _image("eye_correction")
	eye_obstacle.free()
	for tick in range(20):
		var before := camera.global_position
		await _ticks(1)
		_check(camera.global_position.distance_to(before) <= rig.settings.correction_speed * STEP + 0.01, "Correction release speed bounded")
	# Sweep protects the path even when both endpoints are clear.
	var solver = load("res://scripts/camera/camera_collision.gd").new()
	var space := player.get_world_3d().direct_space_state
	var previous := Vector3(3, 1.5, -7)
	var wanted := Vector3(3, 1.5, -11)
	var excludes: Array[RID] = [player.get_rid()]
	var result: Vector3 = solver.solve(space, wanted, previous, Basis.IDENTITY, rig.settings, excludes, false, STEP)
	_check(_clear(result) and result.z > -8.7, "Swept camera cannot cross thin wall")
	# Move around a tall obstruction at eye height. Sample the render interpolation path.
	await _reset(Vector3(0, 0, 6), 0)
	var orbit_obstacle := _box(rig.global_position + Vector3(0, 7.071, 7.071).rotated(Vector3.UP, deg_to_rad(-30)), Vector3(1.5, 3, 1.5), base_material)
	await _ticks(2)
	held.camera_right = 1.0
	for tick in range(90):
		var before := camera.global_position
		await _ticks(1)
		_check(_clear(camera.global_position), "Eye obstacle orbit endpoint")
		if not rig.safety.discontinuity:
			for fraction in [0.25, 0.5, 0.75]:
				_check(_clear(before.lerp(camera.global_position, fraction)), "Eye obstacle render interpolation path")
	orbit_obstacle.free()
	held.clear()
	# A huge enclosing test box exercises the explicit failure/recovery path.
	await _reset(Vector3(0, 0, 6), 0)
	var enclosure := _box(camera.global_position, Vector3(100, 100, 100), base_material)
	player.set_physics_process(false)
	await _ticks(3)
	_check(rig.safety_failed and camera.cull_mask == 0, "No safe position is explicit failure, not embedded rendering")
	enclosure.free()
	await _ticks(3)
	_check(not rig.safety_failed and camera.cull_mask != 0 and _clear(camera.global_position), "Safety recovers after geometry removal")
	player.set_physics_process(true)
	# Render caps, normal physics updates: 15 physics ticks = 0.25 seconds.
	for fps in [30, 60]:
		Engine.max_fps = fps
		await _reset(Vector3(3, 0, -7.5), 180)
		rig.fader.restore_all()
		await _ticks(7)
		var halfway: float = wall.get_active_material(0).albedo_color.a
		await _ticks(8)
		var end_alpha: float = wall.get_active_material(0).albedo_color.a
		print("FADE fps=", fps, " alpha_7ticks=", halfway, " alpha_15ticks=", end_alpha)
		_check(halfway > 0.5 and halfway < 0.8 and absf(end_alpha - 0.3) < 0.002, "Fade duration cap=" + str(fps))
		await _image("fade_fps_%d" % fps)
	# Mode switch and removing rig must restore materials immediately.
	rig.settings.occlusion_mode = 0
	await _ticks(2)
	_check(wall.get_active_material(0) == base_material, "A mode restores B material changes")
	rig.settings.occlusion_mode = 1
	await _ticks(25)
	rig.set_physics_process(false)
	main.remove_child(rig)
	_check(wall.get_active_material(0) == base_material, "Rig removal restores materials")
	rig.free()
	main.set_physics_process(false)
	held.clear()
	_refresh()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M04 occlusion: A/B distance, multiple/removed blockers, ownership/restoration, jump, hysteresis, terrain, eye overlap/sweep/failure, 30/60 fade")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _box(at: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.mesh.material = material
	body.add_child(mesh)
	main.add_child(body)
	body.global_position = at
	return body

func _clear(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.24
	query.shape = shape
	query.transform.origin = at
	query.collision_mask = 1
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _image(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/m04_fade_" + label + ".png") == OK, "Save image " + label)
