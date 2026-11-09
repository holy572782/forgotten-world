extends Node3D
## Temporary, field-local history. All distances inside the field are in authoring units.
const SAMPLE_PERIOD := 0.25
const RIM_MARGIN := 2.8
const BANK_RANGE := 25.0
const NO_STAND := Vector3.INF
@onready var field: Node3D = $Field
@onready var player: CharacterBody3D = $Player
@onready var capsule: CollisionShape3D = $Player/CollisionShape3D
@onready var bridge: Vector3 = field.vec(field.layout.landmarks.D_bridge)
var safe_points: Array[Vector3] = []
var last_safe: Vector3
var last_bank := NO_STAND
var bridge_entry := NO_STAND
var recovery_count := 0
var last_recovery := ""
var _history: Array[Vector3] = []
var _last_inspected := NO_STAND
var _grounded_time := 0.0
var _checked_anchors := false
var _body_query := PhysicsShapeQueryParameters3D.new()
var measure_cost := false
var recovery_usec := 0
var recovery_ticks := 0
var safety_queries := 0
var max_tick_usec := 0

func _ready() -> void:
	process_physics_priority = 1
	_body_query.shape = capsule.shape
	_body_query.collision_mask = player.collision_mask
	_body_query.exclude = [player.get_rid()]
	last_safe = field.get_node("PlayerSpawn").global_position
	player.reset_motion(last_safe)
	player.movement_camera = $CameraRig.camera
	$CameraRig.snap_to_target()

func _find_anchors() -> void:
	var candidates: Array[Vector3] = [field.to_local(last_safe)]
	for id in ["B_middle", "C_overlook", "E_summit"]:
		candidates.append(field.vec(field.layout.landmarks[id]))
	var river_route: Array = field.routes[2].points
	for i in [3,6,river_route.size()-1]:
		candidates.append(river_route[i])
	for local in candidates:
		var stand := _safe_stand(field.to_global(local))
		if stand.is_finite(): safe_points.append(stand)
	_checked_anchors = true

func _on_bridge(p: Vector3) -> bool:
	return absf(p.x-bridge.x)<=11.5 and absf(p.z-bridge.z)<=2.75 and p.y>=bridge.y-0.6

func _safe_stand(world: Vector3) -> Vector3:
	var p := field.to_local(world)
	var cfg: Dictionary = field.layout.terrain
	if p.x<cfg.min_x+RIM_MARGIN or p.x>cfg.max_x-RIM_MARGIN or p.z<cfg.min_z+RIM_MARGIN or p.z>cfg.max_z-RIM_MARGIN:
		return NO_STAND
	var river: Dictionary = field.channel.sample(p.x,p.z)
	if _on_bridge(p) or river.distance<field.water_width(river.center_z)*0.5+2.0: return NO_STAND
	var floor_y: float = field.surface_height(p.x,p.z)
	if absf(floor_y-p.y)>1.2: return NO_STAND
	# The visible heightfield and collider use the same triangles. Check the landing
	# footprint for a ledge before paying for an actual support and clearance query.
	for offset: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var height: float = field.surface_height(p.x+offset.x*1.6,p.z+offset.y*1.6)
		if absf(height-floor_y)>1.08: return NO_STAND
	p.y = floor_y
	var floor_point := field.to_global(p)
	var ray := PhysicsRayQueryParameters3D.create(floor_point+Vector3.UP*0.35,floor_point-Vector3.UP*0.35,player.collision_mask,[player.get_rid()])
	var space := get_world_3d().direct_space_state
	safety_queries += 1
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(35.0)): return NO_STAND
	var stand: Vector3 = hit.position+Vector3.UP*0.12
	_body_query.transform = Transform3D(capsule.global_basis,stand+capsule.position)
	safety_queries += 1
	if not space.intersect_shape(_body_query,1).is_empty(): return NO_STAND
	return stand

