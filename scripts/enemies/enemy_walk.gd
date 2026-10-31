extends RefCounted
## Enemy-only native floor locomotion and swept, time-based stair climbing.
const Arc = preload("res://scripts/combat/jump_arc.gd")
const Ground = preload("res://scripts/combat/terrain_ground.gd")
enum Motion { WALK, STEP, JUMP, FALL, STRANDED }
var motion_mode := Motion.WALK
var jump_data: Dictionary = {}
var jump_elapsed := 0.0
var jump_cooldown := 0.0
var jump_count := 0
var _fall_elapsed := 0.0
var _rise_ahead := 0.0
var actor: CharacterBody3D
var config: Resource
var retry := 0.0
var vertical_speed := 0.0
var climb: Array[Vector3] = []
var climb_speed := 0.0
var breadcrumbs: Array[Vector3] = []
var returning := false
var blocked := false
var blocked_reason := ""

func _within_walk_bounds(at: Vector3) -> bool:
	if actor.inside_home(at): return true
	# Turning debugging off outside the leash must still allow the proven home
	# route to move inward. It does not reopen pursuit/attack eligibility.
	return returning and horizontal(at,actor.home)<=horizontal(actor.global_position,actor.home)+0.05

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
	var hit := Ground.sample(actor,at,0.05,depth,deg_to_rad(config.max_slope_degrees),config.floor_seam_tolerance)
	return hit.position if not hit.is_empty() else Vector3.INF

func _sample(at: Vector3) -> Dictionary:
	return Ground.sample(actor,at,config.maximum_step_up+0.03,config.maximum_step_down+0.03,deg_to_rad(config.max_slope_degrees),config.floor_seam_tolerance)

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
	if not actor.test_move(Transform3D(actor.global_basis,start),motion,collision,actor.safe_margin,false,8): return true
	if not floor_ok or not _floor_contacts_only(collision): return false
	# A first floor contact can mask a wall later in the requested motion. Probe
	# with the capsule just clear of its actual supporting plane, then inspect all
	# endpoint recovery contacts as well. This is a query, never a body relocation.
	var floor_at:=_sample(start)
	if floor_at.is_empty(): return false
	var radius: float=actor.get_node("CollisionShape3D").shape.radius
	var lift:=maxf(0.01,floor_at.position.y-start.y+radius*(1.0/floor_at.normal.y-1.0)+0.01)
	if lift>radius*(1.0/cos(deg_to_rad(config.max_slope_degrees))-1.0)+0.04: return false
	var raised:=start+Vector3.UP*lift
	var sweep:=KinematicCollision3D.new()
	if actor.test_move(Transform3D(actor.global_basis,raised),motion,sweep,actor.safe_margin,false,8) and not _floor_contacts_only(sweep): return false
	var endpoint:=KinematicCollision3D.new()
	if actor.test_move(Transform3D(actor.global_basis,raised+motion),Vector3.ZERO,endpoint,actor.safe_margin,true,8) and not _floor_contacts_only(endpoint): return false
	return true

func _floor_contacts_only(collision: KinematicCollision3D) -> bool:
	for index in range(collision.get_collision_count()):
		if collision.get_normal(index).y<cos(deg_to_rad(config.max_slope_degrees)): return false
	return true

func can_reach(at: Vector3, check_clearance: bool = true, from: Vector3 = Vector3.INF) -> bool:
	var current := from if from.is_finite() else actor.global_position
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

func airborne() -> bool: return motion_mode in [Motion.JUMP,Motion.FALL,Motion.STRANDED]

func busy() -> bool: return not climb.is_empty() or airborne()

func advance_cooldown(delta: float) -> void:
	jump_cooldown=maxf(0.0,jump_cooldown-delta)

func _jump_corridor(landing: Vector3) -> bool:
	var start:=actor.global_position
	var count:=maxi(1,ceili(horizontal(start,landing)/0.1))
	for index in range(count+1):
		var at:=start.lerp(landing,float(index)/count)
		if not _within_walk_bounds(at): return false
		var hit:=_sample(at)
		if hit.is_empty() or hit.position.y<minf(start.y,landing.y)-0.04 or hit.position.y>maxf(start.y,landing.y)+0.04: return false
		if not _support(Vector3(at.x,hit.position.y,at.z)): return false
	return true

