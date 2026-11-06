extends Node3D
## Only scene wiring and map-specific recovery; production motion stays unchanged.
var recovery_count := 0
var last_recovery := ""

func _ready() -> void:
	process_physics_priority = 1
	$Player.reset_motion($WindHills/PlayerSpawn.global_position)
	$Player.movement_camera = $CameraRig.camera
	$CameraRig.snap_to_target()

func recovery_reason(p: Vector3) -> String:
	if p.x < -129 or p.x > 129 or p.z < -259 or p.z > 39 or p.y < -25: return "outer boundary"
	if p.y < -16: return "lower valley"
	var river_x := 95.0+5.0*sin((p.z+65.0)*0.035)
	if p.z > -154 and p.z < 12 and absf(p.x-river_x)<4.5 and p.y < -11.1: return "river"
	# Lower basins beneath each traversable terrace are fall-recovery regions.
	var road: Dictionary = $WindHills.route_sample(p.x,p.z)
	if road.distance < 15 and p.y < road.height-7.0: return "terrace fall"
	return ""

func _physics_process(_delta: float) -> void:
	var reason := recovery_reason($Player.global_position)
	if reason.is_empty(): return
	recover(reason)

func recover(reason: String) -> void:
	last_recovery = reason
	recovery_count += 1
	$Player.reset_motion($WindHills/PlayerSpawn.global_position)
	$CameraRig.snap_to_target()