func _remember(stand: Vector3) -> void:
	last_safe = stand
	if _history.is_empty() or _history.front().distance_squared_to(stand)>0.5:
		_history.push_front(stand)
		if _history.size()>8: _history.pop_back()

func _record_floor(p: Vector3, river: Dictionary, delta: float) -> void:
	if not player.is_on_floor() or player.combat.is_busy():
		_grounded_time = 0.0
		return
	if _on_bridge(p):
		if not bridge_entry.is_finite() and last_bank.distance_squared_to(player.global_position)<24.0*24.0:
			bridge_entry = last_bank
		_grounded_time = 0.0
		return
	_grounded_time += delta
	if _grounded_time<SAMPLE_PERIOD: return
	_grounded_time = 0.0
	if _last_inspected.distance_squared_to(player.global_position)<0.7*0.7: return
	_last_inspected = player.global_position
	var stand := _safe_stand(player.global_position)
	if not stand.is_finite(): return
	_remember(stand)
	bridge_entry = NO_STAND
	if river.distance<BANK_RANGE: last_bank = stand

func _select_stand(p: Vector3, river: Dictionary, reason: String) -> Vector3:
	var candidates: Array[Vector3] = []
	if reason=="river":
		if bridge_entry.distance_squared_to(player.global_position)<24.0*24.0: candidates.append(bridge_entry)
		if last_bank.distance_squared_to(player.global_position)<20.0*20.0:
			candidates.append(last_bank)
		# Search beside the incident on the approach side, along and away from water.
		var side := signf(river.offset_x)
		if side==0: side = -1.0
		for along in [0.0,-4.0,4.0]:
			for across in [8.0,12.0,18.0]:
				var x: float = p.x-river.offset_x+side*across
				var z: float = river.center_z+along
				candidates.append(field.to_global(Vector3(x,field.surface_height(x,z),z)))
	candidates.append_array(_history)
	# Deterministic fallback to the nearest supported landmark.
	var anchors := safe_points.duplicate()
	anchors.sort_custom(func(a: Vector3,b: Vector3): return a.distance_squared_to(player.global_position)<b.distance_squared_to(player.global_position))
	candidates.append_array(anchors)
	for candidate in candidates:
		var stand := _safe_stand(candidate)
		if stand.is_finite(): return stand
	return NO_STAND

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec() if measure_cost else 0
	_update_recovery(delta)
	if measure_cost:
		var elapsed := Time.get_ticks_usec()-started
		recovery_usec += elapsed
		recovery_ticks += 1
		max_tick_usec = maxi(elapsed,max_tick_usec)

func _update_recovery(delta: float) -> void:
	if not _checked_anchors: _find_anchors()
	var p := field.to_local(player.global_position)
	var cfg: Dictionary = field.layout.terrain
	var reason := ""
	var river: Dictionary = {}
	if p.x<cfg.min_x-2 or p.x>cfg.max_x+2 or p.z<cfg.min_z-2 or p.z>cfg.max_z+2:
		reason = "boundary"
	elif p.y < -60:
		reason = "fall"
	elif p.x>=cfg.min_x and p.x<cfg.max_x and p.z>=cfg.min_z and p.z<cfg.max_z:
		river = field.channel.sample(p.x,p.z)
		if river.distance<field.water_width(river.center_z)*0.5 and p.y<river.height-0.12:
			reason = "river"
		elif p.y<field.surface_height(p.x,p.z)-2.0:
			reason = "below terrain"
		else:
			_record_floor(p,river,delta)
	if reason.is_empty(): return
	var stand := _select_stand(p,river,reason)
	if not stand.is_finite(): return
	last_recovery = reason
	recovery_count += 1
	_history.clear()
	_remember(stand)
	bridge_entry = NO_STAND
	last_bank = stand if reason=="river" else NO_STAND
	_last_inspected = NO_STAND
	_grounded_time = 0.0
	player.reset_motion(stand)
	$CameraRig.snap_to_target()
