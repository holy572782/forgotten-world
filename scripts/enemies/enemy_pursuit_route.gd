extends RefCounted
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
const PlanningBudget=preload("res://scripts/combat/planning_budget.gd")
## Bounded local A* for debug pursuit and CHASE attack positioning.
## Every edge uses the existing safe walk probe;
## actual motion is still owned by EnemyWalk, including its native jump checks.
const CELL:=0.75
const RADIUS:=6.0
const BUDGET:=160
var waypoints: Array[Vector3]=[]
var target:=Vector3.INF
var retry:=0.0
var reason:=""
const DECISION_SECONDS:=0.15
const FAILED_RETRY_SECONDS:=1.5
const EDGES_PER_FRAME:=8
const SEARCH_USEC:=1200
const DIRECTIONS=[Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
var _decision_until:=0
var _decision_origin:=Vector3.INF
var _decision_target:=Vector3.INF
var _decision:=Vector3.INF
var _decision_direct:=false
var _search: Dictionary={}
var _failed_origin:=Vector3.INF
var _failed_target:=Vector3.INF
var _probe_stage:=-1
var position_reason:=""
var _position: Dictionary={}
const POSITION_OFFSETS=[Vector2(1,0),Vector2(-1,0),Vector2(1,1),Vector2(-1,1),Vector2(1,-0.4),Vector2(-1,-0.4)]

func _mover_stalled(actor: CharacterBody3D) -> bool:
	return actor.walker.blocked and actor.walker.blocked_reason not in ["", "JUMP_COOLDOWN"]

func positioning() -> bool:
	return not _position.is_empty() and _position.phase!=3

func reset() -> void:
	_position.clear()
	position_reason=""
	_reset_route()

func _reset_route() -> void:
	waypoints.clear()
	_search.clear()
	_decision_until=0
	_failed_origin=Vector3.INF
	target=Vector3.INF
	retry=0.0
	reason=""
	_probe_stage=-1

func _work_goal(actor: CharacterBody3D, at: Vector3, delta: float, allow_search: bool=true) -> Vector3:
	retry=maxf(0.0,retry-delta)
	var walker=actor.walker
	var moved:=actor.global_position.distance_to(_decision_origin)>=0.2 or at.distance_to(_decision_target)>=0.35
	if moved:
		_probe_stage=-1
		_decision_until=0
	if not _search.is_empty() and (actor.global_position.distance_to(_search.anchor)>0.35 or at.distance_to(target)>0.5):
		_search.clear()
		retry=0.0
	if _probe_stage<0 and not moved and Time.get_ticks_usec()<_decision_until:
		if not _search.is_empty():
			_advance_search(actor)
			if not waypoints.is_empty(): return waypoints[0]
		return at if _decision_direct else _decision
	if _probe_stage<0:
		_decision_origin=actor.global_position
		_decision_target=at
		_probe_stage=0
	if target.is_finite() and target.distance_to(at)>1.0:
		waypoints.clear()
		_search.clear()
		retry=0.0
	if _failed_origin.is_finite() and (actor.global_position.distance_to(_failed_origin)>0.35 or at.distance_to(_failed_target)>0.5): retry=0.0
	target=at
	while not waypoints.is_empty() and walker.horizontal(actor.global_position,waypoints[0])<0.18: waypoints.pop_front()
	var offset:=Vector3(at.x-actor.global_position.x,0,at.z-actor.global_position.z)
	var safe_goal:=at
	if walker.horizontal(at,actor.player.global_position)<0.1:
		var gap: float=actor.get_node("CollisionShape3D").shape.radius+actor.player.get_node("CollisionShape3D").shape.radius+0.15
		safe_goal=actor.global_position+offset.normalized()*maxf(0.0,offset.length()-gap)
	var safe_offset:=Vector3(safe_goal.x-actor.global_position.x,0,safe_goal.z-actor.global_position.z)
	while _probe_stage<4:
		if not PlanningBudget.take():
			reason="PLANNING_BUDGET (PREFLIGHT)"
			return Vector3.INF
		var stage:=_probe_stage
		_probe_stage+=1
		var clear:=false
		match stage:
			0:
				if not _mover_stalled(actor): clear=walker.can_reach(actor.global_position+safe_offset.normalized()*minf(CELL,safe_offset.length()))
			1: clear=not walker._jump_plan(safe_offset.normalized()).is_empty()
			2:
				if not waypoints.is_empty():
					if walker.can_reach(waypoints[0]): return _remember(waypoints[0])
					waypoints.clear()
			3:
				if not _mover_stalled(actor): clear=walker.can_reach(actor.global_position+safe_offset.normalized()*minf(actor.settings.chase_speed*delta,safe_offset.length()))
		if clear:
			waypoints.clear()
			_search.clear()
			reason=""
			return _remember(at,true)
	if _search.is_empty():
		if not allow_search:
			reason="DIRECT_BLOCKED"
			return _remember(Vector3.INF)
		var diagnostic:=Work.for_body(actor)
		if diagnostic!=null and not diagnostic.local_astar_enabled:
			reason="DIAGNOSTIC_ASTAR_DISABLED"
			return _remember(Vector3.INF)
		if retry>0.0: return _remember(Vector3.INF)
		_begin_search(actor,safe_goal)
	_advance_search(actor)
	return _remember(waypoints[0] if not waypoints.is_empty() else Vector3.INF)

func _remember(at: Vector3, direct: bool=false) -> Vector3:
	_probe_stage=-1
	_decision_until=Time.get_ticks_usec()+int(DECISION_SECONDS*1000000.0)
	_decision=at
	_decision_direct=direct
	return at

func _begin_search(actor: CharacterBody3D, goal_at: Vector3) -> void:
	var anchor:=actor.global_position
	var offset:=Vector3(goal_at.x-anchor.x,0,goal_at.z-anchor.z)
	var destination:=anchor+offset.normalized()*minf(4.5,offset.length())
	_search={"anchor":anchor,"destination":destination,"open":[Vector2i.ZERO],"points":{Vector2i.ZERO:anchor},"costs":{Vector2i.ZERO:0.0},"previous":{},"closed":{},"current":Vector2i.ZERO,"edge":8,"expanded":0}
	reason="NO_SAFE_LOCAL_ROUTE (SEARCHING)"

func _finish_search(end: Vector2i) -> void:
	while end!=Vector2i.ZERO:
		waypoints.push_front(_search.points[end])
		end=_search.previous[end]
	_failed_origin=_search.anchor
	_failed_target=target
	_search.clear()
	retry=FAILED_RETRY_SECONDS
	reason="NO_SAFE_LOCAL_ROUTE" if waypoints.is_empty() else "DETOUR"
	_decision_until=0

func _work_advance_search(actor: CharacterBody3D) -> void:
	var diagnostic:=Work.for_body(actor)
	if diagnostic!=null and not diagnostic.local_astar_enabled:
		_search.clear()
		reason="DIAGNOSTIC_ASTAR_DISABLED"
		return
	# Shared render-frame budget also covers physics catch-up ticks and multiple
	# enemies. An individual native edge query is atomic; time is checked between edges.
	while not _search.is_empty() and PlanningBudget.allowed():
		if _search.edge>=8:
			if _search.open.is_empty() or _search.expanded>=BUDGET:
				_finish_search(Vector2i.ZERO)
				break
			var best:=0
			var score:=INF
			for index in range(_search.open.size()):
				var candidate: Vector2i=_search.open[index]
				var value: float=_search.costs[candidate]+actor.walker.horizontal(_search.points[candidate],_search.destination)
				if value<score:
					score=value
					best=index
			_search.current=_search.open[best]
			_search.open.remove_at(best)
			if actor.walker.horizontal(_search.points[_search.current],_search.destination)<CELL:
				_finish_search(_search.current)
				break
			_search.closed[_search.current]=true
			_search.edge=0
			_search.expanded+=1
		var current: Vector2i=_search.current
		var key: Vector2i=current+DIRECTIONS[_search.edge]
		if not PlanningBudget.take(): break
		_search.edge+=1
		if _search.closed.has(key) or Vector2(key).length()*CELL>RADIUS: continue
		var anchor: Vector3=_search.anchor
		var at:=Vector3(anchor.x+key.x*CELL,_search.points[current].y,anchor.z+key.y*CELL)
		var floor_at: Dictionary=actor.walker._sample(at)
		if floor_at.is_empty(): continue
		at.y=floor_at.position.y
		if not actor.inside_home(at): continue
		if not actor.walker.can_reach(at,true,_search.points[current]): continue
		var cost: float=_search.costs[current]+_search.points[current].distance_to(at)
		if _search.costs.has(key) and _search.costs[key]<=cost: continue
		_search.points[key]=at
		_search.costs[key]=cost
		_search.previous[key]=current
		if not _search.open.has(key): _search.open.append(key)

func goal(actor: CharacterBody3D, at: Vector3, delta: float, allow_search: bool=true) -> Vector3:
	var started:=Work.start(actor)
	PlanningBudget.begin()
	var result: Vector3=_work_goal(actor,at,delta,allow_search)
	PlanningBudget.end()
	Work.finish(actor,"route.goal",started)
	return result

func _advance_search(actor: CharacterBody3D) -> void:
	var started:=Work.start(actor)
	PlanningBudget.begin()
	_work_advance_search(actor)
	PlanningBudget.end()
	Work.finish(actor,"route.astar",started)

func combat_goal(actor: CharacterBody3D, delta: float) -> Vector3:
	var started:=Work.start(actor)
	PlanningBudget.begin()
	var result:=_combat_goal(actor,delta)
	PlanningBudget.end()
	Work.finish(actor,"route.position",started)
	return result

func _combat_goal(actor: CharacterBody3D, delta: float) -> Vector3:
	# CHASE-only hints. Actual walking and attack entry always prove safety afresh.
	if actor.state!=actor.State.CHASE or not actor.player_alive(): return Vector3.INF
	var at: Vector3=actor.player.global_position
	var now:=Time.get_ticks_usec()
	if _position.is_empty() or at.distance_to(_position.target)>0.35:
		_reset_route()
		_position={"origin":actor.global_position,"target":at,"phase":0,"index":0,"frame":-1,"until":0,"goal":Vector3.INF}
	if _position.phase==3:
		if now<_position.until:
			position_reason="POSITION_FAILED (RETRY)"
			return Vector3.INF
		_position.clear()
		return Vector3.INF
	if _position.phase==2:
		var destination: Vector3=_position.goal
		if actor.walker.horizontal(actor.global_position,destination)<0.12:
			_position.clear()
			return Vector3.INF
		if _position.get("travelling",false) and actor.walker.blocked:
			_position.phase=1
			_reset_route()
			return Vector3.INF
		position_reason="POSITION_MOVING"
		var route:=goal(actor,destination,delta)
		if route.is_finite(): _position.travelling=true
		elif reason=="NO_SAFE_LOCAL_ROUTE":
			_position.phase=1
			_reset_route()
		else: position_reason="POSITION_ROUTE_PENDING"
		return route
	if _position.phase==0:
		var direct:=goal(actor,at,delta,false)
		if direct.is_finite() and not _mover_stalled(actor):
			position_reason="POSITION_DIRECT"
			return direct
		if reason.begins_with("PLANNING_BUDGET"):
			position_reason="POSITION_PENDING (DIRECT)"
			return Vector3.INF
		_position.phase=1
		_position.origin=actor.global_position
		_reset_route()
	if _position.index<POSITION_OFFSETS.size()*2:
		position_reason="POSITION_SEARCHING %s/%s" % [_position.index,POSITION_OFFSETS.size()*2]
		if _position.frame==Engine.get_process_frames() or not PlanningBudget.take(): return Vector3.INF
		_position.frame=Engine.get_process_frames()
		var toward:=Vector3(at.x-_position.origin.x,0,at.z-_position.origin.z).normalized()
		var side:=toward.cross(Vector3.UP)
		var offset: Vector2=POSITION_OFFSETS[_position.index%POSITION_OFFSETS.size()]
		var distance:=CELL*(1.0 if _position.index<POSITION_OFFSETS.size() else 2.0)
		_position.index+=1
		var candidate: Vector3=_position.origin+(side*offset.x+toward*offset.y)*distance
		var floor_at: Dictionary=actor.walker._sample(candidate)
		if floor_at.is_empty(): return Vector3.INF
		var radius: float=actor.get_node("CollisionShape3D").shape.radius
		candidate.y=floor_at.position.y+radius*(1.0/floor_at.normal.y-1.0)+0.002
		if not actor.inside_home(candidate) or not actor.walker._support(candidate): return Vector3.INF
		if not actor.walker._motion_clear(candidate,Vector3.ZERO,true) or not actor.firing_position_clear(candidate): return Vector3.INF
		if not actor.walker.can_reach(candidate): return Vector3.INF
		_position.phase=2
		_position.goal=candidate
		_position.travelling=false
		_reset_route()
		position_reason="POSITION_ROUTE_PENDING"
		return Vector3.INF
	# No immediate shooting/striking point: reuse the bounded incremental A*
	# toward the target. CHASE stops as soon as a real attack becomes available.
	position_reason="POSITION_DETOUR"
	var route:=goal(actor,at,delta)
	if not route.is_finite() and reason=="NO_SAFE_LOCAL_ROUTE":
		_position.phase=3
		_position.until=now+int(FAILED_RETRY_SECONDS*1000000.0)
		position_reason="POSITION_NO_SAFE_ROUTE"
	return route
