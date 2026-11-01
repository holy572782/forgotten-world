extends RefCounted
## Corridor verification needs the actual walkable centre surface. Endpoint
## capsule support retains sample()'s contact/seam proof unchanged.
static func surface(body: CharacterBody3D, at: Vector3, up: float, down: float, angle: float, seam: float) -> Dictionary:
	var hit:=_ray(body,at,up,down)
	if not hit.is_empty() and hit.normal.y>=cos(angle): return hit
	return sample(body,at,up,down,angle,seam)
## Real walkable surfaces, with a bounded two-sided proof for tiny map seams.
static func sample(body: CharacterBody3D, at: Vector3, up: float, down: float, angle: float, seam: float=0.0, seam_height: float=0.15) -> Dictionary:
	var center:=_ray(body,at,up,down)
	if not center.is_empty() and center.normal.y<=0.01: return {} # Never bypass solid ceilings/vertical walls.
	if not center.is_empty() and center.normal.y>=cos(angle) and absf(center.position.y-at.y)<=0.12: return center
	if seam>0.0:
		for direction in [Vector3.RIGHT,Vector3.FORWARD]:
			var a:=_ray(body,at-direction*seam,up,down)
			var b:=_ray(body,at+direction*seam,up,down)
			if a.is_empty() or b.is_empty() or a.normal.y<cos(angle) or b.normal.y<cos(angle): continue
			if absf(a.position.y-b.position.y)>seam_height: continue
			var height: float=(a.position.y+b.position.y)*0.5
			# A rotated ramp's short end cap may sit just below its adjoining
			# landing. It is not itself walkable: require enclosing walkable tops.
			if not center.is_empty() and height<center.position.y-0.04: continue
			if center.is_empty() or center.normal.y<cos(angle) or height>center.position.y+0.04:
				return {"position":Vector3(at.x,height,at.z),"normal":(a.normal+b.normal).normalized()}
	return center if center.is_empty() or center.normal.y>=cos(angle) else {}

static func _ray(body: CharacterBody3D, at: Vector3, up: float, down: float) -> Dictionary:
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*up,at-Vector3.UP*down,1)
	ray.exclude=[body.get_rid()]
	var result:=body.get_world_3d().direct_space_state.intersect_ray(ray)
	return result

static func contact_seam(body: CharacterBody3D) -> float:
	return minf(0.15,body.get_node("CollisionShape3D").shape.radius*0.45)
