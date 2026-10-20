extends Resource
## M08 comparison values, all provisional; invulnerability defaults to A (off).
@export_range(0.0, 1.0) var guard_damage_multiplier: float = 0.5
@export_range(0.0, 180.0) var guard_half_angle_degrees: float = 60.0
@export_range(0.1, 4.0) var step_distance: float = 1.2
@export_range(0.02, 1.0) var step_duration: float = 0.18
@export_range(0.0, 1.0) var step_reinput_delay: float = 0.20
@export_range(0.01, 2.0) var followup_window: float = 0.5
@export var step_invulnerability_enabled: bool = false
@export_range(0.0, 1.0) var step_invulnerability_start: float = 0.03
@export_range(0.0, 1.0) var step_invulnerability_duration: float = 0.10
