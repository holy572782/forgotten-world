extends Resource
## Provisional M04 tuning, not final balance values.
@export_range(-80.0, -10.0) var pitch_angle: float = -45.0
@export_range(1.0, 30.0) var camera_distance: float = 10.0
@export_range(0.0, 360.0) var rotation_speed: float = 100.0
@export_range(0.0, 30.0) var follow_smoothing: float = 8.0
@export var target_offset := Vector3(0, 0.9, 0)
@export_range(1.0, 100.0) var teleport_distance: float = 8.0

@export_category("M04 occlusion prototype (provisional)")
@export_enum("A: SpringArm shortening", "B: Distance and fade") var occlusion_mode: int = 1
@export_range(0.05, 0.95) var occluded_opacity: float = 0.3
@export_range(0.05, 1.0) var fade_time: float = 0.25
@export_range(0.0, 0.5) var occlusion_release_delay: float = 0.12
@export var occlusion_heights := PackedFloat32Array([0.15, 0.9, 1.65])
@export_range(1, 64) var max_occluders_per_ray: int = 16
@export_flags_3d_physics var terrain_mask: int = 1
@export_range(0.15, 1.0) var camera_radius: float = 0.25
@export_range(0.01, 0.2) var collision_margin: float = 0.05
@export_range(0.25, 3.0) var max_local_correction: float = 2.0
@export_range(1, 8) var correction_steps: int = 4
@export_range(1.0, 30.0) var correction_speed: float = 8.0
@export_range(1, 32) var emergency_steps: int = 16
@export_range(0.5, 8.0) var emergency_step_height: float = 2.0
