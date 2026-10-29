extends Resource
## Configuration only; timers and anchors belong to each enemy.
const DamageTypes = preload("res://scripts/combat/damage_types.gd")
const MagicVisual = preload("res://scripts/effects/magic_visual_settings.gd")
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
enum Kind { DASH_MELEE, STATIONARY_MELEE, PROJECTILE }
## Optional shared player weapon profile; null preserves legacy/ranged attacks.
@export var weapon: WeaponData
@export var travel_settings: Resource
@export var kind: Kind = Kind.DASH_MELEE
@export var windup_seconds := 0.9
@export var dash_max_distance := 1.5
@export var dash_seconds := 0.25
@export var stop_distance := 0.9
@export var attack_seconds := 0.15
@export var hit_delay_seconds := 0.05
@export var hit_radius := 1.4
@export var hit_half_angle_degrees := 45.0
@export var hit_yaw_degrees := 0.0 # Hit sector offset only; never changes the straight route.
## Enemy-only override; the shared player weapon is never edited.
@export var override_weapon_hit_height := false
@export_range(0.01, 10.0, 0.01) var hit_height_tolerance := 1.0
## Ground search depth is independent of whether the blade can reach airborne feet.
@export_range(0.1, 10.0, 0.1) var target_ground_probe_depth := 2.0
@export var damage := 10.0
@export var damage_kind: DamageTypes.Kind = DamageTypes.Kind.PHYSICAL
## Optional presentation only: physical arrows need not look like fire.
@export var magic_visual: MagicVisual
@export var return_seconds := 0.35
@export var recovery_seconds := 1.2
@export var minimum_attack_interval := 2.1
@export var movement_hold_timeout := 0.45
@export var projectile_speed := 3.0
@export var projectile_radius := 0.2
@export var projectile_lifetime := 6.0
@export var projectile_range := 18.0
@export var maximum_projectiles := 1

func snapshot() -> Resource:
	var result := duplicate(true)
	if weapon == null: return result
	result.weapon = weapon.duplicate() # External Resources remain shared by duplicate(true).
	result.kind = Kind.DASH_MELEE
	var motion := (weapon.motion if weapon.motion != null else Motion.new()).snapshot()
	result.weapon.motion = motion
	result.attack_seconds = weapon.swing_duration()
	result.hit_radius = weapon.melee_reach
	result.hit_half_angle_degrees = weapon.sweep_angle_degrees * 0.5
	result.hit_yaw_degrees = 0.0
	result.hit_height_tolerance = Motion.bounded(hit_height_tolerance,0.01,10.0,1.0) if override_weapon_hit_height else weapon.hit_height_tolerance
	result.weapon.hit_height_tolerance = result.hit_height_tolerance
	result.dash_max_distance = weapon.attack_range
	if travel_settings != null: result.stop_distance = minf(travel_settings.stop_distance, weapon.melee_reach)
	var visual := weapon.attack_visual
	if visual != null and visual.is_valid():
		var weights := Motion.weights(visual.attack_frames, &"attack_down", motion.frame_time_ratios)
		result.hit_delay_seconds = result.attack_seconds * Motion.phase_at(weights, clampi(motion.hit_frame, 0, weights.size()-1), motion.hit_frame_percent/100.0)
	return result
