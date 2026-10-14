extends SceneTree
## Synthetic integration tests. --capture uses real rendering and saves T04 images.
const STEP := 1.0 / 60.0
var main: Node3D
var player: CharacterBody3D
var rig: Node3D
var camera: Camera3D
var failures: Array[String] = []
var held: Dictionary = {}
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	main = load("res://scenes/main.tscn").instantiate()
	# Fixed M01 fixture coordinates, independent of editor placement of the arena.
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	if "--legacy" in OS.get_cmdline_user_args():
		var setup_rig = main.get_node("CameraRig")
		setup_rig.settings = setup_rig.settings.duplicate()
		setup_rig.settings.occlusion_mode = 0
	root.add_child(main)
	player = main.get_node("Player")
	rig = main.get_node("CameraRig")
	camera = rig.camera
	await _ticks(15)
	_check(camera == root.get_camera_3d() and player.movement_camera == camera, "Active camera wiring")
	_check(is_equal_approx(rig.arm.rotation.x, -PI / 4) and camera.global_position.y > player.position.y, "Downward pitch sign")
	_check(is_equal_approx(camera.global_position.distance_to(rig.global_position), 10.0), "Open ground full length; no player collision")
	_check(ProjectSettings.get_setting("physics/common/physics_interpolation"), "Shared physics interpolation enabled")
	# Move the actual body, with the production camera at each cardinal yaw.
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		for action in ["move_up", "move_down", "move_left", "move_right"]:
			await _reset(Vector3(0, 0, 6), yaw)
			held[action] = 1.0
			await _ticks(25)
			var axis: Vector3 = {"move_up": Vector3.FORWARD, "move_down": Vector3.BACK, "move_left": Vector3.LEFT, "move_right": Vector3.RIGHT}[action]
			var expected := axis.rotated(Vector3.UP, deg_to_rad(yaw))
			_check(Vector3(player.velocity.x, 0, player.velocity.z).normalized().dot(expected) > 0.999, "T02 yaw=%s %s" % [yaw, action])
		await _reset(Vector3(0, 0, 6), yaw)
		await _image("yaw_%d" % int(yaw))
	# Q/E and right-stick events traverse the existing InputMap.
	for item in [[KEY_Q, 1.0], [KEY_E, -1.0]]:
		await _reset(Vector3(0, 0, 6), 0)
		rig.set_physics_process(false)
		var key := InputEventKey.new()
		key.physical_keycode = item[0]
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		rig._physics_process(0.5)
		_check(absf(rad_to_deg(rig.rotation.y) - 50.0 * item[1]) < 0.01, "Q/E direction and speed")
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		rig.set_physics_process(true)
	for strength in [0.1, 0.6, -0.6, 1.0]:
		await _reset(Vector3(0, 0, 6), 0)
		rig.set_physics_process(false)
		var stick := InputEventJoypadMotion.new()
		stick.axis = JOY_AXIS_RIGHT_X
		stick.axis_value = strength
		Input.parse_input_event(stick)
		Input.flush_buffered_events()
		rig._physics_process(0.5)
		var expected := -signf(strength) * maxf(0, (absf(strength) - 0.2) / 0.8) * 50
		_check(absf(rad_to_deg(rig.rotation.y) - expected) < 0.01, "Analog orbit strength=" + str(strength))
		stick = stick.duplicate()
		stick.axis_value = 0
		Input.parse_input_event(stick)
		Input.flush_buffered_events()
		rig.set_physics_process(true)
	await _reset(Vector3(0, 0, 6), 0)
	held = {"move_up": 1.0, "camera_right": 1.0}
	for tick in range(90):
		await _ticks(1)
		if tick > 20:
			var forward := -camera.global_basis.z
			forward.y = 0
			_check(Vector3(player.velocity.x, 0, player.velocity.z).normalized().dot(forward.normalized()) > 0.98, "T02 moving while orbiting")
		_check(player.position.distance_to(rig.position - rig.settings.target_offset) < 1.0, "Follow bounded during movement")
	# Jump with production callbacks and actual camera framing.
	await _reset(Vector3(0, 0, 6), 0)
	held.jump = 1.0
	var highest := 0.0
	for tick in range(65):
		await _ticks(1)
		highest = maxf(highest, rig.position.y)
		_check(not camera.is_position_behind(player.position + Vector3.UP), "Jump remains in front of camera")
		var screen := camera.unproject_position(player.position + Vector3.UP)
		_check(root.get_visible_rect().has_point(screen), "Jump remains on screen")
		if tick == 18: await _image("jump")
	_check(highest > 1.5 and player.is_on_floor(), "Vertical follow and landing")
	# Static and moving orbit clearance on M01 wall/ramp/platform.
	for item in [[Vector3(3, 0, -7.5), 180.0, "wall"], [Vector3(-3.3, 0, -4), 270.0, "ramp"], [Vector3(-3.3, 0, -8), 270.0, "platform"]]:
		await _reset(item[0], item[1])
		if rig.settings.occlusion_mode == 0: _check(rig.arm.get_hit_length() < 9.0, "Obstacle shortens arm: " + item[2] + " length=" + str(rig.arm.get_hit_length()))
		await _image(item[2])
		held.camera_right = 1.0
		for tick in range(216):
			await _ticks(1)
			var query := PhysicsShapeQueryParameters3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.1
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
			query.collision_mask = 1
			_check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "Camera clearance during orbit: " + item[2])
	# Real fall recovery and explicit teleport both snap without slow traversal.
	await _reset(Vector3(13, 0, 6), 0)
	held.move_right = 1.0
	var recovered := false
	for tick in range(220):
		await _ticks(1)
		if player.position.x < 1:
			recovered = true
			_check(rig.position.distance_to(player.position + rig.settings.target_offset) < 0.001, "Recovery snaps camera same tick")
			break
	_check(recovered, "Open edge recovery")
	await _reset(Vector3(0, 0, 6), 0)
	player.reset_motion(Vector3(10, 0, 6))
	await _ticks(1)
	_check(rig.position.distance_to(player.position + rig.settings.target_offset) < 0.01, "Large teleport auto sync")
	# Exponential smoothing at equal elapsed time with different delta partitions.
	rig.set_physics_process(false)
	player.set_physics_process(false)
	var endpoints: Array[Vector3] = []
	for fps in [30, 60]:
		rig.snap_to_target()
		rig.position.x -= 3.0
		for step in range(fps): rig._physics_process(1.0 / fps)
		endpoints.append(rig.position)
	_check(endpoints[0].distance_to(endpoints[1]) < 0.0001, "Exponential follow delta independence")
	rig.set_physics_process(true)
	player.set_physics_process(true)
	# Actual renderer caps, normal 60Hz physics, equal physics duration.
	var results: Array[Vector2] = []
	for fps in [30, 60]:
		Engine.max_fps = fps
		await _reset(Vector3(0, 0, 6), 0)
		held = {"move_up": 1.0, "camera_right": 1.0}
		var start_frame := Engine.get_frames_drawn()
		await _ticks(60)
		var measurement := Vector2(rad_to_deg(rig.rotation.y), rig.position.distance_to(player.position + rig.settings.target_offset))
		results.append(measurement)
		print("FPS_CAP=", fps, " yaw/follow_error=", measurement, " rendered_frames=", Engine.get_frames_drawn() - start_frame)
		_check(absf(measurement.x + 100.0) < 0.1, "100 degrees per second cap=" + str(fps))
		await _image("fps_%d" % fps)
	_check(results[0].distance_to(results[1]) < 0.02, "30/60 cap equivalent follow and orbit")
	held.clear()
	_refresh()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M04: T02 integration, follow/jump/recovery, Q/E/analog, terrain clearance, delta and 30/60 caps; T04 captures require visual review")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _ticks(count: int) -> void:
	_refresh()
	for tick in range(count):
		await physics_frame
		_refresh()

func _refresh() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "jump", "camera_left", "camera_right"]:
		if held.has(action): Input.action_press(action, held[action])
		else: Input.action_release(action)

func _reset(at: Vector3, yaw: float) -> void:
	held.clear()
	_refresh()
	player.reset_motion(at)
	rig.rotation.y = deg_to_rad(yaw)
	rig.snap_to_target()
	await _ticks(20)

func _image(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/m04_" + label + ".png") == OK, "Save image " + label)

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
