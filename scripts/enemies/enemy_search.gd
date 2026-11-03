extends RefCounted
## CHASE/RECOVERY overlay. Owns memory and timers, never AI state or movement.
const Budget=preload("res://scripts/combat/planning_budget.gd")
const OFFSETS=[Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT,Vector3.BACK]
var phase:=""
var anchor:=Vector3.INF
var travel_elapsed:=0.0
var area_elapsed:=-1.0
var _center:=Vector3.INF
var _goal:=Vector3.INF
var _index:=0
var _candidate_frame:=-1
var _floor_retry_at:=0
func stand_off(actor: CharacterBody3D) -> float:
	# Body sizes are known; the hidden target's current coordinates are not read.
	return actor.get_node("CollisionShape3D").shape.radius+actor.player.get_node("CollisionShape3D").shape.radius+0.15

func reset() -> void:
	phase=""; anchor=Vector3.INF; travel_elapsed=0.0; area_elapsed=-1.0
	_center=Vector3.INF; _goal=Vector3.INF; _index=0; _candidate_frame=-1
	_floor_retry_at=0

func tick(actor: CharacterBody3D, delta: float) -> bool:
	if phase.is_empty():
		anchor=actor.last_seen_position
		phase="LAST_SEEN"
	if phase=="DONE": return false
	if area_elapsed>=0.0:
		area_elapsed+=delta
		if area_elapsed>=maxf(0.0,actor.settings.search_duration_seconds):
			phase="DONE"; return false
		return true
	travel_elapsed+=delta
	phase="LAST_SEEN" if actor.sight_lost<actor.settings.sight_loss_seconds else "SEARCH_TRAVEL"
	if _center.is_finite() and not actor.walker.busy() and actor.walker.horizontal(actor.global_position,_center)<=stand_off(actor) and absf(actor.global_position.y-_center.y)<0.2 and Budget.take() and actor._recognized_from(actor.global_position,_center):
		if actor.sight_lost>=actor.settings.sight_loss_seconds:
			if actor.settings.search_duration_seconds<=0.0:
				phase="DONE"; return false
			area_elapsed=0.0; phase="SEARCH_AREA"; _goal=Vector3.INF
			actor._pursuit_route.reset()
		return true
	if travel_elapsed>=maxf(actor.settings.sight_loss_seconds,actor.settings.search_travel_timeout_seconds):
		phase="DONE"; return false
	return true

func goal(actor: CharacterBody3D) -> Vector3:
	if not _center.is_finite():
		if Time.get_ticks_usec()<_floor_retry_at: return Vector3.INF
		if not Budget.take(): return Vector3.INF
		_center=actor.walker.target_floor(anchor,actor.active_attack.target_ground_probe_depth)
		if not _center.is_finite() or not actor.inside_home(_center):
			_center=Vector3.INF; _floor_retry_at=Time.get_ticks_usec()+1500000
			return Vector3.INF
	if area_elapsed<0.0: return _center
	if actor.settings.search_radius<=0.0: return Vector3.INF
	if _goal.is_finite():
		if actor.walker.horizontal(actor.global_position,_goal)>0.2 and actor._pursuit_route.reason!="NO_SAFE_LOCAL_ROUTE": return _goal
		_goal=Vector3.INF
		actor._pursuit_route.reset()
	if _index>=OFFSETS.size() or _candidate_frame==Engine.get_process_frames() or not Budget.take(): return Vector3.INF
	_candidate_frame=Engine.get_process_frames()
	var at: Vector3=_center+OFFSETS[_index]*clampf(actor.settings.search_radius,0.0,4.0)
	_index+=1
	var floor_at: Dictionary=actor.walker._sample(at)
	if floor_at.is_empty(): return Vector3.INF
	var radius: float=actor.get_node("CollisionShape3D").shape.radius
	at.y=floor_at.position.y+radius*(1.0/floor_at.normal.y-1.0)+0.002
	if not actor.inside_home(at) or not actor.walker._support(at) or not actor.walker._motion_clear(at,Vector3.ZERO,true): return Vector3.INF
	_goal=at
	return _goal
