extends RefCounted
## Enemy-only native floor locomotion and swept, time-based stair climbing.
var actor: CharacterBody3D
var config: Resource
var retry := 0.0
var vertical_speed := 0.0
var climb: Array[Vector3] = []
var climb_speed := 0.0
var breadcrumbs: Array[Vector3] = []
var returning := false
var blocked := false

func _init(body: CharacterBody3D) -> void:
	actor = body
	config = body.settings.walk
	actor.floor_max_angle = deg_to_rad(config.max_slope_degrees)
	actor.floor_snap_length = config.snap_length
	actor.floor_constant_speed = true
	actor.floor_stop_on_slope = true
	breadcrumbs.append(body.home)

static func horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

static func floor_hit(body: CharacterBody3D, at: Vector3, up: float, down: float, slope: float = 45.0) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*up,at-Vector3.UP*down,1)
	ray.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < cos(deg_to_rad(slope)): return {}
	return hit

func target_floor(at: Vector3, depth: float = 2.0) -> Vector3:
	var hit := floor_hit(actor,at,0.05,depth,config.max_slope_degrees)
	return hit.position if not hit.is_empty() else Vector3.INF

func _sample(at: Vector3) -> Dictionary:
	var hit := floor_hit(actor,at,config.maximum_step_up+0.03,config.maximum_step_down+0.03,config.max_slope_degrees)
	if not hit.is_empty(): return hit
	var seam: float = config.floor_seam_tolerance
	if seam<=0.0: return {}
	for direction in [Vector3.RIGHT,Vector3.FORWARD]:
		var a:=floor_hit(actor,at-direction*seam,config.maximum_step_up+0.03,config.maximum_step_down+0.03,config.max_slope_degrees)
		var b:=floor_hit(actor,at+direction*seam,config.maximum_step_up+0.03,config.maximum_step_down+0.03,config.max_slope_degrees)
		if not a.is_empty() and not b.is_empty() and absf(a.position.y-b.position.y)<=0.15:
			return {"position":Vector3(at.x,(a.position.y+b.position.y)*0.5,at.z),"normal":Vector3.UP}
	return {}

