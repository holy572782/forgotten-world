extends SceneTree
## Run with --headless; append -- --capture with a real renderer for PNGs.
## Drive the production physics callback once per physics tick, with synthetic Input events.

const Controller = preload("res://scripts/player/player_controller.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []
var main: Node3D
var player: CharacterBody3D
var camera: Camera3D
var original_rotation: Vector3
var held_keys := Vector2.ZERO
var held_axes := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	# Fixed fixture coordinates; do not change the saved arena placement.
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	player = main.get_node("Player")
	root.add_child(main)
	player.set_physics_process(false)
	camera = main.get_node("TestArena/Preview/Camera3D")
	_check(player.movement_camera == main.get_node("CameraRig/SpringArm3D/Camera3D"), "M04 camera wiring")
	# Isolate the existing locomotion regression from orbit/follow, tested in M04.
	main.get_node("CameraRig").set_physics_process(false)
	player.movement_camera = camera
	camera.make_current()
	original_rotation = camera.rotation
	_check(player.global_position == main.get_node("TestArena/PlayerSpawn").global_position, "Spawn wiring")
	_check(player.movement_camera == camera, "Camera wiring")
	await _ticks(10)
	_check(player.is_on_floor(), "Spawn grounded")
	var sprite: AnimatedSprite3D = player.get_node("AnimatedSprite3D")
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 1)
	_check(sprite.position.is_zero_approx() and absf(sprite.offset.y - (texture.get_height() / 2.0 - 1.0)) < 0.0001, "Sprite lower edge matches feet")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	_check(absf(collider.position.y - collider.shape.height / 2.0) < 0.0001, "Capsule lower edge matches feet")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not sprite.no_depth_test, "Full billboard and depth test")
	_check(player.collision_layer == 2 and player.collision_mask == 1, "3D collision layers")
	camera.rotation = Vector3.ZERO
	var directions: Array[Vector2] = [Vector2.UP, Vector2(1, -1), Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1), Vector2.LEFT, Vector2(-1, -1)]
	for direction in directions:
		await _reset(Vector3(0, 0.01, 7))
		_keys(direction)
		await _ticks(20)
		var start := player.position
		await _ticks(20)
		var expected := Vector3(direction.x, 0, direction.y).normalized()
		var displacement := player.position - start
		_check(absf(displacement.length() - 5.0 * 20.0 * STEP) < 0.025, "T01 equal distance " + str(direction) + ": " + str(displacement.length()))
		_check(displacement.normalized().dot(expected) > 0.999, "Direction " + str(direction))
		_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 5.0) < 0.01, "T01 max speed " + str(direction))
		_check(player.facing_index == posmod(roundi(atan2(direction.x, direction.y) / (PI / 4.0)), 8), "Visual facing sector")
	_release()
	await _ticks(1)
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 4.5) < 0.01, "Deceleration 30 m/s2")
	await _ticks(12)
	_check(player.velocity.length() < 0.01, "Released input stops")
	await _reset(Vector3(0, 0.01, 7))
	_keys(Vector2.RIGHT)
	await _ticks(1)
	_check(absf(player.velocity.x - 22.0 * STEP) < 0.01, "Acceleration 22 m/s2")
	await _reset(Vector3(0, 0.01, 7))
	_axis(JOY_AXIS_LEFT_X, 0.1)
	await _ticks(20)
	_check(absf(player.velocity.x) < 0.001, "Stick radial deadzone")
	_axis(JOY_AXIS_LEFT_X, 0.6)
	await _ticks(20)
	_check(absf(player.velocity.x - 2.5) < 0.02, "Analog half speed after deadzone")
	_axis(JOY_AXIS_LEFT_X, 0.48)
	_axis(JOY_AXIS_LEFT_Y, -0.64)
	await _ticks(30)
	var analog_motion := Vector2(player.velocity.x, player.velocity.z)
	_check(absf(analog_motion.length() - 3.75) < 0.02, "Analog radial strength")
	_check(analog_motion.normalized().dot(Vector2(0.6, -0.8)) > 0.999, "Analog direction is not quantized")
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _ticks(15)
	_check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 5.0) < 0.02, "Stick diagonal capped")
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		await _reset(Vector3(0, 0.01, 7))
		camera.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(yaw), 0)
		_keys(Vector2.UP)
		await _ticks(20)
		var expected := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw))
		_check(Vector3(player.velocity.x, 0, player.velocity.z).normalized().dot(expected) > 0.999, "Camera basis yaw " + str(yaw))
	var vertical_basis := Basis.from_euler(Vector3(-PI / 2.0, 0, 0))
	_check(Controller.input_to_world(Vector2.UP, vertical_basis).is_equal_approx(Vector3.FORWARD), "Vertical camera fallback")
	camera.rotation = Vector3.ZERO
	await _reset(Vector3(3, 0.01, -6))
	_keys(Vector2.UP)
	await _ticks(90)
	_check(player.position.z > -8.41 and player.position.z < -8.2 and player.is_on_wall(), "Wall blocks actual player: " + str(player.position))
	await _reset(Vector3(5, 0.01, 3))
	_keys(Vector2.UP)
	await _ticks(60)
	_check(player.position.z > 2.15 and player.position.y < 0.05, "Step riser blocks; no automatic climb")
	await _reset(Vector3(-6, 0.01, 2))
	_keys(Vector2.UP)
	var highest := 0.0
	var airborne := 0
	for tick in range(120):
		await _ticks(1)
		highest = maxf(highest, player.position.y)
		if not player.is_on_floor():
			airborne += 1
	_check(player.position.z < -6.5 and absf(player.position.y - 2.0) < 0.06, "Ramp reaches landing: " + str(player.position))
	_check(airborne == 0 and highest < 2.06, "Ramp ascent stays grounded without seam pop")
	_release()
	_keys(Vector2.DOWN)
	for tick in range(140):
		await _ticks(1)
		if not player.is_on_floor():
			airborne += 1
	_check(player.position.z > 1.0 and absf(player.position.y) < 0.06 and airborne == 0, "Ramp descent stays grounded")
	await _reset(Vector3(-6, 1, -3))
	var rest := player.position
	await _ticks(60)
	_check(player.position.distance_to(rest) < 0.01 and player.is_on_floor(), "No idle slope sliding")
	# Temporarily steepen only this test instance to prove the 40-degree limit.
	var ramp: StaticBody3D = main.get_node("TestArena/Terrain/Ramp")
	var ramp_transform := ramp.transform
	ramp.position = Vector3(-6, 2.2, -3)
	ramp.rotation.x = deg_to_rad(55.0)
	await _reset(Vector3(-6, 0.01, 0))
	_keys(Vector2.UP)
	await _ticks(90)
	_check(player.position.z > -2.0 and player.position.y < 0.1, "55 degree slope is blocked")
	ramp.transform = ramp_transform
	await _reset(Vector3(0, 0.01, 7))
	var original_speed: float = player.movement.speed
	player.movement = player.movement.duplicate()
	player.movement.speed = 2.0
	_keys(Vector2.RIGHT)
	await _ticks(20)
	_check(absf(player.velocity.x - 2.0) < 0.01, "Movement Resource controls speed")
	player.movement.speed = original_speed
	await _reset(Vector3(0, 0.01, 7))
	# Jump is tested by M03; keep the unrelated action/camera scope regression.
	Input.action_press("attack")
	Input.action_press("camera_left")
	await _ticks(30)
	_check(player.is_on_floor() and absf(player.position.y) < 0.02 and camera.rotation == Vector3.ZERO, "No attack or camera rotation added")
	# No jump input in this M02 regression.
	Input.action_release("attack")
	Input.action_release("camera_left")
	# Also verify Godot's normal automatic callback path, not just direct tick calls.
	await _reset(Vector3(0, 0.01, 7))
	_keys(Vector2.RIGHT)
	player.set_physics_process(true)
	var automatic_start := player.position
	for tick in range(31):
		await physics_frame
		_refresh_input()
	player.set_physics_process(false)
	_check(player.position.x - automatic_start.x > 1.5 and absf(player.velocity.x - 5.0) < 0.01, "Automatic physics callback moves player")
	camera.rotation = original_rotation
	await _reset(main.get_node("TestArena/PlayerSpawn").position + Vector3(0, 0.01, 0))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture("m02_preview")
		# Close view for alpha edges and ground contact; the production camera is unchanged.
		camera.size = 8.0
		camera.position = player.position + Vector3(4, 5, 7)
		camera.look_at(player.position + Vector3(0, 0.7, 0))
		await _capture("m02_feet")
		camera.position = Vector3(3, 4, -3)
		camera.look_at(Vector3(3, 1, -9))
		player.position = Vector3(3, 0.01, -10.2)
		await _ticks(10)
		await _capture("m02_occlusion")
	_release()
	if failures.is_empty():
		print("PASS M02: T01 eight directions, analog input, acceleration/braking, camera basis, feet, wall/steps, ramp seams, slope limit, Resource and scope regression")
	else:
		for failure in failures:
			push_error(failure)
	main.free()
	quit(0 if failures.is_empty() else 1)

func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame
		# Reinject held synthetic events after OS focus/key events in rendered runs.
		_refresh_input()
		player._physics_process(STEP)

func _reset(at: Vector3) -> void:
	_release()
	player.position = at
	player.velocity = Vector3.ZERO
	await _ticks(12)

func _keys(direction: Vector2) -> void:
	held_keys = direction
	for item in [[KEY_A, direction.x < 0], [KEY_D, direction.x > 0], [KEY_W, direction.y < 0], [KEY_S, direction.y > 0]]:
		var event := InputEventKey.new()
		event.physical_keycode = item[0]
		event.pressed = item[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _axis(axis: JoyAxis, value: float) -> void:
	held_axes[axis] = value
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _refresh_input() -> void:
	_keys(held_keys)
	_axis(JOY_AXIS_LEFT_X, held_axes.x)
	_axis(JOY_AXIS_LEFT_Y, held_axes.y)

func _release() -> void:
	_keys(Vector2.ZERO)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/" + label + ".png") == OK, "Save " + label)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
