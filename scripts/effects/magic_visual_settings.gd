extends Resource
## Visual dimensions never affect projectile_radius or damage.
@export_group("Casting circle")
@export var circle_enabled := true
## Native Effekseer effect; null retains the original procedural circle.
@export var circle_effect: EffekseerEffect
## Older XY-authored effects can still opt into the emitter conversion.
@export var circle_effect_is_floor := false
@export_range(0.2, 8.0, 0.1) var circle_diameter := 2.8
@export_range(0.01, 0.1, 0.005) var ground_offset := 0.035
@export_range(-1.0, 1.0, 0.01) var circle_rotation_speed := 0.25
@export var circle_color := Color(0.95, 0.12, 0.055, 1.0)
@export_range(0.0, 0.3, 0.01) var release_fade_seconds := 0.12
@export_group("Fireball")
@export_range(0.1, 5.0, 0.1) var fireball_diameter := 1.8
@export_range(8, 64, 1) var pixel_grid := 24
@export_range(0, 10, 1) var trail_count := 5
@export_range(0.0, 3.0, 0.05) var trail_length := 1.1
@export_group("Projectile launch sound")
@export var launch_sound: AudioStream
@export_range(-60.0, 0.0, 0.5) var launch_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var launch_pitch_scale := 1.0
@export_group("Fire hit")
@export var hit_effect: EffekseerEffect
@export_range(0.001, 1.0, 0.001) var hit_effect_scale := 0.06
@export var hit_sound: AudioStream
@export_range(-60.0, 0.0, 0.5) var hit_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var hit_pitch_scale := 1.0
