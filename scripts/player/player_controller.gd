extends CharacterBody3D
## Locomotion and jumping. Body origin is the contact point beneath the capsule.

const MovementSettings = preload("res://scripts/player/player_movement.gd")

@export var movement: MovementSettings = preload("res://resources/player_movement.tres")
@export var movement_camera: Camera3D

var facing_world := Vector3.BACK
## Screen-relative sectors: down, down-right, right, up-right, up, up-left, left, down-left.
var facing_index: int = 0
var combat: Node
var _coyote_remaining := 0.0
var _buffer_remaining := 0.0
var _jump_consumed := false
var _jump_requested := false
var _jump_was_pressed := false
var _wait_for_jump_release := false
var _floor_valid := false

func _ready() -> void:
	floor_max_angle = deg_to_rad(movement.max_slope_degrees)
	floor_snap_length = movement.snap_length
	floor_constant_speed = true
	floor_stop_on_slope = true

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(combat) and combat.is_busy():
		return
	# Preserve short press/release taps between physics ticks, but ignore key repeat.
	if event.is_action_pressed("jump") and not event.is_echo() and not _wait_for_jump_release:
		_jump_requested = true

func _physics_process(delta: float) -> void:
	if is_instance_valid(combat):
		combat.physics_step(delta)
		if combat.is_busy():
			return
	var grounded := _floor_valid and is_on_floor() and not _jump_consumed
	_update_jump_input(delta)
	if grounded:
		_coyote_remaining = movement.coyote_time
	else:
		_coyote_remaining = maxf(0.0, _coyote_remaining - delta)
	_apply_gravity(delta, grounded)
	if _buffer_remaining > 0.0 and not _jump_consumed and (grounded or _coyote_remaining > 0.0):
		_start_jump()
	var view_basis := _movement_basis()
	_update_horizontal(delta, view_basis, grounded and not _jump_consumed)
	move_and_slide()
	_floor_valid = true
	_update_landing(grounded)
	_update_facing(view_basis)

func _update_jump_input(delta: float) -> void:
	_buffer_remaining = maxf(0.0, _buffer_remaining - delta)
	var pressed := Input.is_action_pressed("jump")
	if _wait_for_jump_release:
		_buffer_remaining = 0.0
		_jump_requested = false
		if not pressed:
			_wait_for_jump_release = false
	elif _jump_requested or (pressed and not _jump_was_pressed):
		_buffer_remaining = movement.jump_buffer_time
	_jump_requested = false
	_jump_was_pressed = pressed

func _start_jump() -> void:
	velocity.y = movement.jump_speed
	_jump_consumed = true
	_coyote_remaining = 0.0
	_buffer_remaining = 0.0

func _apply_gravity(delta: float, grounded: bool) -> void:
	if grounded and not _jump_consumed:
		velocity.y = 0.0
	else:
		velocity.y -= movement.gravity * delta

func _update_landing(was_grounded: bool) -> void:
	# A buffered launch sets upward velocity after collision resolution. The consumed
	# flag keeps the stale is_on_floor result from clearing it on the following tick.
	if is_on_floor() and velocity.y <= 0.0:
		_jump_consumed = false
		_coyote_remaining = movement.coyote_time
		if _buffer_remaining > 0.0:
			_start_jump()
	elif was_grounded and not _jump_consumed:
		_coyote_remaining = movement.coyote_time

func reset_motion(at: Vector3) -> void:
	if is_instance_valid(combat):
		combat.cancel()
	# Map/respawn code chooses the safe point; the controller only resets motion.
	global_position = at
	velocity = Vector3.ZERO
	_coyote_remaining = 0.0
	_buffer_remaining = 0.0
	_jump_consumed = true
	_jump_requested = false
	_jump_was_pressed = Input.is_action_pressed("jump")
	_wait_for_jump_release = true
	_floor_valid = false
	reset_physics_interpolation()

func clear_combat_input() -> void:
	velocity = Vector3.ZERO
	_buffer_remaining = 0.0
	_jump_requested = false
	_coyote_remaining = 0.0
	_wait_for_jump_release = true
	_jump_was_pressed = Input.is_action_pressed("jump")

func _movement_basis() -> Basis:
	var camera := movement_camera
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	return camera.global_basis if is_instance_valid(camera) else Basis.IDENTITY

func _update_horizontal(delta: float, view_basis: Basis, grounded: bool) -> void:
	# get_vector caps diagonals and retains analog strength and radial deadzone.
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var desired := input_to_world(input_vector, view_basis) * movement.speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := movement.deceleration if input_vector.is_zero_approx() else movement.acceleration
	if not grounded:
		rate *= movement.air_control
	horizontal = horizontal.move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

func _update_facing(view_basis: Basis) -> void:
	var actual_horizontal := Vector3(get_real_velocity().x, 0.0, get_real_velocity().z)
	if actual_horizontal.length_squared() > 0.0001:
		facing_world = actual_horizontal.normalized()
	facing_index = direction_sector(facing_world, view_basis)

static func horizontal_forward(view_basis: Basis) -> Vector3:
	var forward := -view_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		var right := view_basis.x
		right.y = 0.0
		forward = Vector3.UP.cross(right)
	return forward.normalized()

static func input_to_world(input_vector: Vector2, view_basis: Basis) -> Vector3:
	var forward := horizontal_forward(view_basis)
	var right := view_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.000001 else forward.cross(Vector3.UP)
	var bounded := input_vector.limit_length()
	return right * bounded.x - forward * bounded.y

static func direction_sector(direction: Vector3, view_basis: Basis, sector_count: int = 8) -> int:
	var forward := horizontal_forward(view_basis)
	var screen_direction := Vector2(direction.dot(forward.cross(Vector3.UP)), -direction.dot(forward))
	return posmod(roundi(atan2(screen_direction.x, screen_direction.y) / (TAU / sector_count)), sector_count)
