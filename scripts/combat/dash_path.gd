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
	var space := body.get_world_3d().direct_space_state
	var collider: CollisionShape3D = body.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(body.global_basis, start) * collider.transform
	query.transform.origin.y += 0.01
	query.collision_mask = 5 # Terrain and enemy bodies; never the selectable marker.
	query.exclude = [body.get_rid()]
	query.margin = 0.0 # Native body test below owns the movement safety margin.
	query.motion = finish - start
	var sweep := space.cast_motion(query)
	if sweep[0] < 1.0:
		return false
	if body.test_move(Transform3D(body.global_basis, start), query.motion, null, body.safe_margin, false):
		return false
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
