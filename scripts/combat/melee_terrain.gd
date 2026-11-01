extends RefCounted
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
## Blade clearance only. Does not authorize body movement or create damage.
const Path=preload("res://scripts/combat/dash_path.gd")
const Ground=preload("res://scripts/combat/terrain_ground.gd")
static func _work_clear(body: CharacterBody3D, at: Vector3, settings: Resource, depth: float=2.0, from: Vector3=Vector3.INF) -> bool:
	var ground:=ground_at(body,at,depth)
	if not ground.is_finite(): return false
	var start:=from if from.is_finite() else body.global_position
	if absf(ground.y-start.y)<=settings.floor_tolerance and flat_at(body,start) and flat_at(body,ground):
		if start.distance_to(body.global_position)>0.005:
			if Path.supported(body,start,ground,settings) and Path._sweep_clear(body,start,ground,1) and _line(body,start+Vector3.UP*0.8,at+Vector3.UP*0.8): return true
		elif Path.strike_clear(body,ground,settings) and _line(body,start+Vector3.UP*0.8,at+Vector3.UP*0.8): return true
		# A capsule/footprint may touch a ramp although both centre rays hit flat
		# ground. Fall through to the blade-only terrain checks, not a level dash.
	var low:=minf(start.y,ground.y)
	var high:=maxf(start.y,ground.y)
	var hand:=Vector3(start.x,maxf(high,at.y)+0.8,start.z)
	var tip:=Vector3(at.x,hand.y,at.z)
	# Raise the blade over a step lip; vertical columns reject ceilings/overhangs/floors.
	if not _line(body,start+Vector3.UP*0.8,hand) or not _line(body,hand,tip) or not _line(body,tip,at+Vector3.UP*0.8): return false
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	var count:=maxi(1,ceili(Vector2(at.x-start.x,at.z-start.z).length()/settings.path_sample_spacing))
	for index in range(count+1):
		var point:=start.lerp(ground,float(index)/count)
		for offset in [Vector3.ZERO,Vector3.LEFT*radius,Vector3.RIGHT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var hit:=Ground.surface(body,Vector3(point.x+offset.x,high,point.z+offset.z),1.5,high-low+radius+0.1,body.floor_max_angle,Ground.contact_seam(body))
			if hit.is_empty(): return false
			var allowance:=0.04+radius*tan(acos(clampf(hit.normal.y,0.01,1.0)))
			if hit.normal.y<0.7 or hit.position.y<low-allowance or hit.position.y>high+allowance: return false
	return true

static func ground_at(body: CharacterBody3D, at: Vector3, depth: float) -> Vector3:
	var hit:=Ground.sample(body,at,0.05,depth,body.floor_max_angle,Ground.contact_seam(body))
	if hit.is_empty() or hit.normal.y<cos(body.floor_max_angle): return Vector3.INF
	return hit.position

static func _line(body: CharacterBody3D, a: Vector3, b: Vector3) -> bool:
	if a.distance_squared_to(b)<0.000001: return true
	return body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1)).is_empty()

static func flat_at(body: CharacterBody3D, at: Vector3) -> bool:
	var hit:=body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.1,at-Vector3.UP*0.3,1))
	return not hit.is_empty() and hit.normal.y>=0.99

static func flat_footprint(body: CharacterBody3D, at: Vector3) -> bool:
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	for offset in [Vector3.ZERO,Vector3.LEFT*radius,Vector3.RIGHT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
		var hit:=Ground.sample(body,at+offset,0.1,0.3,body.floor_max_angle,Ground.contact_seam(body))
		if hit.is_empty() or hit.normal.y<0.99 or absf(hit.position.y-at.y)>0.04: return false
	return true

static func clear(body: CharacterBody3D, at: Vector3, settings: Resource, depth: float=2.0, from: Vector3=Vector3.INF) -> bool:
	var started:=Work.start(body)
	var result: bool=_work_clear(body,at,settings,depth,from)
	Work.finish(body,"blade.clear",started)
	return result