func _jump_plan(direction: Vector3) -> Dictionary:
	_rise_ahead=0.0
	if not config.jump_enabled or direction.is_zero_approx() or not _can_land(): return {}
	var height: float=clampf(config.jump_height,0.4,1.5)
	var takeoff: float=clampf(config.jump_takeoff_speed,2.0,12.0)
	var speed: float=clampf(config.jump_horizontal_speed,0.5,6.0)
	var start:=actor.global_position
	var horizon:=minf(4.0,Arc.flight_time(height,takeoff,0.0)*speed)
	var seen: Dictionary={}
	for index in range(4,ceili(horizon/0.1)+1):
		var distance:=float(index)*0.1
		var hit:=floor_hit(actor,start+direction*distance,height+0.05,0.05,config.max_slope_degrees)
		if hit.is_empty() or hit.normal.y<0.99: continue # Ramps use native floor walking.
		var rise: float=hit.position.y-start.y
		if rise<=config.walking_step_height+0.01: continue
		var contact:=KinematicCollision3D.new()
		if not actor.test_move(actor.global_transform,direction*distance,contact,actor.safe_margin) or contact.get_normal().y>=cos(deg_to_rad(config.max_slope_degrees)): continue
		_rise_ahead=maxf(_rise_ahead,rise)
		var key:=roundi(rise*100.0)
		if seen.has(key): continue
		seen[key]=true
		if rise>config.maximum_step_up+0.01 or rise+0.003>height: continue
		var duration:=Arc.flight_time(height,takeoff,rise+0.003)
		var landing:=start+direction*speed*duration
		landing.y=start.y+rise+0.003
		var floor_at:=floor_hit(actor,landing,0.02,0.08,config.max_slope_degrees)
		if floor_at.is_empty() or absf(floor_at.position.y-hit.position.y)>0.02: continue
		if not _support(Vector3(landing.x,floor_at.position.y,landing.z),true) or not _jump_corridor(landing): continue
		var g:=Arc.gravity(height,takeoff)
		if not Arc.clear(actor,start,direction,speed,takeoff,g,duration): continue
		return {"start":start,"direction":direction,"speed":speed,"takeoff":takeoff,"gravity":g,"duration":duration,"landing":landing,"cooldown":config.jump_cooldown_seconds,"height":height}
	return {}

func _begin_jump(plan: Dictionary) -> void:
	_record()
	jump_data=plan
	jump_elapsed=0.0
	motion_mode=Motion.JUMP
	jump_count+=1
	blocked=false
	blocked_reason=""
	actor.facing=plan.direction

func _settled() -> void:
	if not returning:
		_record()
		return
	# A hop can pass several return breadcrumbs. Resume at the nearest grounded one.
	var nearest:=breadcrumbs.size()-1
	var distance:=INF
	for index in range(breadcrumbs.size()):
		var candidate:=actor.global_position.distance_squared_to(breadcrumbs[index])
		if candidate<distance:
			distance=candidate
			nearest=index
	if nearest>=0: breadcrumbs.resize(nearest+1)

func _can_land() -> bool:
	var floor_at:=floor_hit(actor,actor.global_position,0.02,0.05,config.max_slope_degrees)
	return not floor_at.is_empty() and _support(actor.global_position)

func _land_jump() -> void:
	motion_mode=Motion.WALK
	vertical_speed=0.0
	jump_cooldown=maxf(0.1,float(jump_data.get("cooldown",config.jump_cooldown_seconds)))
	actor.apply_floor_snap()
	_settled()

