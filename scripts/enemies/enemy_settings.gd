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
