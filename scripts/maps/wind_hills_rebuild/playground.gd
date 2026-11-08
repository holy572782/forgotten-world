extends Node3D
## Scene-local recovery. Only visited, physically supported locations become anchors.
@onready var field: Node3D = $Field
@onready var player: CharacterBody3D = $Player
var safe_points: Array[Vector3] = []
var last_safe: Vector3
var recovery_count := 0
var last_recovery := ""
var _checked_anchors := false

func _ready() -> void:
	process_physics_priority = 1
	last_safe = field.get_node("PlayerSpawn").global_position
	player.reset_motion(last_safe)
	player.movement_camera = $CameraRig.camera
	$CameraRig.snap_to_target()

func _find_anchors() -> void:
	var candidates: Array[Vector3] = [field.to_local(last_safe)]
	for id in ["B_middle", "C_overlook", "E_summit"]:
		candidates.append(field.vec(field.layout.landmarks[id]))
	var river_route: Array = field.routes[2].points
	candidates.append(river_route[3])
	candidates.append(river_route[6])
	candidates.append(river_route.back())
	var space := get_world_3d().direct_space_state
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	for local in candidates:
		var nominal: Vector3 = field.to_global(local)
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(nominal+Vector3.UP, nominal-Vector3.UP*1.5, player.collision_mask))
		if ground.is_empty() or ground.normal.y < cos(player.floor_max_angle):
			continue
		var stand: Vector3 = ground.position + Vector3.UP*0.12
		query.transform = Transform3D(Basis.IDENTITY, stand+capsule.position)
		if space.intersect_shape(query,1).is_empty():
			safe_points.append(stand)
	_checked_anchors = true

func _physics_process(_delta: float) -> void:
	if not _checked_anchors:
		_find_anchors()
	var p: Vector3 = field.to_local(player.global_position)
	var cfg: Dictionary = field.layout.terrain
	var reason := ""
	if p.x < cfg.min_x-2 or p.x > cfg.max_x+2 or p.z < cfg.min_z-2 or p.z > cfg.max_z+2:
		reason = "boundary"
	elif p.y < -60:
		reason = "fall"
	elif p.x >= cfg.min_x and p.x < cfg.max_x and p.z >= cfg.min_z and p.z < cfg.max_z:
		var river: Dictionary = field.channel.sample(p.x,p.z)
		if river.distance < field.water_width(river.center_z)*0.5 and p.y < river.height-0.12:
			reason = "river"
		elif p.y < field.surface_height(p.x,p.z)-2.0:
			reason = "below terrain"
	if not reason.is_empty():
		last_recovery = reason
		recovery_count += 1
		player.reset_motion(last_safe)
		$CameraRig.snap_to_target()
	elif player.is_on_floor() and not player.combat.is_busy():
		for anchor in safe_points:
			if player.global_position.distance_squared_to(anchor) < 2.5*2.5:
				last_safe = anchor
				break