func _advance_air(delta: float) -> void:
	var before:=actor.global_position
	if motion_mode==Motion.STRANDED:
		actor.velocity=Vector3.ZERO
		var restored:=floor_hit(actor,before,0.02,0.05,config.max_slope_degrees)
		if not restored.is_empty() and _support(before): _land_jump()
		return
	if motion_mode==Motion.JUMP:
		jump_elapsed=minf(jump_elapsed+delta,jump_data.duration)
		var next:=Arc.position_at(jump_data.start,jump_data.direction,jump_data.speed,jump_data.takeoff,jump_data.gravity,jump_elapsed)
		var collision:=actor.move_and_collide(next-before)
		actor.velocity=(actor.global_position-before)/maxf(delta,0.0001)
		if collision!=null:
			if collision.get_normal().y>=cos(deg_to_rad(config.max_slope_degrees)) and actor.velocity.y<=0.0 and _can_land():
				_land_jump()
			else:
				motion_mode=Motion.FALL
				vertical_speed=minf(0.0,actor.velocity.y)
				_fall_elapsed=0.0
		elif jump_elapsed>=jump_data.duration:
			var floor_at:=floor_hit(actor,actor.global_position,0.02,0.05,config.max_slope_degrees)
			if not floor_at.is_empty() and _support(actor.global_position): _land_jump()
			else:
				motion_mode=Motion.FALL
				vertical_speed=minf(0.0,jump_data.takeoff-jump_data.gravity*jump_elapsed)
				_fall_elapsed=0.0
		return
	_fall_elapsed+=delta
	vertical_speed=maxf(-10.0,vertical_speed-config.gravity*delta)
	var collision:=actor.move_and_collide(Vector3.UP*vertical_speed*delta)
	actor.velocity=(actor.global_position-before)/maxf(delta,0.0001)
	if collision!=null and collision.get_normal().y>=cos(deg_to_rad(config.max_slope_degrees)) and _can_land():
		_land_jump()
	elif _fall_elapsed>=2.0 and collision==null:
		motion_mode=Motion.STRANDED # No warp or retry-jump into missing terrain.
		actor.velocity=Vector3.ZERO
		blocked=true
		blocked_reason="GROUND_LOST"

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
	if airborne():
		_advance_air(delta)
		return
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
		blocked_reason="CLIMB_COLLISION"
		retry=config.blocked_retry_seconds
		actor.velocity=Vector3.ZERO
	elif actor.global_position.distance_to(goal)<0.012:
		climb.pop_front()
		if climb.is_empty():
			motion_mode=Motion.WALK
			vertical_speed=0.0
			_settled()

func _try_climb(direction: Vector3, speed: float) -> bool:
	var radius: float=actor.get_node("CollisionShape3D").shape.radius
	var landing := actor.global_position+direction*(radius*2.0+0.1)
	var hit := floor_hit(actor,landing,config.maximum_step_up+0.03,0.05,config.max_slope_degrees)
	if hit.is_empty(): return false
	landing.y=hit.position.y
	var rise:=landing.y-actor.global_position.y
	if rise<=0.04 or rise>minf(config.maximum_step_up,config.walking_step_height)+0.01 or not _support(landing,true): return false
	if not _within_walk_bounds(landing): return false
	var raised:=Vector3(actor.global_position.x,landing.y+0.01,actor.global_position.z)
	var across:=landing+Vector3.UP*0.01
	if not _motion_clear(actor.global_position,raised-actor.global_position) or not _motion_clear(raised,across-raised): return false
	_record()
	motion_mode=Motion.STEP
	climb.assign([raised,across,landing+Vector3.UP*0.001])
	climb_speed=speed
	blocked=false
	blocked_reason=""
	return true

func walk(at: Vector3, delta: float, speed: float) -> void:
	actor.velocity=Vector3.ZERO
	blocked_reason="" if not blocked else blocked_reason
	if busy():
		continue_climb(delta)
		return
	retry=maxf(0.0,retry-delta)
	if retry>0.0: return
	var offset:=Vector3(at.x-actor.global_position.x,0,at.z-actor.global_position.z)
	if offset.length()<0.001 and absf(at.y-actor.global_position.y)<0.08: return
	var direction:=offset.normalized()
	var plan:=_jump_plan(direction)
	if not plan.is_empty():
		if jump_cooldown>0.0:
			blocked=true
			blocked_reason="JUMP_COOLDOWN"
			retry=minf(config.blocked_retry_seconds,jump_cooldown)
			return
		_begin_jump(plan)
		_advance_air(delta)
		return
	if _rise_ahead>config.walking_step_height: speed=minf(speed,1.5)
	var motion:=direction*minf(speed*delta,offset.length())
	var next:=actor.global_position+motion
	if not _within_walk_bounds(next) or not _support(next):
		blocked=true
		blocked_reason="HOME_BOUNDARY" if not _within_walk_bounds(next) else "NO_WALKABLE_SUPPORT"
		retry=config.blocked_retry_seconds
		return
	var collision:=KinematicCollision3D.new()
	if actor.test_move(actor.global_transform,motion,collision,actor.safe_margin) and collision.get_normal().y < cos(deg_to_rad(config.max_slope_degrees)):
		if _try_climb(direction,speed): continue_climb(delta)
		else:
			blocked=true
			blocked_reason="STEP_OR_JUMP_UNSAFE"
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
		blocked_reason="BODY_COLLISION"
		if _try_climb(direction,speed):
			continue_climb(delta)
			return
		retry=config.blocked_retry_seconds
		actor.velocity=Vector3.ZERO
	else: blocked_reason=""
	if actor.is_on_floor(): _record()
