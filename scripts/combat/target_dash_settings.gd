extends Resource
## M06 provisional values; stock and combo balance belong to M07.
@export_range(0.1, 40.0) var approach_speed: float = 12.0
@export_range(0.1, 40.0) var return_speed: float = 10.0
@export_range(0.05, 2.0) var minimum_travel_time: float = 0.25
@export_range(0.05, 2.0) var maximum_travel_time: float = 0.4
@export_range(0.5, 3.0) var stop_distance: float = 1.1
@export_range(0, 2) var hit_frame: int = 1
@export_range(0.001, 0.1) var floor_tolerance: float = 0.04
@export_range(0.05, 0.3) var path_sample_spacing: float = 0.15
@export_range(0.5, 5.0) var attack_timeout: float = 2.0
@export_category("M07 aiming prototype")
@export_range(0.0, 90.0) var aim_hysteresis_degrees: float = 12.0
@export_range(0.0, 1.0) var aim_stability_seconds: float = 0.12
@export_range(1.0, 180.0) var manual_aim_release_degrees: float = 35.0
@export_range(0.0, 0.2) var screen_margin: float = 0.03
