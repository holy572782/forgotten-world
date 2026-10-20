extends Node3D
## Follow/orbit plus selectable visibility/safety policy. Values are prototypes.
const CameraSettings = preload("res://scripts/camera/camera_settings.gd")
const Fader = preload("res://scripts/camera/occlusion_fader.gd")
const Safety = preload("res://scripts/camera/camera_collision.gd")
@export var settings: CameraSettings = preload("res://resources/camera_settings.tres")
@export var target: Node3D
@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var fader := Fader.new()
var safety := Safety.new()
var safety_failed := false
var _last_target_position := Vector3.ZERO
var _mode := -1
var _reset_eye := true
var _excluded: Array[RID] = []
var _normal_cull_mask: int
var follow_locked := false
var follow_anchor := Vector3.ZERO
var _resuming_follow := false

func hold_follow() -> void:
	if follow_locked: return
	follow_anchor = global_position
	follow_locked = true
	_resuming_follow = false

func release_follow() -> void:
	if not follow_locked: return
	follow_locked = false
	_resuming_follow = true
	if is_instance_valid(target): _last_target_position = target.global_position

func frames_points(points: Array[Vector3], margin: float) -> bool:
	if safety_failed: return false
	var size := camera.get_viewport().get_visible_rect().size
	var bounds := Rect2(size * margin, size * (1.0 - 2.0 * margin))
	for point in points:
		if camera.is_position_behind(point) or not bounds.has_point(camera.unproject_position(point)):
			return false
	return true

func _ready() -> void:
	process_physics_priority = 2
	arm.process_physics_priority = 3
	arm.rotation.x = deg_to_rad(settings.pitch_angle)
	arm.spring_length = settings.camera_distance
	_normal_cull_mask = camera.cull_mask
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
		_excluded.append(target.get_rid())
	_apply_mode()
	snap_to_target()

func _apply_mode() -> void:
	if _mode == settings.occlusion_mode: return
	fader.restore_all()
	_mode = settings.occlusion_mode
	# B replaces the arm's full sightline sweep with camera-volume overlap/sweep queries.
	# The native arm remains available, unchanged, for the A comparison.
	arm.set_physics_process_internal(_mode == 0)
	camera.top_level = _mode == 1
	camera.cull_mask = _normal_cull_mask
	safety_failed = false
	if _mode == 0:
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, settings.camera_distance))
	_reset_eye = true
	camera.reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	_apply_mode()
	rotation.y = wrapf(rotation.y - Input.get_axis("camera_left", "camera_right") * deg_to_rad(settings.rotation_speed) * delta, -PI, PI)
	if not is_instance_valid(target):
		fader.restore_all()
		return
	if follow_locked:
		global_position = follow_anchor
	elif not _resuming_follow and target.global_position.distance_to(_last_target_position) > settings.teleport_distance:
		snap_to_target()
	else:
		global_position = global_position.lerp(target.global_position + settings.target_offset, 1.0 - exp(-settings.follow_smoothing * delta))
		if global_position.distance_to(target.global_position + settings.target_offset) < 0.01:
			_resuming_follow = false
	_last_target_position = target.global_position
	if _mode == 1: _update_eye(delta)

func _update_eye(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var desired := arm.global_position + arm.global_basis.z * settings.camera_distance
	var safe := safety.solve(space, desired, camera.global_position, arm.global_basis, settings, _excluded, _reset_eye, delta)
	if safety.failed and not safety_failed:
		push_warning("Camera safety: no clear eye position found; rendering suppressed until recovery.")
	safety_failed = safety.failed
	camera.cull_mask = 0 if safety_failed else _normal_cull_mask
	if not safety_failed:
		camera.global_transform = Transform3D(arm.global_basis, safe)
		if safety.discontinuity: camera.reset_physics_interpolation()
		fader.update(space, safe, target.global_position, settings, _excluded, delta)
	else:
		fader.restore_all()
	_reset_eye = safety_failed

func snap_to_target() -> void:
	if not is_instance_valid(target): return
	follow_locked = false
	_resuming_follow = false
	global_position = target.global_position + settings.target_offset
	_last_target_position = target.global_position
	_reset_eye = true
	reset_physics_interpolation()
	camera.reset_physics_interpolation.call_deferred()

func _exit_tree() -> void:
	fader.restore_all()
