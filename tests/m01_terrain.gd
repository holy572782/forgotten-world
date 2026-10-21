extends SceneTree
## Disposable physics probe, not the M02 player controller.
## Run: godot --headless --path . --script res://tests/m01_terrain.gd

var failures: Array[String] = []
var probe: CharacterBody3D
var arena: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node3D
	main.get_node("PracticeSelector").initial_mode = 0 # Isolate this legacy trial from the F5 enemy.
	# Probe coordinates below refer to the original M01 fixture.
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	arena = main.get_node("TestArena")
	probe = CharacterBody3D.new()
	probe.collision_layer = 2
	probe.collision_mask = 1
	probe.floor_max_angle = deg_to_rad(40.0)
	probe.floor_snap_length = 0.3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9 # Probe origin is its feet, as is PlayerSpawn.
	probe.add_child(collider)
	root.add_child(probe)
	await physics_frame
	await physics_frame
	_check(arena.get_node("PlayerSpawn").position == Vector3(0, 0, 6), "Spawn marker")
	_drop(Vector3(0, 4, 6), "FlatGround", 0.0)
	_drop(Vector3(-6, 5, -8), "Landing", 2.0)
	_drop(Vector3(5, 4, 1), "StepLow", 0.25)
	_drop(Vector3(5, 4, -1), "StepMiddle", 0.5)
	_drop(Vector3(5, 4, -3), "StepHigh", 1.0)
	probe.position = Vector3(3, 0.02, -6)
	var hit := probe.move_and_collide(Vector3(0, 0, -6))
	_check(hit != null and hit.get_collider().name == "Wall", "Wall blocks capsule")
	_check(probe.position.z > -8.71, "No wall penetration")
	probe.position = Vector3(5, 0.01, 3)
	hit = probe.move_and_collide(Vector3(0, 0, -3))
	_check(hit != null and hit.get_collider().name == "StepLow", "Low step riser blocks capsule")
	# Exercise the actual slope/landing seams using Godot's CharacterBody3D solver.
	probe.position = Vector3(-6, 0.02, 2)
	var maximum_height := 0.0
	for tick in range(260):
		await physics_frame
		probe.velocity = Vector3(0, -2, -3)
		probe.move_and_slide()
		maximum_height = maxf(maximum_height, probe.position.y)
	_check(probe.position.z < -7.0, "Capsule walks up ramp onto landing: " + str(probe.position))
	_check(absf(probe.position.y - 2.0) < 0.06 and probe.is_on_floor(), "Grounded on landing")
	_check(maximum_height < 2.06, "No upward seam pop")
	for tick in range(260):
		await physics_frame
		probe.velocity = Vector3(0, -2, 3)
		probe.move_and_slide()
	_check(probe.position.z > 1.0, "Capsule walks down ramp to flat ground")
	_check(absf(probe.position.y) < 0.06 and probe.is_on_floor(), "Grounded after descent")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png("res://.godot/m01_preview.png")
		_check(error == OK, "Save rendered preview")
	if failures.is_empty():
		print("PASS M01: ground, wall, three step heights, riser, ramp ascent/descent and landing seams")
	else:
		for failure in failures:
			push_error(failure)
	main.free()
	probe.free()
	quit(0 if failures.is_empty() else 1)

func _drop(start: Vector3, expected_body: String, expected_height: float) -> void:
	probe.position = start
	var hit := probe.move_and_collide(Vector3(0, -10, 0))
	# Refine the long sweep stop with a short motion before measuring contact height.
	probe.move_and_collide(Vector3(0, -0.1, 0))
	_check(hit != null and hit.get_collider().name == expected_body, expected_body + ": catches falling capsule")
	_check(absf(probe.position.y - expected_height) < 0.02, expected_body + ": surface height " + str(probe.position.y))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
