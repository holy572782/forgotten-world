extends Resource
## All values are provisional M09 practice balance, not final enemy design.
@export_enum("Melee", "Ranged") var attack_kind: int = 0
@export var detection_radius := 7.0
@export var attack_start_distance := 1.8
@export var hit_radius := 1.4
@export var hit_half_angle_degrees := 45.0
@export var hit_height_tolerance := 1.0
@export var windup_seconds := 0.9
@export var attack_seconds := 0.12
@export var recovery_seconds := 1.2
@export var minimum_attack_interval := 2.1
@export var damage := 10.0
@export var chase_speed := 2.0
@export var leash_radius := 9.0
@export var sight_loss_seconds := 0.5
@export var projectile_speed := 3.0
@export var projectile_radius := 0.2
@export var projectile_lifetime := 6.0
@export var projectile_range := 18.0
@export var maximum_projectiles := 1
