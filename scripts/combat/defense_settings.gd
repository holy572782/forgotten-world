extends Resource
## M08 guard prototype. Direction return has no invulnerability (ADR-014).
@export_range(0.0, 1.0) var guard_damage_multiplier: float = 0.5
@export_range(0.0, 180.0) var guard_half_angle_degrees: float = 60.0
@export_range(0.01, 2.0) var followup_window: float = 0.5

@export_group("Block success sound")
@export var block_success_sound: AudioStream
@export_range(-60.0, 0.0) var block_success_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var block_success_pitch_scale := 1.0