func _support(at: Vector3, flat: bool = false) -> bool:
	var radius: float = actor.get_node("CollisionShape3D").shape.radius*0.95
	for offset in [Vector3.ZERO,Vector3.LEFT*radius,Vector3.RIGHT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
		var hit := _sample(at+offset)
		if hit.is_empty(): return false
		var rise: float = hit.position.y-at.y
		if rise>config.maximum_step_up+0.01 or rise < -config.maximum_step_down-0.01: return false
		if flat and absf(rise)>0.04: return false
	return true

func _motion_clear(start: Vector3, motion: Vector3, floor_ok: bool = false) -> bool:
	var collision := KinematicCollision3D.new()
	if not actor.test_move(Transform3D(actor.global_basis,start),motion,collision,actor.safe_margin): return true
	return floor_ok and collision.get_normal().y >= cos(deg_to_rad(config.max_slope_degrees))

func can_reach(at: Vector3, check_clearance: bool = true) -> bool:
	var current := actor.global_position
	var count := maxi(1,ceili(horizontal(current,at)/0.15))
	for index in range(1,count+1):
		var next := current.lerp(at,1.0/float(count-index+1))
		var hit := _sample(next)
		if hit.is_empty(): return false
		next.y=hit.position.y
		if absf(next.y-current.y)>maxf(config.maximum_step_up,config.maximum_step_down)+0.01 or not _support(next): return false
		if check_clearance and not _motion_clear(current,next-current,true):
			if next.y-current.y<=0.04:
				var ahead := current+(next-current).normalized()*0.9
				var step := floor_hit(actor,ahead,config.maximum_step_up+0.03,0.05,config.max_slope_degrees)
				if step.is_empty() or step.position.y-current.y<=0.04: return false
				next.y=step.position.y
			var raised := Vector3(current.x,next.y+0.01,current.z)
			if not _motion_clear(current,raised-current) or not _motion_clear(raised,next+Vector3.UP*0.01-raised): return false
		current=next
	return true

func busy() -> bool: return not climb.is_empty()

func _record() -> void:
	if returning: return
	if breadcrumbs.is_empty() or breadcrumbs[0]!=actor.home: breadcrumbs.assign([actor.home])
	if horizontal(breadcrumbs[-1],actor.global_position)>0.25 or absf(breadcrumbs[-1].y-actor.global_position.y)>0.12:
		breadcrumbs.append(actor.global_position)
		if breadcrumbs.size()>256: breadcrumbs.remove_at(1)

func begin_return() -> void:
	returning=true
	# Record the actual grounded endpoint before retracing, never an airborne climb midpoint.
	retry=0.0

func home_goal() -> Vector3:
	while breadcrumbs.size()>1 and actor.global_position.distance_to(breadcrumbs[-1])<0.09:
		breadcrumbs.pop_back()
	return breadcrumbs[-1] if not breadcrumbs.is_empty() else actor.home

func reset_home() -> void:
	returning=false
	breadcrumbs.assign([actor.home])
	retry=0.0

func continue_climb(delta: float) -> void:
	actor.velocity=Vector3.ZERO
	if climb.is_empty(): return
	var goal := climb[0]
	var speed: float = config.climb_speed if absf(goal.y-actor.global_position.y)>0.001 else climb_speed
	var next := actor.global_position.move_toward(goal,speed*delta)
	var before := actor.global_position
	var collision := actor.move_and_collide(next-before)
	actor.velocity=(actor.global_position-before)/maxf(delta,0.0001)
	if collision!=null and actor.global_position.distance_to(goal)>0.015:
		climb.clear()
		blocked=true
		retry=config.blocked_retry_seconds
		actor.velocity=Vector3.ZERO
	elif actor.global_position.distance_to(goal)<0.012:
		climb.pop_front()
		if climb.is_empty():
			vertical_speed=0.0
			_record()

func _try_climb(direction: Vector3, speed: float) -> bool:
	var radius: float=actor.get_node("CollisionShape3D").shape.radius
	var landing := actor.global_position+direction*(radius*2.0+0.1)
	var hit := floor_hit(actor,landing,config.maximum_step_up+0.03,0.05,config.max_slope_degrees)
	if hit.is_empty(): return false
	landing.y=hit.position.y
	var rise:=landing.y-actor.global_position.y
	if rise<=0.04 or rise>config.maximum_step_up+0.01 or not _support(landing,true): return false
	if horizontal(landing,actor.home)>actor.settings.leash_radius: return false
	var raised:=Vector3(actor.global_position.x,landing.y+0.01,actor.global_position.z)
	var across:=landing+Vector3.UP*0.01
	if not _motion_clear(actor.global_position,raised-actor.global_position) or not _motion_clear(raised,across-raised): return false
	_record()
	climb.assign([raised,across,landing+Vector3.UP*0.001])
	climb_speed=speed
	blocked=false
	return true

func walk(at: Vector3, delta: float, speed: float) -> void:
	actor.velocity=Vector3.ZERO
	if busy():
		continue_climb(delta)
		return
	retry=maxf(0.0,retry-delta)
	if retry>0.0: return
	var offset:=Vector3(at.x-actor.global_position.x,0,at.z-actor.global_position.z)
	if offset.length()<0.001 and absf(at.y-actor.global_position.y)<0.08: return
	var direction:=offset.normalized()
	var motion:=direction*minf(speed*delta,offset.length())
	var next:=actor.global_position+motion
	if horizontal(next,actor.home)>actor.settings.leash_radius or not _support(next):
		blocked=true
		retry=config.blocked_retry_seconds
		return
	var collision:=KinematicCollision3D.new()
	if actor.test_move(actor.global_transform,motion,collision,actor.safe_margin) and collision.get_normal().y < cos(deg_to_rad(config.max_slope_degrees)):
		if _try_climb(direction,speed): continue_climb(delta)
		else:
			blocked=true
			retry=config.blocked_retry_seconds
		return
	var before:=actor.global_position
	vertical_speed=0.0 if actor.is_on_floor() else maxf(-config.climb_speed,vertical_speed-config.gravity*delta)
	actor.velocity=Vector3(direction.x*speed,vertical_speed,direction.z*speed)
	if offset.length()<speed*delta:
		actor.velocity.x=motion.x/delta
		actor.velocity.z=motion.z/delta
	actor.move_and_slide()
	vertical_speed=actor.velocity.y
	actor.velocity=(actor.global_position-before)/maxf(delta,0.0001)
	blocked=horizontal(before,actor.global_position)<motion.length()*0.2 and motion.length()>0.001
	if blocked:
		if _try_climb(direction,speed):
			continue_climb(delta)
			return
		retry=config.blocked_retry_seconds
		actor.velocity=Vector3.ZERO
	if actor.is_on_floor(): _record()
