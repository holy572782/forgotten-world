extends RefCounted
## World-space sector at the current strike point. Never grants movement safety.
static func contains(origin: Vector3, facing: Vector3, point: Vector3, weapon: WeaponData) -> bool:
	var offset := point - origin
	if absf(offset.y) > weapon.hit_height_tolerance: return false
	offset.y = 0.0
	var forward := Vector3(facing.x,0,facing.z).normalized()
	if forward.is_zero_approx() or offset.length() > maxf(0.0,weapon.melee_reach): return false
	if offset.is_zero_approx(): return false
	return forward.dot(offset.normalized()) >= cos(deg_to_rad(clampf(weapon.sweep_angle_degrees,1.0,180.0)*0.5)) - 0.000001
