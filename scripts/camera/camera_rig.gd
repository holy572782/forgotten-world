extends Node3D
## Physics follow/orbit; player and camera share automatic render interpolation.
const CameraSettings = preload("res://scripts/camera/camera_settings.gd")
@export var settings: CameraSettings = preload("res://resources/camera_settings.tres")
@export var target: Node3D
@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var _last_target_position := Vector3.ZERO

func _ready() -> void:
	# Player (0), map recovery (1), follow (2), spring collision (3).
	process_physics_priority = 2
	arm.process_physics_priority = 3
	arm.rotation.x = deg_to_rad(settings.pitch_angle)
	arm.spring_length = settings.camera_distance
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap_to_target()

func _physics_process(delta: float) -> void:
	rotation.y = wrapf(rotation.y - Input.get_axis("camera_left", "camera_right") * deg_to_rad(settings.rotation_speed) * delta, -PI, PI)
	if not is_instance_valid(target):
		return
	if target.global_position.distance_to(_last_target_position) > settings.teleport_distance:
		snap_to_target()
	else:
		global_position = global_position.lerp(target.global_position + settings.target_offset, 1.0 - exp(-settings.follow_smoothing * delta))
	_last_target_position = target.global_position

func snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	global_position = target.global_position + settings.target_offset
	_last_target_position = target.global_position
	reset_physics_interpolation()
	# SpringArm updates the camera distance later in this same physics tick.
	camera.reset_physics_interpolation.call_deferred()
