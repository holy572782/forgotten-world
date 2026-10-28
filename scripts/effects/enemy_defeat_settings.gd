extends Resource
## Per-enemy presentation selection; no HP/damage/AI timing lives here.
enum Mode { NONE, SCENE }
@export var mode: Mode = Mode.SCENE
@export var scene: PackedScene = preload("res://scenes/effects/enemy_flyoff.tscn")
## Minimum world-equivalent speed. Screen edge distance may require a faster flight.
@export_range(1.0, 60.0, 0.5) var minimum_fly_speed := 18.0
## First hop height; later hops use the smaller scale and decay below.
@export_range(0.0, 3.0, 0.05) var lift_height := 0.9
## Target time to reach the real viewport edge; high minimum speed can exit sooner.
@export_range(0.2, 1.5, 0.01) var flyoff_duration := 0.65
@export_range(0.8, 5.0, 0.1) var maximum_lifetime := 2.5
@export_range(0.0, 128.0, 1.0) var offscreen_margin_pixels := 24.0

@export_group("Bounces after the first hop")
@export_range(0, 4, 1) var bounce_count := 2
@export_range(0.0, 1.0, 0.01) var secondary_bounce_scale := 0.45
@export_range(0.0, 0.95, 0.01) var bounce_decay := 0.55
@export_group("Defeat sound")
@export var defeat_sound: AudioStream
@export_range(-60.0, 0.0, 0.1) var defeat_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var defeat_pitch_scale := 0.5
