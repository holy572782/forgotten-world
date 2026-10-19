class_name WeaponData
extends Resource
## Provisional weapon balance. Runtime combo progress never lives here.
@export var weapon_id: StringName = &"one_handed_sword"
@export var display_name: String = "片手剣"
@export_range(1, 99) var max_combo_hits: int = 3
@export_range(1.0, 100.0) var base_damage: float = 10.0
@export_range(0.5, 20.0) var attack_range: float = 5.0
@export_range(0.0, 2.0) var combo_input_window: float = 0.5
@export_range(1, 99) var stock_cost_per_hit: int = 1
@export_range(0.1, 2.0) var attack_duration: float = 0.32
@export_range(0.0, 1.0) var combo_stance_duration: float = 0.12
@export_range(0.1, 5.0) var attack_speed_multiplier: float = 1.0
## Reserved: M07 repeats the existing animation for all strikes.
@export var animation_profile: Resource
