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
static var _budget_frame:=-1
static var _budget_edges:=0
static var _budget_usec:=0

func reset() -> void:
	waypoints.clear()
	_search.clear()
	_decision_until=0
	_failed_origin=Vector3.INF
	target=Vector3.INF
	retry=0.0
	reason=""

func goal(actor: CharacterBody3D, at: Vector3, delta: float) -> Vector3:
	retry=maxf(0.0,retry-delta)
	var walker=actor.walker
	var now:=Time.get_ticks_usec()
	if not _search.is_empty() and (actor.global_position.distance_to(_search.anchor)>0.35 or at.distance_to(target)>0.5):
		_search.clear()
		_decision_until=0
		retry=0.0
	# Cache intent only. EnemyWalk still checks the actual body/support before
	# every movement and proves a fresh jump before takeoff.
	if now<_decision_until and actor.global_position.distance_to(_decision_origin)<0.2 and at.distance_to(_decision_target)<0.35:
		if not _search.is_empty():
			_advance_search(actor)
			if not waypoints.is_empty(): return waypoints[0]
		return at if _decision_direct else _decision
	_decision_origin=actor.global_position
	_decision_target=at
	_decision_until=now+int(DECISION_SECONDS*1000000.0)
	if target.is_finite() and target.distance_to(at)>1.0:
		waypoints.clear()
		_search.clear()
		retry=0.0
	if _failed_origin.is_finite() and (actor.global_position.distance_to(_failed_origin)>0.35 or at.distance_to(_failed_target)>0.5): retry=0.0
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
		_search.clear()
		reason=""
		return _remember(at,true)
	# A safe ballistic step need not be a valid grounded walk edge. Let the
	# existing jump owner execute its own full-body/landing proof.
	if not walker._jump_plan(offset.normalized()).is_empty():
		waypoints.clear()
		_search.clear()
		reason=""
		return _remember(at,true)
	if not waypoints.is_empty():
		if walker.can_reach(waypoints[0]): return _remember(waypoints[0])
		waypoints.clear()
	# Do not stop metres before a riser merely because a long grounded probe
	# cannot climb it. Approach safely until EnemyWalk can prove its jump/step.
	var near:=actor.global_position+offset.normalized()*minf(actor.settings.chase_speed*delta,offset.length())
	if walker.can_reach(near):
		reason=""
		return _remember(at,true)
	if _search.is_empty():
		if retry>0.0: return _remember(Vector3.INF)
		_begin_search(actor,safe_goal)
	_advance_search(actor)
	return _remember(waypoints[0] if not waypoints.is_empty() else Vector3.INF)

func _remember(at: Vector3, direct: bool=false) -> Vector3:
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

func _advance_search(actor: CharacterBody3D) -> void:
	# Shared render-frame budget also covers physics catch-up ticks and multiple
	# enemies. An individual native edge query is atomic; time is checked between edges.
	var frame:=Engine.get_process_frames()
	if frame!=_budget_frame:
		_budget_frame=frame
		_budget_edges=0
		_budget_usec=0
	var started:=Time.get_ticks_usec()
	while not _search.is_empty() and _budget_edges<EDGES_PER_FRAME and _budget_usec+Time.get_ticks_usec()-started<SEARCH_USEC:
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
		_search.edge+=1
		_budget_edges+=1
		if _search.closed.has(key) or Vector2(key).length()*CELL>RADIUS: continue
		var anchor: Vector3=_search.anchor
		var at:=Vector3(anchor.x+key.x*CELL,_search.points[current].y,anchor.z+key.y*CELL)
		var floor_at: Dictionary=actor.walker._sample(at)
		if floor_at.is_empty(): continue
		at.y=floor_at.position.y
		if not actor.walker.can_reach(at,true,_search.points[current]): continue
		var cost: float=_search.costs[current]+_search.points[current].distance_to(at)
		if _search.costs.has(key) and _search.costs[key]<=cost: continue
		_search.points[key]=at
		_search.costs[key]=cost
		_search.previous[key]=current
		if not _search.open.has(key): _search.open.append(key)
	_budget_usec+=Time.get_ticks_usec()-started
