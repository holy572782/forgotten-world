extends Resource
## Configuration only; timers and anchors belong to each enemy.
enum Kind { DASH_MELEE, STATIONARY_MELEE, PROJECTILE }
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
@export var hit_height_tolerance := 1.0
@export var damage := 10.0
@export var return_seconds := 0.35
@export var recovery_seconds := 1.2
@export var minimum_attack_interval := 2.1
@export var movement_hold_timeout := 0.45
@export var projectile_speed := 3.0
@export var projectile_radius := 0.2
@export var projectile_lifetime := 6.0
@export var projectile_range := 18.0
@export var maximum_projectiles := 1
