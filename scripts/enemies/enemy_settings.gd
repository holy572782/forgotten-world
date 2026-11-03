extends Resource
## All values are provisional M09 practice balance, not final enemy design.
const WalkSettings = preload("res://scripts/enemies/enemy_walk_settings.gd")
@export var walk: WalkSettings = WalkSettings.new()
const AttackData = preload("res://scripts/enemies/enemy_attack_data.gd")
const PathSettings = preload("res://scripts/combat/dash_path_settings.gd")
const Defeat = preload("res://scripts/effects/enemy_defeat_settings.gd")
const Visual = preload("res://scripts/enemies/enemy_visual_data.gd")
@export var visual: Visual
@export var defeat: Defeat
@export var attack: AttackData = preload("res://resources/enemies/melee_attack.tres")
@export var path: PathSettings = PathSettings.new()
@export_range(0.1, 30.0, 0.1) var detection_radius := 5.0
@export_range(1.0, 360.0, 1.0) var horizontal_field_of_view_degrees := 120.0
@export_range(1.0, 180.0, 1.0) var vertical_field_of_view_degrees := 80.0
@export var attack_start_distance := 1.8
@export var chase_speed := 2.0
## Projectile-only hysteresis; does not change the 6m attack eligibility.
@export_range(0.0, 1.0, 0.01) var ranged_stop_margin := 0.2
@export var leash_radius := 9.0
@export_storage var sight_loss_seconds := 1.75 # ADR-059 saved-resource compatibility; no longer a deadline.
@export_range(0.1, 2.0, 0.05) var leash_reentry_margin := 0.3
@export_group("Lost target search")
## One deadline measured from the last actual sighting, including travel.
@export_range(0.1, 20.0, 0.1) var lost_target_timeout_seconds := 5.0
@export_range(0.0, 4.0, 0.1) var search_radius := 2.0
@export_storage var search_duration_seconds := 2.0 # Legacy serialized fields, not active timers.
@export_storage var search_travel_timeout_seconds := 8.0
@export_group("Attack warning presentation")
@export var attack_warning_flash_enabled := true
@export var attack_warning_flash_color := Color(1.0, 0.15, 0.1, 1.0)
@export_range(1, 8, 1) var attack_warning_flash_count := 2
@export_range(0.08, 1.0, 0.01) var attack_warning_flash_interval := 0.09
@export_range(0.0, 1.0, 0.01) var attack_warning_flash_strength := 0.75
@export var attack_range_indicator_enabled := false
@export_group("Attack warning sound")
@export var attack_warning_sound_enabled := true
@export var attack_warning_sound: AudioStream
@export_range(-60.0, 0.0, 0.1) var attack_warning_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var attack_warning_pitch_scale := 1.0
@export_group("Post-attack pursuit")
@export var pursuit_enabled := false
## Shared walk speed for range-closing pursuit and post-return local movement.
@export_range(0.1, 10.0, 0.1) var pursuit_speed := 2.0
@export_range(0.5, 20.0, 0.1) var preferred_attack_distance := 5.0
## Also the maximum goal distance of each local combat movement interval.
@export_range(0.1, 3.0, 0.1) var pursuit_step_distance := 1.0

@export_group("Aim commitment")
## Kept for old saved Resources; EnemyAttackData.aim_lock_ratio owns aim timing.
@export var track_windup_target := false
## Melee: lock to damage including travel; projectile: lock to release.
@export_range(0.1, 1.5, 0.01) var aim_commit_minimum_seconds := 0.45
## Legacy saved setting; fixed-target jobs now finish or cancel without re-aiming.
@export_range(0.0, 0.3, 0.01) var windup_replan_grace_seconds := 0.12
@export_group("Post-return combat movement")
## Uses existing pursuit_speed / pursuit_step_distance / preferred_attack_distance.
@export var combat_movement_enabled := false
@export_range(0.2, 3.0, 0.05) var combat_direction_interval := 0.7
@export_range(0.05, 2.0, 0.05) var combat_wait_seconds := 0.2
@export_range(0, 8, 1) var combat_strafe_weight := 2
@export_range(0, 8, 1) var combat_approach_weight := 1
@export_range(0, 8, 1) var combat_retreat_weight := 1
@export_range(0, 8, 1) var combat_wait_weight := 1
