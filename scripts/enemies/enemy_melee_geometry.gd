extends RefCounted
## Terrain permission for enemy sword hits, independent of dash travel and hit shape.
const Walk = preload("res://scripts/enemies/enemy_walk.gd")
const BladeTerrain=preload("res://scripts/combat/melee_terrain.gd")
static func clear(body: CharacterBody3D, at: Vector3) -> bool:
	if body.active_attack.weapon!=null and body.active_attack.weapon.hit_height_up>=0.0:
		return BladeTerrain.clear(body,at,body.settings.path,body.active_attack.target_ground_probe_depth)
	var config: Resource=body.settings.walk
	var ground:=Walk.floor_hit(body,at,0.05,body.active_attack.target_ground_probe_depth,config.max_slope_degrees)
	if ground.is_empty(): return false
	var start:=body.global_position
	var finish: Vector3=ground.position
	var low:=minf(start.y,finish.y)
	var high:=maxf(start.y,finish.y)
	# Existing eye-height sight remains mandatory; this second blade line rejects floors/overhangs.
	var ray:=PhysicsRayQueryParameters3D.create(start+Vector3.UP*0.8,at+Vector3.UP*0.8,1)
	if not body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	var count:=maxi(1,ceili(Walk.horizontal(start,finish)/body.settings.path.path_sample_spacing))
	for index in range(count+1):
		var point:=start.lerp(finish,float(index)/count)
		for offset in [Vector3.ZERO,Vector3.LEFT*radius,Vector3.RIGHT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var hit:=Walk.floor_hit(body,Vector3(point.x+offset.x,high,point.z+offset.z),1.5,high-low+1.6,config.max_slope_degrees)
			if hit.is_empty(): return false
			var allowance := 0.04 + radius*tan(acos(clampf(hit.normal.y,0.01,1.0)))
			if hit.position.y<low-allowance or hit.position.y>high+allowance: return false
	return true
