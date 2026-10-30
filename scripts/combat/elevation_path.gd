extends RefCounted
## Pure plans shared by player and soldier. Flat DashPath retains its contract.
const Path=preload("res://scripts/combat/dash_path.gd")
const Arc=preload("res://scripts/combat/jump_arc.gd")
const Blade=preload("res://scripts/combat/melee_terrain.gd")
const Sweep=preload("res://scripts/combat/melee_sweep.gd")

static func supported(body: CharacterBody3D, at: Vector3, tolerance: float=0.04) -> bool:
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	for offset in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
		var ground:=Path.ground_below(body,at+offset+Vector3.UP*0.02,0.1)
		if not ground.is_finite() or absf(ground.y-at.y)>tolerance: return false
	return true

static func corridor(body: CharacterBody3D, start: Vector3, finish: Vector3, spacing: float) -> bool:
	var low:=minf(start.y,finish.y)
	var high:=maxf(start.y,finish.y)
	var radius: float=body.get_node("CollisionShape3D").shape.radius*0.95
	var count:=maxi(1,ceili(start.distance_to(finish)/spacing))
	for index in range(count+1):
		var at:=start.lerp(finish,float(index)/count)
		for offset in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var ground:=Path.ground_below(body,Vector3(at.x+offset.x,high+0.05,at.z+offset.z),high-low+0.15)
			if not ground.is_finite() or ground.y<low-0.04 or ground.y>high+0.04: return false
	return true

static func plan(body: CharacterBody3D, start: Vector3, finish: Vector3, path: Resource, tuning: Resource, motion: Resource, returning: bool=false) -> Dictionary:
	if absf(start.y-finish.y)<=path.floor_tolerance:
		return {"air":false,"start":start,"finish":finish} if Path.clear(body,finish,path,start) else {}
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

static func attack(body: CharacterBody3D, at: Vector3, weapon: WeaponData, path: Resource, stop: float, motion: Resource, from: Vector3=Vector3.INF) -> Dictionary:
	var start:=from if from.is_finite() else body.global_position
	var offset:=Vector3(at.x-start.x,0,at.z-start.z)
	if offset.length()>weapon.attack_range+0.00001: return {}
	if Sweep.contains(start,offset,at,weapon) and Blade.clear(body,at,path,2.0,start): return {"in_place":true,"destination":start,"out":{},"back":{}}
	var ground:=Path.ground_below(body,at,2.0)
	if not ground.is_finite() or not Blade.clear(body,at,path,2.0,start): return {}
	# Search supported stops before the target, never beyond/through its body.
	var closest:=maxf(0.9,minf(stop,weapon.melee_reach))
	for index in range(maxi(1,ceili((weapon.melee_reach-closest)/0.1))+1):
		var distance:=closest+float(index)*0.1
		if distance>=offset.length(): continue
		var destination:=ground-offset.normalized()*distance
		var floor_at:=Path.ground_below(body,destination+Vector3.UP*0.02,0.1)
		if not floor_at.is_finite() or absf(floor_at.y-ground.y)>0.04: continue
		destination.y=floor_at.y
		var out:=plan(body,start,destination,path,weapon.elevation_travel,motion)
		if out.is_empty(): continue
		var back:=plan(body,destination,start,path,weapon.elevation_travel,motion,true)
		if back.is_empty(): continue
		return {"in_place":false,"destination":destination,"out":out,"back":back}
	return {}
