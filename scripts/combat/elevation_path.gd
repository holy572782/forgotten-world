extends RefCounted
## Pure plans shared by player and soldier. Flat DashPath retains its contract.
const Path=preload("res://scripts/combat/dash_path.gd")
const Arc=preload("res://scripts/combat/jump_arc.gd")
const Blade=preload("res://scripts/combat/melee_terrain.gd")
const Sweep=preload("res://scripts/combat/melee_sweep.gd")
const Ground=preload("res://scripts/combat/terrain_ground.gd")
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")

static func supported(body: CharacterBody3D, at: Vector3, tolerance: float=0.04) -> bool:
	var center:=Ground.sample(body,at,0.1,0.3,body.floor_max_angle,Ground.contact_seam(body))
	if center.is_empty() or center.normal.y<cos(body.floor_max_angle) or absf(center.position.y-at.y)>tolerance+0.08: return false
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	var planar:=true
	for offset in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
		var ground:=Blade.ground_at(body,at+offset+Vector3.UP*0.5,1.0)
		var expected: float=center.position.y-(center.normal.x*offset.x+center.normal.z*offset.z)/center.normal.y
		if not ground.is_finite(): return false
		if absf(ground.y-expected)>tolerance: planar=false
	if planar: return true
	# Native capsules can stand across the continuous join of a ramp and flat
	# ground. Check actual surface continuity; never bridge a riser or missing floor.
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var previous:=center
		var count:=maxi(1,ceili(radius/0.08))
		for index in range(1,count+1):
			var point: Vector3=at+direction*radius*float(index)/count
			var hit:=Ground.sample(body,point,0.5,0.5,body.floor_max_angle,Ground.contact_seam(body))
			if hit.is_empty() or hit.normal.y<cos(body.floor_max_angle): return false
			var slope:=maxf(Vector2(hit.normal.x,hit.normal.z).length()/hit.normal.y,Vector2(previous.normal.x,previous.normal.z).length()/previous.normal.y)
			if absf(hit.position.y-previous.position.y)>slope*radius/count+0.005: return false
			previous=hit
	return true

static func landing(body: CharacterBody3D, at: Vector3) -> Vector3:
	var above:=at+Vector3.UP*0.2
	var collision:=KinematicCollision3D.new()
	if not body.test_move(Transform3D(body.global_basis,above),Vector3.DOWN*0.4,collision,body.safe_margin): return Vector3.INF
	if collision.get_normal().y<cos(body.floor_max_angle): return Vector3.INF
	var result:=above+collision.get_travel()
	return result if supported(body,result) else Vector3.INF
static func corridor(body: CharacterBody3D, start: Vector3, finish: Vector3, spacing: float) -> bool:
	var low:=minf(start.y,finish.y)
	var high:=maxf(start.y,finish.y)
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	var count:=maxi(1,ceili(start.distance_to(finish)/spacing))
	for index in range(count+1):
		var at:=start.lerp(finish,float(index)/count)
		for offset in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var ground:=Ground.surface(body,Vector3(at.x+offset.x,high+0.5,at.z+offset.z),0.05,high-low+1.0,body.floor_max_angle,Ground.contact_seam(body))
			if ground.is_empty() or ground.position.y<low-radius-0.04 or ground.position.y>high+radius+0.04: return false
	return true

static func plan(body: CharacterBody3D, start: Vector3, finish: Vector3, path: Resource, tuning: Resource, motion: Resource, returning: bool=false) -> Dictionary:
	if absf(start.y-finish.y)<=path.floor_tolerance:
		if Path.clear(body,finish,path,start): return {"air":false,"start":start,"finish":finish}
		if Blade.flat_footprint(body,start) and Blade.flat_footprint(body,finish): return {}
	if tuning==null or not tuning.enabled: return {}
	var rise:=finish.y-start.y
	var max_height:=clampf(tuning.apex_height,0.1,1.1)
	if "movement" in body: max_height=minf(max_height,body.movement.jump_speed*body.movement.jump_speed/(2.0*body.movement.gravity))
	elif "settings" in body: max_height=minf(max_height,body.settings.walk.jump_height)
	if rise>minf(tuning.maximum_ascent,max_height)+0.005 or -rise>tuning.maximum_descent+0.005: return {}
	if not supported(body,start) or not supported(body,finish) or not corridor(body,start,finish,path.path_sample_spacing): return {}
	if not actors_clear(body,start,finish): return {}
	var safe:=Path.contact_position(body,finish,path)
	if not safe.is_finite(): return {}
	safe.y+=0.003
	var apex:=minf(max_height,maxf(maxf(rise,0.0)+0.08,tuning.minimum_hop_height))
	if apex<rise+0.003: return {}
	var v:=sqrt(2.0*maxf(1.0,tuning.gravity)*apex)
	var duration:=Arc.flight_time(apex,v,safe.y-start.y)
	if duration<=0.0: return {}
	var speed: float=motion.return_speed if returning else motion.approach_speed
	var minimum: float=motion.return_minimum_travel_time if returning else motion.minimum_travel_time
	var maximum: float=motion.return_maximum_travel_time if returning else motion.maximum_travel_time
	var desired:=maxf(duration,clampf(start.distance_to(safe)/maxf(0.1,speed),minimum,maximum))
	# Stretch the ballistic clock without increasing the normal-jump apex.
	var scale:=duration/desired
	v*=scale
	var g:=maxf(1.0,tuning.gravity)*scale*scale
	var offset:=Vector3(safe.x-start.x,0,safe.z-start.z)
	var direction:=offset.normalized()
	var horizontal_speed:=offset.length()/desired
	var curve:=1 if rise>0.0 else -1 # Rise before crossing a lip; leave a high ledge before descending.
	if not Arc.clear(body,start,direction,horizontal_speed,v,g,desired,curve): return {}
	return {"air":true,"start":start,"finish":safe,"direction":direction,"speed":horizontal_speed,"takeoff":v,"gravity":g,"duration":desired,"curve":curve}

