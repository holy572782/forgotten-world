extends Node3D
## M03 test-map wiring and fall recovery only; no persistence or death system.

@export var fall_reset_height: float = -10.0 # Provisional map-only threshold.

func _ready() -> void:
	# Run after the player so recovery clears the entire completed tick's motion.
	process_physics_priority = 1
	$Player.reset_motion($TestArena/PlayerSpawn.global_position)
	$Player.movement_camera = $TestArena/Preview/Camera3D
	$TestArena/Preview/Instructions/Label.text = "M03 | JUMP / FALL / LAND\nWASD / Arrows / Left stick: move | Space / South button: jump\nBlue: ramp | Gray: wall | Orange: jumpable steps\nOpen edges: return to spawn after falling. F8: stop."

func _physics_process(_delta: float) -> void:
	if $Player.global_position.y < fall_reset_height:
		$Player.reset_motion($TestArena/PlayerSpawn.global_position)
