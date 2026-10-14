extends RefCounted
## Camera-volume safety, independent of player-to-camera visibility.
var failed := false
var discontinuity := false
var holding := false
var _shape := SphereShape3D.new()
var _last_desired := Vector3.ZERO
var _has_desired := false

func _query(at: Vector3, settings: Resource, excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	_shape.radius = settings.camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = settings.terrain_mask
	query.margin = settings.collision_margin
	query.exclude = excluded
	return query

func is_clear(space: PhysicsDirectSpaceState3D, at: Vector3, settings: Resource, excluded: Array[RID]) -> bool:
	return space.intersect_shape(_query(at, settings, excluded), 1).is_empty()

func _sweep(space: PhysicsDirectSpaceState3D, start: Vector3, finish: Vector3, settings: Resource, excluded: Array[RID]) -> Vector3:
	var query := _query(start, settings, excluded)
	query.motion = finish - start
	if query.motion.is_zero_approx(): return finish
	var fraction := space.cast_motion(query)[0]
	# Leave extra room for floating-point differences and render interpolation.
	var safe := maxf(0, fraction - settings.collision_margin / query.motion.length()) if fraction < 1.0 else 1.0
	return start + query.motion * safe

func solve(space: PhysicsDirectSpaceState3D, desired: Vector3, previous: Vector3, basis: Basis, settings: Resource, excluded: Array[RID], reset: bool, delta: float) -> Vector3:
	failed = false
	discontinuity = reset
	holding = false
	var nominal_motion := desired - _last_desired if _has_desired and not reset else Vector3.ZERO
	_last_desired = desired
	_has_desired = true
	var previous_clear := not reset and is_clear(space, previous, settings, excluded)
	var candidates: Array[Vector3] = [desired]
	# No player-side collapse: local corrections are bounded around the nominal eye.
	for step in range(1, settings.correction_steps + 1):
		var offset: float = settings.max_local_correction * step / settings.correction_steps
		for axis in [Vector3.UP, basis.x, -basis.x, basis.z, -basis.z]:
			candidates.append(desired + axis * offset)
	for candidate in candidates:
		if not is_clear(space, candidate, settings, excluded): continue
		if previous_clear:
			# Orbit/follow retains its normal speed; applying AND releasing a safety
			# offset is rate-limited, including after an obstacle disappears.
			var next := (previous + nominal_motion).move_toward(candidate, settings.correction_speed * delta)
			var safe := _sweep(space, previous, next, settings, excluded)
			if safe.distance_to(next) > 0.01: continue
			if is_clear(space, safe, settings, excluded): return safe
		else:
			discontinuity = true
			return candidate
	# When blocked, retain a verified safe eye, instead of zooming toward the player.
	if previous_clear:
		holding = true
		return previous
	# Spawn/teleport or geometry moving over the old eye: find a new safe height.
	for step in range(1, settings.emergency_steps + 1):
		var candidate: Vector3 = desired + Vector3.UP * settings.emergency_step_height * step
		if is_clear(space, candidate, settings, excluded):
			discontinuity = true
			return candidate
	# No mathematical guarantee for arbitrary enclosing geometry: fail explicitly.
	failed = true
	return previous
