extends RefCounted
## Conservative M06 straight, level route. Slopes/steps require normal locomotion.
static func clear(body: CharacterBody3D, destination: Vector3, settings: Resource, from: Vector3) -> bool:
	if absf(destination.y - from.y) > settings.floor_tolerance:
		return false
	# Locomotion may leave a tiny contact penetration. Resolve it using the same
	# full-body recovery as move_and_collide, then validate the entire safe route.
	var start := contact_position(body, from, settings)
	var finish := contact_position(body, destination, settings)
	if not start.is_finite() or not finish.is_finite(): return false
	if not _sweep_clear(body, start, finish, 5): return false
	if body.test_move(Transform3D(body.global_basis, start), finish - start, null, body.safe_margin, false):
		return false
	return supported(body, start, finish, settings)

static func supported(body: CharacterBody3D, start: Vector3, finish: Vector3, settings: Resource) -> bool:
	# Shared by travel and the line of a melee strike; no sweep into the enemy body.
	if absf(finish.y - start.y) > settings.floor_tolerance: return false
	var space := body.get_world_3d().direct_space_state
	var collider: CollisionShape3D = body.get_node("CollisionShape3D")
	# Sample the capsule footprint, not just its centre, to reject ledges and gaps.
	var count := maxi(1, ceili(start.distance_to(finish) / settings.path_sample_spacing))
	var radius: float = collider.shape.radius * 0.95
	for index in range(count + 1):
		var point := start.lerp(finish, float(index) / count)
		for offset in [Vector3.ZERO, Vector3.RIGHT * radius, Vector3.LEFT * radius, Vector3.FORWARD * radius, Vector3.BACK * radius]:
			var sample: Vector3 = point + offset
			var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 0.1, sample - Vector3.UP * 0.1, 1)
			var floor_hit := space.intersect_ray(ray)
			if floor_hit.is_empty() or absf(floor_hit.position.y - point.y) > settings.floor_tolerance or floor_hit.normal.y < 0.99:
				return false
	return true

static func _sweep_clear(body: CharacterBody3D, start: Vector3, finish: Vector3, mask: int, endpoint_tolerance: float = 0.0) -> bool:
	var collider: CollisionShape3D = body.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(body.global_basis, start) * collider.transform
	query.transform.origin.y += 0.01
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	query.motion = finish - start
	var space := body.get_world_3d().direct_space_state
	if space.cast_motion(query)[0] >= 1.0: return true
	if endpoint_tolerance <= 0.0: return false
	# Only resolve proven, shallow endpoint contact, then sweep the whole route again.
	# A middle wall with a clear endpoint must never be accepted by this fallback.
	var original_transform := query.transform
	query.transform.origin += query.motion
	query.motion = Vector3.ZERO
	var contacts := space.collide_shape(query)
	if contacts.is_empty(): return false
	var recovery := Vector3.ZERO
	for index in range(0, contacts.size()-1, 2):
		var separation := contacts[index+1] - contacts[index]
		var depth := separation.length()
		if depth > endpoint_tolerance: return false
		if depth > 0.0:
			var normal := separation / depth
			recovery += normal * maxf(0.0, depth-recovery.dot(normal))
	if recovery.length_squared() <= 0.0 or recovery.length() > endpoint_tolerance: return false
	recovery += recovery.normalized() * minf(body.safe_margin, endpoint_tolerance-recovery.length())
	query.transform = original_transform
	query.motion = finish + recovery - start
	return space.cast_motion(query)[0] >= 1.0

static func strike_clear(body: CharacterBody3D, destination: Vector3, settings: Resource) -> bool:
	# Reuse travel geometry for terrain/low obstacles and continuous floor support.
	# Enemy bodies are not terrain: the existing sweep may hit several recipients.
	var start := contact_position(body, body.global_position, settings)
	if not start.is_finite(): return false
	# Keep a wall-parallel corridor parallel after the bounded native contact recovery.
	var finish := destination + (start - body.global_position)
	# A target's wall-tangent endpoint may need the same <=2mm recovery as the start.
	return sight(body, destination) and _sweep_clear(body, start, finish, 1, settings.contact_recovery_limit) and supported(body, start, destination, settings)

static func contact_position(body: CharacterBody3D, at: Vector3, settings: Resource) -> Vector3:
	var result := KinematicCollision3D.new()
	body.test_move(Transform3D(body.global_basis, at), Vector3.ZERO, result, body.safe_margin, false)
	var recovery := result.get_travel()
	if recovery.length() > settings.contact_recovery_limit: return Vector3.INF
	var resolved := at + recovery
	var collider: CollisionShape3D = body.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape # Original capsule, never shrink or exclude walls.
	query.transform = Transform3D(body.global_basis, resolved) * collider.transform
	query.transform.origin.y += 0.01 # Existing floor-contact separation for shape queries.
	query.collision_mask = 5
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	if not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return Vector3.INF
	return resolved

static func sight(body: CharacterBody3D, destination: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.8, destination + Vector3.UP * 0.8, 1)
	return body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