static func actors_clear(body: CharacterBody3D, start: Vector3, finish: Vector3) -> bool:
	# A low enemy must not become an obstacle we can simply jump over.
	var horizontal:=Vector3(finish.x-start.x,0,finish.z-start.z)
	if horizontal.length()<0.001: return false
	var radius: float=body.get_node("CollisionShape3D").shape.radius
	var shape:=BoxShape3D.new()
	shape.size=Vector3(radius*2.0,absf(finish.y-start.y)+3.0,horizontal.length())
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(Basis.looking_at(horizontal.normalized()),(start+finish)*0.5+Vector3.UP*1.5)
	query.collision_mask=6 # Both character layers, even if ordinary allies do not collide.
	query.exclude=[body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

static func new_attack_job() -> Dictionary:
	return {"index":-1,"done":false,"result":{},"reason":"NO_SAFE_LANDING"}

static func _work_attack(body: CharacterBody3D, at: Vector3, weapon: WeaponData, path: Resource, stop: float, motion: Resource, from: Vector3=Vector3.INF, diagnostics: Dictionary={}) -> Dictionary:
	var job:=new_attack_job()
	while not job.done: attack_step(body,at,weapon,path,stop,motion,from,job,diagnostics)
	return job.result

static func attack_step(body: CharacterBody3D, at: Vector3, weapon: WeaponData, path: Resource, stop: float, motion: Resource, from: Vector3, job: Dictionary, diagnostics: Dictionary={}) -> void:
	var started:=Work.start(body)
	_attack_step_now(body,at,weapon,path,stop,motion,from,job,diagnostics)
	job.reason=diagnostics.get("reason",job.reason)
	Work.finish(body,"elevation.step",started)

static func _attack_step_now(body: CharacterBody3D, at: Vector3, weapon: WeaponData, path: Resource, stop: float, motion: Resource, from: Vector3, job: Dictionary, diagnostics: Dictionary) -> void:
	var work:=Work.for_body(body)
	if work!=null and not work.attack_planning_enabled:
		reject(diagnostics,"DIAGNOSTIC_ATTACK_DISABLED")
		job.done=true
		return
	var start:=from if from.is_finite() else body.global_position
	var offset:=Vector3(at.x-start.x,0,at.z-start.z)
	if offset.length()>weapon.attack_range+0.00001:
		reject(diagnostics,"OUT_OF_RANGE")
		job.done=true
		return
	if job.index<0:
		if diagnostics.get("enabled",false): diagnostics["reason"]="NO_SAFE_LANDING"
		job.index=0
		if Sweep.contains(start,offset,at,weapon) and Blade.clear(body,at,path,2.0,start):
			job.result={"in_place":true,"destination":start,"out":{},"back":{}}
			job.done=true
		elif not supported(body,start) and not Path.clear(body,start,path,start):
			# No candidate can repair an unsafe takeoff footprint. Keep the
			# in-place blade check first, and preserve the existing level-path proof.
			reject(diagnostics,"NO_SAFE_TAKEOFF")
			job.done=true
		return
	var ground:=Blade.ground_at(body,at,2.0)
	if not ground.is_finite():
		job.done=true
		return
	var closest:=maxf(0.9,minf(stop,weapon.melee_reach))
	var count:=maxi(1,ceili((weapon.melee_reach-closest)/0.1))+1
	if job.index>=count:
		job.done=true
		return
	var distance:=closest+float(job.index)*0.1
	job.index+=1
	if distance>=offset.length(): return
	var destination:=ground-offset.normalized()*distance
	var floor_at:=Blade.ground_at(body,destination+Vector3.UP*1.1,2.3)
	if not floor_at.is_finite(): return
	destination=landing(body,floor_at)
	if not destination.is_finite(): return
	if not Sweep.contains(destination,at-destination,at,weapon):
		reject(diagnostics,"HEIGHT_OUT_OF_RANGE_OR_REACH")
		return
	if not Blade.clear(body,at,path,2.0,destination):
		reject(diagnostics,"BLADE_BLOCKED")
		return
	var out:=plan(body,start,destination,path,weapon.elevation_travel,motion)
	if out.is_empty():
		reject(diagnostics,"DASH_PATH_BLOCKED")
		return
	var back:=plan(body,destination,start,path,weapon.elevation_travel,motion,true)
	if back.is_empty():
		reject(diagnostics,"RETURN_PATH_BLOCKED")
		return
	job.result={"in_place":false,"destination":destination,"out":out,"back":back}
	job.result["candidate_index"]=job.index-1
	job.done=true

static func reject(diagnostics: Dictionary, reason: String) -> Dictionary:
	if diagnostics.get("enabled",false): diagnostics["reason"]=reason
	return {}

static func attack(body: CharacterBody3D, at: Vector3, weapon: WeaponData, path: Resource, stop: float, motion: Resource, from: Vector3=Vector3.INF, diagnostics: Dictionary={}) -> Dictionary:
	var started:=Work.start(body)
	var result: Dictionary=_work_attack(body,at,weapon,path,stop,motion,from,diagnostics)
	Work.finish(body,"elevation.attack",started)
	return result
