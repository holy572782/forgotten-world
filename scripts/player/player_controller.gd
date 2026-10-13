extends CharacterBody3D
## M02 locomotion only. Body origin is the contact point beneath the capsule.

const MovementSettings = preload("res://scripts/player/player_movement.gd")

@export var movement: MovementSettings = preload("res://resources/player_movement.tres")
@export var movement_camera: Camera3D

var facing_world := Vector3.BACK
## Screen-relative sectors: down, down-right, right, up-right, up, up-left, left, down-left.
## Reserved for directional animation; M02 intentionally uses one placeholder frame.
var facing_index: int = 0

func _ready() -> void:
	floor_max_angle = deg_to_rad(movement.max_slope_degrees)
	floor_snap_length = movement.snap_length
	floor_constant_speed = true
	floor_stop_on_slope = true

func _physics_process(delta: float) -> void:
	var camera := movement_camera
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	var view_basis := camera.global_basis if is_instance_valid(camera) else Basis.IDENTITY
	# get_vector applies the InputMap radial deadzone, caps diagonals and retains analog strength.
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var desired := input_to_world(input_vector, view_basis) * movement.speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := movement.deceleration if input_vector.is_zero_approx() else movement.acceleration
	if not is_on_floor():
		rate *= movement.air_control
	horizontal = horizontal.move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= movement.gravity * delta
	move_and_slide()
	var actual_horizontal := Vector3(get_real_velocity().x, 0.0, get_real_velocity().z)
	if actual_horizontal.length_squared() > 0.0001:
		facing_world = actual_horizontal.normalized()
	facing_index = direction_sector(facing_world, view_basis)

static func horizontal_forward(view_basis: Basis) -> Vector3:
	var forward := -view_basis.z
	forward.y = 0.0
	# A vertical camera has no projected forward: derive it from its right axis.
	if forward.length_squared() < 0.000001:
		var right := view_basis.x
		right.y = 0.0
		forward = Vector3.UP.cross(right)
	return forward.normalized()

static func input_to_world(input_vector: Vector2, view_basis: Basis) -> Vector3:
	var forward := horizontal_forward(view_basis)
	var right := forward.cross(Vector3.UP)
	var bounded := input_vector.limit_length()
	return right * bounded.x - forward * bounded.y

static func direction_sector(direction: Vector3, view_basis: Basis) -> int:
	var forward := horizontal_forward(view_basis)
	var screen_direction := Vector2(direction.dot(forward.cross(Vector3.UP)), -direction.dot(forward))
	return posmod(roundi(atan2(screen_direction.x, screen_direction.y) / (PI / 4.0)), 8)
