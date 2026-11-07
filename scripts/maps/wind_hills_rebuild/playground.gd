extends Node3D
## Only stage-01 entrance rehearsal. Full-map traversal/recovery is stage 02.
func _ready() -> void:
	process_physics_priority = 1
	$Player.reset_motion($Field/PlayerSpawn.global_position)
	$Player.movement_camera = $CameraRig.camera
	$CameraRig.snap_to_target()

func _physics_process(_delta: float) -> void:
	var p: Vector3 = $Field.to_local($Player.global_position)
	if p.x < -28 or p.x > -2 or p.z < -8 or p.z > 20 or p.y < -2:
		$Player.reset_motion($Field/PlayerSpawn.global_position)
		$CameraRig.snap_to_target()
