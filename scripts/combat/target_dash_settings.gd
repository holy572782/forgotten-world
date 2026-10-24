extends Resource
## M06 provisional values; stock and combo balance belong to M07.
@export_range(0.5, 3.0) var stop_distance: float = 1.1
@export_range(0.001, 0.1) var floor_tolerance: float = 0.04
@export_range(0.05, 0.3) var path_sample_spacing: float = 0.15
## Maximum native contact recovery, not a capsule size or collision exclusion.
@export_range(0.0, 0.005, 0.0001) var contact_recovery_limit: float = 0.002
@export_range(0.5, 5.0) var attack_timeout: float = 2.0
@export_category("M07 aiming prototype")
## Screen-space half angle for right-click assistance; direct clicks take priority.
@export_range(0.0, 90.0) var directional_click_tolerance_degrees: float = 20.0
@export_range(1.0, 180.0) var auto_aim_half_angle_degrees: float = 60.0
@export_range(0.0, 2.0) var auto_aim_distance_hysteresis: float = 0.3
@export_range(0.0, 0.2) var auto_aim_distance_tie: float = 0.05
@export_range(0.0, 90.0) var aim_hysteresis_degrees: float = 12.0
@export_range(0.0, 1.0) var aim_stability_seconds: float = 0.12
@export_range(1.0, 180.0) var manual_aim_release_degrees: float = 35.0
@export_range(0.0, 0.2) var screen_margin: float = 0.03
