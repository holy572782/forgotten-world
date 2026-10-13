extends Resource
## Provisional M04 tuning, not final balance values.
@export_range(-80.0, -10.0) var pitch_angle: float = -45.0
@export_range(1.0, 30.0) var camera_distance: float = 10.0
@export_range(0.0, 360.0) var rotation_speed: float = 100.0
@export_range(0.0, 30.0) var follow_smoothing: float = 8.0
@export var target_offset := Vector3(0, 0.9, 0)
@export_range(1.0, 100.0) var teleport_distance: float = 8.0
