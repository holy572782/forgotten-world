extends RefCounted
## Debug-only, bounded local A*. Every edge uses the existing safe walk probe;
## actual motion is still owned by EnemyWalk, including its native jump checks.
const CELL:=0.75
const RADIUS:=6.0
const BUDGET:=160
var waypoints: Array[Vector3]=[]
var target:=Vector3.INF
var retry:=0.0
var reason:=""

func goal(actor: CharacterBody3D, at: Vector3, delta: float) -> Vector3:
	retry=maxf(0.0,retry-delta)
	var walker=actor.walker
	if target.is_finite() and walker.horizontal(target,at)>1.0: waypoints.clear()
	target=at
	while not waypoints.is_empty() and walker.horizontal(actor.global_position,waypoints[0])<0.18: waypoints.pop_front()
	var safe_goal:=at
	if walker.horizontal(at,actor.player.global_position)<0.1:
		var toward:=Vector3(at.x-actor.global_position.x,0,at.z-actor.global_position.z)
		var gap: float=actor.get_node("CollisionShape3D").shape.radius+actor.player.get_node("CollisionShape3D").shape.radius+0.15
		safe_goal=actor.global_position+toward.normalized()*maxf(0.0,toward.length()-gap)
	var offset:=Vector3(safe_goal.x-actor.global_position.x,0,safe_goal.z-actor.global_position.z)
	var direct:=actor.global_position+offset.normalized()*minf(3.0,offset.length())
	# Prefer a newly clear full-body corridor over stale corner waypoints.
	if walker.can_reach(direct):
		waypoints.clear()
		reason=""
		return at
	# A safe ballistic step need not be a valid grounded walk edge. Let the
	# existing jump owner execute its own full-body/landing proof.
	if not walker._jump_plan(offset.normalized()).is_empty():
		waypoints.clear()
		reason=""
		return at
	if not waypoints.is_empty():
		if walker.can_reach(waypoints[0]): return waypoints[0]
		waypoints.clear()
	# Do not stop metres before a riser merely because a long grounded probe
	# cannot climb it. Approach safely until EnemyWalk can prove its jump/step.
	var near:=actor.global_position+offset.normalized()*minf(actor.settings.chase_speed*delta,offset.length())
	if walker.can_reach(near):
		reason=""
		return at
	if retry>0.0: return Vector3.INF
	retry=0.75
	waypoints=_find(actor,safe_goal)
	reason="NO_SAFE_LOCAL_ROUTE" if waypoints.is_empty() else "DETOUR"
	return waypoints[0] if not waypoints.is_empty() else Vector3.INF

func _find(actor: CharacterBody3D, goal_at: Vector3) -> Array[Vector3]:
	var walker=actor.walker
	var anchor:=actor.global_position
	var offset:=Vector3(goal_at.x-anchor.x,0,goal_at.z-anchor.z)
	var destination:=anchor+offset.normalized()*minf(4.5,offset.length())
	var open: Array[Vector2i]=[Vector2i.ZERO]
	var points: Dictionary={Vector2i.ZERO:anchor}
	var costs: Dictionary={Vector2i.ZERO:0.0}
	var previous: Dictionary={}
	var closed: Dictionary={}
	var end:=Vector2i.ZERO
	for iteration in range(BUDGET):
		if open.is_empty(): break
		open.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return costs[a]+walker.horizontal(points[a],destination)<costs[b]+walker.horizontal(points[b],destination))
		var current: Vector2i=open.pop_front()
		if walker.horizontal(points[current],destination)<CELL:
			end=current
			break
		closed[current]=true
		for direction in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
			var key: Vector2i=current+direction
			if closed.has(key) or Vector2(key).length()*CELL>RADIUS: continue
			var at:=Vector3(anchor.x+key.x*CELL,points[current].y,anchor.z+key.y*CELL)
			var floor_at: Dictionary=walker._sample(at)
			if floor_at.is_empty(): continue
			at.y=floor_at.position.y
			if not walker.can_reach(at,true,points[current]): continue
			var cost: float=costs[current]+points[current].distance_to(at)
			if costs.has(key) and costs[key]<=cost: continue
			points[key]=at
			costs[key]=cost
			previous[key]=current
			if not open.has(key): open.append(key)
	var result: Array[Vector3]=[]
	while end!=Vector2i.ZERO:
		result.push_front(points[end])
		end=previous[end]
	return result
