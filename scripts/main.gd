extends Node3D
## Test-map wiring and fall recovery only; no persistence or death system.

@export var fall_reset_height: float = -10.0 # Provisional map-only threshold.

func _ready() -> void:
	# Run after the player so recovery clears the entire completed tick's motion.
	process_physics_priority = 1
	$Player.reset_motion($TestArena/PlayerSpawn.global_position)
	$Player.movement_camera = $CameraRig.camera
	$CameraRig.snap_to_target()
	$TestArena/Preview/Instructions/Label.text = "M04 | FOLLOW / ORBIT CAMERA\nWASD / Left stick: move | Space / South button: jump\nQ / E / Right stick: orbit | W: screen forward\nBlue: ramp | Gray: wall | Orange: steps | F8: stop"

func _physics_process(_delta: float) -> void:
	if $Player.global_position.y < fall_reset_height:
		$Player.reset_motion($TestArena/PlayerSpawn.global_position)
		$CameraRig.snap_to_target()
