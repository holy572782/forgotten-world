extends Resource
## All values are provisional M09 practice balance, not final enemy design.
const AttackData = preload("res://scripts/enemies/enemy_attack_data.gd")
const PathSettings = preload("res://scripts/combat/dash_path_settings.gd")
const Visual = preload("res://scripts/enemies/enemy_visual_data.gd")
@export var visual: Visual
@export var attack: AttackData = preload("res://resources/enemies/melee_attack.tres")
@export var path: PathSettings = PathSettings.new()
@export var detection_radius := 7.0
@export var attack_start_distance := 1.8
@export var chase_speed := 2.0
@export var leash_radius := 9.0
@export var sight_loss_seconds := 0.5
@export_group("Attack warning presentation")
@export var attack_warning_flash_enabled := true
@export var attack_warning_flash_color := Color(1.0, 0.15, 0.1, 1.0)
@export_range(1, 8, 1) var attack_warning_flash_count := 2
@export_range(0.0, 1.0, 0.01) var attack_warning_flash_strength := 0.75
@export var attack_range_indicator_enabled := false
