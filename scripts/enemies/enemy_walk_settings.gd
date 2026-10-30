extends Resource
## Normal locomotion only. Never relaxes DashPath's attack travel contract.
@export_range(1.0, 60.0, 1.0) var max_slope_degrees := 45.0
@export_range(0.05, 1.2, 0.05) var maximum_step_up := 1.05
@export_range(0.05, 1.2, 0.05) var maximum_step_down := 1.05
@export_range(0.5, 8.0, 0.1) var climb_speed := 3.5
@export_range(1.0, 50.0, 0.5) var gravity := 20.0
@export_range(0.01, 0.3, 0.01) var snap_length := 0.12
@export_range(0.1, 2.0, 0.05) var blocked_retry_seconds := 0.5
## Only bridge tiny map seams with opposing walkable supports; never a cliff.
@export_range(0.0, 0.2, 0.01) var floor_seam_tolerance := 0.15

@export_group("Automatic terrain jump")
@export var jump_enabled := true
@export_range(0.1, 0.4, 0.01) var walking_step_height := 0.3
@export_range(0.4, 1.5, 0.01) var jump_height := 1.1
## Height sets the apex; takeoff speed sets the tempo. Gravity is derived.
@export_range(2.0, 12.0, 0.01) var jump_takeoff_speed := 6.63
@export_range(0.5, 6.0, 0.1) var jump_horizontal_speed := 3.0
@export_range(0.1, 3.0, 0.05) var jump_cooldown_seconds := 0.8
