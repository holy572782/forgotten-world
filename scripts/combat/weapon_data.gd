class_name WeaponData
extends Resource
const MotionSettings = preload("res://scripts/combat/attack_motion_settings.gd")
const FeedbackSettings = preload("res://scripts/combat/combat_feedback_settings.gd")
## Provisional weapon balance. Runtime combo progress never lives here.
enum HitShape { SINGLE_TARGET, SWEEP }
@export var weapon_id: StringName = &"one_handed_sword"
@export var display_name: String = "片手剣"
@export_range(1, 99) var max_combo_hits: int = 3
@export_range(1.0, 100.0) var base_damage: float = 10.0
@export_range(0.5, 20.0) var attack_range: float = 5.0
## attack_range is the dash/chain radius; these describe the local strike.
@export var hit_shape: HitShape = HitShape.SINGLE_TARGET
@export_range(0.1, 5.0) var melee_reach: float = 1.4
@export_range(1.0, 180.0) var sweep_angle_degrees: float = 100.0
@export_range(0.01, 2.0) var hit_height_tolerance: float = 0.3
@export var attack_visual: WeaponAttackVisualData
@export var feedback: FeedbackSettings = preload("res://resources/combat_feedback.tres")
@export var motion: MotionSettings = preload("res://resources/weapons/default_attack_motion.tres")
@export_range(0.0, 2.0) var combo_input_window: float = 0.5
@export_range(1, 99) var stock_cost_per_hit: int = 1
@export_range(0.1, 2.0) var attack_duration: float = 0.32
@export_range(0.0, 1.0) var combo_stance_duration: float = 0.12
@export_range(0.1, 5.0) var attack_speed_multiplier: float = 1.0

func swing_duration() -> float:
	return MotionSettings.bounded(attack_duration, 0.1, 2.0, 0.32) / MotionSettings.bounded(attack_speed_multiplier, 0.1, 5.0, 1.0)
