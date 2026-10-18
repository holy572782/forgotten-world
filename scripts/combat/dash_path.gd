extends RefCounted
## Conservative M06 straight, level route. Slopes/steps require normal locomotion.
static func clear(body: CharacterBody3D, destination: Vector3, settings: Resource, from: Vector3) -> bool:
	if absf(destination.y - from.y) > settings.floor_tolerance:
		return false
	var space := body.get_world_3d().direct_space_state
	var collider: CollisionShape3D = body.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(body.global_basis, from) * collider.transform
	query.transform.origin.y += 0.01
	query.collision_mask = 5 # Terrain and enemy bodies; never the selectable marker.
	query.exclude = [body.get_rid()]
	query.margin = 0.001
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = destination - from
	var sweep := space.cast_motion(query)
	if sweep[0] < 1.0:
		return false
	# Sample the capsule footprint, not just its centre, to reject ledges and gaps.
	var count := maxi(1, ceili(from.distance_to(destination) / settings.path_sample_spacing))
	var radius: float = collider.shape.radius * 0.95
	for index in range(count + 1):
		var point := from.lerp(destination, float(index) / count)
		for offset in [Vector3.ZERO, Vector3.RIGHT * radius, Vector3.LEFT * radius, Vector3.FORWARD * radius, Vector3.BACK * radius]:
			var sample: Vector3 = point + offset
			var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 0.1, sample - Vector3.UP * 0.1, 1)
			var floor_hit := space.intersect_ray(ray)
			if floor_hit.is_empty() or absf(floor_hit.position.y - point.y) > settings.floor_tolerance or floor_hit.normal.y < 0.99:
				return false
	return true

static func sight(body: CharacterBody3D, destination: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.8, destination + Vector3.UP * 0.8, 1)
	return body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
