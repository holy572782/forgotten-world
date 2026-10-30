extends Resource
## Weapon-specific travel, independent of strike height and ordinary locomotion.
@export var enabled:=true
@export_range(0.0,1.1,0.01) var maximum_ascent:=1.0
@export_range(0.0,1.1,0.01) var maximum_descent:=1.1
@export_range(0.1,1.1,0.01) var apex_height:=1.1
@export_range(0.05,0.5,0.01) var minimum_hop_height:=0.18
@export_range(1.0,40.0,0.1) var gravity:=20.0
