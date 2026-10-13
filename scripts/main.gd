extends Node3D
## Scene wiring only: retain the standalone M01 arena and its preview camera.

func _ready() -> void:
	$Player.global_position = $TestArena/PlayerSpawn.global_position
	$Player.movement_camera = $TestArena/Preview/Camera3D
	$TestArena/Preview/Instructions/Label.text = "M02 | MOVEMENT PROTOTYPE\nWASD / Arrows / Left stick: camera-relative move\nBlue: ramp | Gray: wall | Orange: blocked steps\nOpen edges: no respawn yet. Stop with F8 and restart with F5."
