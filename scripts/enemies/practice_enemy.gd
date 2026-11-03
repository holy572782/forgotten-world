extends CharacterBody3D
const Walker = preload("res://scripts/enemies/enemy_walk.gd")
const PursuitRoute = preload("res://scripts/enemies/enemy_pursuit_route.gd")
const StrikeGeometry = preload("res://scripts/enemies/enemy_melee_geometry.gd")
const Settings = preload("res://scripts/enemies/enemy_settings.gd")
const AttackData = preload("res://scripts/enemies/enemy_attack_data.gd")
const CastingVisual = preload("res://scripts/effects/mage_cast_visual.gd")
const Projectile = preload("res://scripts/enemies/practice_projectile.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const Sweep = preload("res://scripts/combat/melee_sweep.gd")
const Elevation=preload("res://scripts/combat/elevation_path.gd")
const Flight=preload("res://scripts/combat/combat_flight.gd")
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
const PlanningBudget=preload("res://scripts/combat/planning_budget.gd")
const SearchBehavior=preload("res://scripts/enemies/enemy_search.gd")
var _search_behavior:=SearchBehavior.new()
var _flight:=Flight.new()
var _air_return_reason:=""
var _jump_arrived:=false
# RETURN = home/leash return; DASH_RETURN = attack_anchor.
enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVERY, RETURN, DEAD, DASH_APPROACH, DASH_RETURN }
signal attack_started
signal attack_warning_started
signal aim_committed
signal projectile_released(shot: CharacterBody3D)
@export var settings: Settings = preload("res://resources/enemies/melee_practice.tres")
@export var player: CharacterBody3D
@export var show_debug_state := true
@export var show_attack_diagnostics := false
@export var debug_unlimited_pursuit := false
@export var performance_diagnostics: Work
var _pursuit_route:=PursuitRoute.new()
var _diagnostics_shown:=false
var attack_start_reason:=""
var attack_abort_reason:=""
var attack_hit_reason:=""
var _availability_frame:=-1
var _availability_until:=0
var _availability_origin:=Vector3.INF
var _availability_target:=Vector3.INF
var _availability_attack: Resource
var _availability_unlimited:=false
var _availability_value:=false
var _availability_reason:=""
var _availability_blocker:=""
var _eligibility_job: Dictionary={}
var _planning_async:=false
var _perception_frame:=-1
var _seen_now:=false
var _distance_now:=INF
var attack_blocker:=""
var last_hit_blocker:=""

func _work_update_attack_debug() -> void:
	if performance_diagnostics!=null and not performance_diagnostics.details_enabled:
		debug_label.visible=false
		return
	debug_label.visible=true
	var visible_goal: Vector3=last_seen_position if not _search_behavior.phase.is_empty() else (player.global_position if player_alive() else global_position)
	var distance:=Walker.horizontal(global_position,visible_goal) if player_alive() else INF
	var blocked: String=_pursuit_route.reason if debug_unlimited_pursuit and not _pursuit_route.reason.is_empty() else walker.blocked_reason
	debug_label.text=State.keys()[state]+"  PURSUIT: "+("UNLIMITED" if debug_unlimited_pursuit else "BOUNDED")+"\nDIST: %.2fm  MOVE: %s" % [distance,blocked]+"\nSTART(now): "+_current_readiness()+"\nPOSITION: "+_pursuit_route.position_reason+"\nBLOCKER: "+attack_blocker+"\nABORT(last): "+attack_abort_reason+"\nHIT(last): "+attack_hit_reason+" "+last_hit_blocker
	debug_label.text+="\nACTION: "+(_search_behavior.phase if not _search_behavior.phase.is_empty() else ("DETOUR" if not _pursuit_route.waypoints.is_empty() or not _pursuit_route._search.is_empty() else State.keys()[state]))
	debug_label.text+="\nROUTE: "+_pursuit_route.reason
	if not _search_behavior.phase.is_empty(): debug_label.text+="\nMEMORY: %s  TRAVEL: %.2fs  AREA: %.2fs" % [last_seen_position,_search_behavior.travel_elapsed,maxf(0.0,_search_behavior.area_elapsed)]

func _current_readiness() -> String:
	if not player_alive(): return "NO_TARGET"
	if state==State.DEAD: return "DEAD"
	if not _search_behavior.phase.is_empty(): return _search_behavior.phase
	if walker.busy(): return "ACTOR_AIRBORNE"
	if state==State.WINDUP:
		if not aim_locked: return "WINDUP_TRACKING"
		if _aim_plan_ready: return "LOCKED_READY"
		return _pending_text(_aim_job)
	if state!=State.CHASE: return State.keys()[state]
	if performance_diagnostics!=null and not performance_diagnostics.attack_planning_enabled: return "DIAGNOSTIC_ATTACK_DISABLED"
	var sight:=_seen_now if _perception_frame==Engine.get_physics_frames() else has_sight()
	if not sight: return "TARGET_NOT_VISIBLE"
	var distance:=_distance_now if _perception_frame==Engine.get_physics_frames() else (Walker.horizontal(global_position,player.global_position) if active_attack.weapon!=null else global_position.distance_to(player.global_position))
	if distance>engagement_range(): return "OUT_OF_RANGE"
	if _in_place_reach(player.global_position): return "READY_IN_PLACE"+(" (COOLDOWN)" if cooldown>0.0 else "")
	if _pursuit_route.positioning(): return "POSITIONING"
	if global_position.distance_to(_availability_origin)>=0.08 or player.global_position.distance_to(_availability_target)>=0.08: return "NEEDS_RECHECK"
	if not _eligibility_job.is_empty(): return _pending_text(_eligibility_job)
	if _availability_until<Time.get_ticks_usec(): return "NEEDS_RECHECK"
	return _availability_reason+(" (COOLDOWN)" if cooldown>0.0 else "")

func _pending_text(job: Dictionary) -> String:
	var age:=float(Time.get_ticks_usec()-int(job.get("started",Time.get_ticks_usec())))/1000000.0
	return ("PLANNING_STALLED" if age>2.0 else "PLANNING_PENDING")+" %.2fs" % age

func _work_terrain_plan(at: Vector3) -> Dictionary:
	var diagnostic: Dictionary={"enabled":true}
	var result:=Elevation.attack(self,at,active_attack.weapon,settings.path,active_attack.stop_distance,active_attack.weapon.motion,Vector3.INF,diagnostic)
	attack_start_reason="OK" if not result.is_empty() else diagnostic.get("reason","NO_SAFE_LANDING")
	return result
@onready var health: HealthComponent = $HealthComponent
@onready var targetable: Node3D = $Targetable
var state := State.IDLE
var home := Vector3.ZERO
var attack_anchor := Vector3.ZERO
var aimed_position := Vector3.ZERO
var dash_destination := Vector3.ZERO
var facing := Vector3.FORWARD
var elapsed := 0.0
var cooldown := 0.0
var sight_lost := 0.0
var attack_count := 0
var attack_executed := false
var last_result := ""
var shots: Array[Node] = []
var telegraph: MeshInstance3D
var dash_guide: MeshInstance3D
var debug_label: Label3D
var active_attack: AttackData
var _travel_start := Vector3.ZERO
var _travel_elapsed := 0.0
var _held_elapsed := 0.0
var _return_after_recovery := false
var _in_place := false
var _pursuit_moving := false
var _pursuit_step_active := false
var _pursuit_destination := Vector3.ZERO
var aim_locked := false
var _forced_in_place := false
var _commit_minimum := 0.0
var aim_lock_elapsed := -1.0
var _locked_floor := Vector3.INF
var _locked_plan: Dictionary = {}
var _aim_job: Dictionary = {}
var _aim_plan_ready := false
var _aim_plan_frame := -1
var combat_move_mode := ""
var _combat_move_elapsed := 0.0
var _combat_move_duration := 0.0
var _combat_move_goal := Vector3.ZERO
var _combat_move_blocked := false
var _combat_move_index := 0
var _ranged_pursuit_active := false
var walker: RefCounted
var last_seen_position := Vector3.ZERO
var _last_seen_valid := false

func _ready() -> void:
	process_physics_priority = 1 # Player reserves a stable target before enemy motion.
	home = global_position
	walker = Walker.new(self)
	last_seen_position = home
	active_attack = settings.attack.snapshot()
	health.depleted.connect(_die)
	if active_attack.magic_visual != null:
		var casting := CastingVisual.new()
		casting.name = "CastingCircle"
		add_child(casting)
	telegraph = MeshInstance3D.new()
	add_child(telegraph)
	dash_guide = MeshInstance3D.new()
	add_child(dash_guide)
	debug_label = Label3D.new()
	debug_label.position.y = 2.95
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.font_size = 26
	debug_label.pixel_size = 0.008
	add_child(debug_label)
	_refresh_visuals()

func player_alive() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and player.get_node("HealthComponent").current_hp > 0.0

func _work_has_sight() -> bool:
	if player_alive() and active_attack!=null and (active_attack.kind==AttackData.Kind.PROJECTILE or (active_attack.weapon!=null and active_attack.weapon.hit_height_up>=0.0)):
		return _recognized_from(global_position,player.global_position)
	return player_alive() and Path.sight(self, player.global_position)

func _recognized_from(from: Vector3, at: Vector3) -> bool:
	var space:=get_world_3d().direct_space_state
	var blocker:=""
	for height in [0.8,1.6]:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(from+Vector3.UP*height,at+Vector3.UP*height,1))
		if hit.is_empty(): return true
		blocker=str(hit.collider.get_path())
	if show_attack_diagnostics and from.is_equal_approx(global_position): attack_blocker=blocker
	return false

func engagement_range() -> float:
	return settings.attack.weapon.attack_range if settings.attack.weapon != null else settings.attack_start_distance

func current_weapon_visual() -> Resource:
	if active_attack != null and active_attack.weapon != null: return active_attack.weapon.attack_visual
	return settings.visual.weapon_visual if settings.visual != null else null

func _weapon_strike_clear(at: Vector3) -> bool:
	if not Sweep.contains(global_position, facing, at, active_attack.weapon): return false
	var report:=StrikeGeometry.report(self,at)
	attack_blocker=report.blocker
	return report.clear

func blade_plan_clear(at: Vector3, from: Vector3) -> bool:
	return StrikeGeometry.report(self,at,from).clear

func _work_physics_process(delta: float) -> void:
	attack_blocker=""
	if state == State.DEAD: return
	if health.current_hp <= 0.0:
		_die(null)
		return
	if not player_alive():
		clear_shots()
		if state != State.RETURN and state != State.IDLE: _set_state(State.RETURN)
	elapsed += delta
	walker.advance_cooldown(delta)
	cooldown = maxf(0.0, cooldown - delta)
	var sight := has_sight()
	var memory_only: bool=not sight and not debug_unlimited_pursuit and state in [State.CHASE,State.RECOVERY]
	var known_position: Vector3=last_seen_position if memory_only else (player.global_position if player_alive() else global_position)
	var distance := global_position.distance_to(known_position) if player_alive() else INF
	if player_alive() and active_attack.weapon!=null: distance=Walker.horizontal(global_position,known_position)
	_seen_now=sight
	_distance_now=distance
	_perception_frame=Engine.get_physics_frames()
	if _diagnostics_shown and not show_attack_diagnostics: _refresh_visuals()
	_diagnostics_shown=show_attack_diagnostics
	debug_label.visible=(show_debug_state or show_attack_diagnostics) and (performance_diagnostics==null or performance_diagnostics.details_enabled)
	if debug_unlimited_pursuit and player_alive(): _return_after_recovery=false
	if debug_unlimited_pursuit and player_alive() and state==State.RETURN:
		walker.returning=false
		_return_after_recovery=false
		_set_state(State.CHASE)
	if show_attack_diagnostics:
		if walker.busy(): attack_start_reason="ACTOR_AIRBORNE"
		elif not sight: attack_start_reason="TARGET_NOT_VISIBLE"
		elif distance>engagement_range(): attack_start_reason="OUT_OF_RANGE"
	sight_lost = 0.0 if sight else sight_lost + delta
	if sight:
		last_seen_position = player.global_position
		_last_seen_valid = true
	if (sight or debug_unlimited_pursuit) and not _search_behavior.phase.is_empty():
		_search_behavior.reset()
		_pursuit_route.reset()
	var searching: bool=memory_only and player_alive() and _last_seen_valid
	var beyond_leash := not inside_home(known_position) if player_alive() else true
	beyond_leash = beyond_leash or not inside_home(global_position)
	var committed := _projectile_cast_committed() or (aim_locked and state in [State.WINDUP,State.DASH_APPROACH,State.ATTACK,State.DASH_RETURN])
	if committed and beyond_leash: _return_after_recovery = true
	var leashed := (beyond_leash or (sight_lost >= settings.sight_loss_seconds and not searching)) and not committed and not (debug_unlimited_pursuit and player_alive())
	# Complete an attack return before going home; never replace its anchor.
	if leashed and state in [State.CHASE, State.WINDUP]: _set_state(State.RETURN)
	elif leashed and state in [State.DASH_APPROACH, State.ATTACK, State.DASH_RETURN]:
		_return_after_recovery = true
		if state != State.DASH_RETURN: _begin_attack_return("Leash or sight lost")
	if leashed and state == State.RECOVERY and not _return_after_recovery: _set_state(State.RETURN)
	if searching and state in [State.CHASE,State.RECOVERY]:
		var search_started:=Work.start(self)
		PlanningBudget.begin()
		var continues: bool=_search_behavior.tick(self,delta)
		PlanningBudget.end()
		Work.finish(self,"enemy.search_tick",search_started)
		if not continues and (state!=State.RECOVERY or elapsed>=active_attack.recovery_seconds): _set_state(State.RETURN)
	if walker.busy() and state in [State.CHASE,State.RECOVERY,State.RETURN]:
		if locomotion_held() and not walker.airborne(): velocity = Vector3.ZERO
		else:
			walker.continue_climb(delta)
			_face_walk_velocity()
		return
	if searching and state in [State.CHASE,State.RECOVERY]:
		_search_step(delta)
		if state==State.RECOVERY and elapsed>=active_attack.recovery_seconds: _set_state(State.CHASE)
		_update_telegraph_position()
		return
	match state:
		State.IDLE:
			if (debug_unlimited_pursuit and player_alive()) or (sight and distance <= settings.detection_radius and inside_home(player.global_position,settings.leash_reentry_margin)): _set_state(State.CHASE)
		State.CHASE:
			var melee_available:=false
			var positioning:=_pursuit_route.positioning()
			if sight and active_attack.kind!=AttackData.Kind.PROJECTILE and distance<=engagement_range():
				if _in_place_reach(player.global_position) or not positioning: melee_available=_attack_position_available()
			if not sight:
				velocity = Vector3.ZERO
				if debug_unlimited_pursuit and player_alive(): _walk_to_attack_position(delta)
				elif _last_seen_valid and sight_lost < settings.sight_loss_seconds: _walk_towards(last_seen_position,delta)
			elif active_attack.kind == AttackData.Kind.PROJECTILE: _ranged_chase_step(delta, distance, sight, true)
			elif positioning and not melee_available: _walk_to_attack_position(delta)
			elif distance<=engagement_range() and not melee_available and attack_start_reason=="PLANNING_PENDING": velocity=Vector3.ZERO
			elif distance <= engagement_range() and cooldown <= 0.0 and melee_available: _start_windup()
			elif distance > engagement_range() or not melee_available:
				if not melee_available and distance<=engagement_range(): _walk_to_attack_position(delta)
				elif _can_pursue() and attack_count > 0: _walk_towards(player.global_position,delta,clampf(settings.pursuit_speed,0.1,10.0))
				else: _walk_towards(player.global_position, delta)
			elif _can_pursue() and attack_count > 0: _post_attack_step(delta)
			else: velocity = Vector3.ZERO # Stopped cooldown uses Idle, not a stale walk velocity.
		State.WINDUP:
			_windup_step(delta)
		State.DASH_APPROACH: _dash_step(delta, false)
		State.ATTACK:
			if not attack_executed and elapsed >= active_attack.hit_delay_seconds: _execute_attack()
			var final_wait: float = active_attack.weapon.motion.final_attack_wait if active_attack.weapon != null else 0.0
			if state == State.ATTACK and elapsed >= maxf(active_attack.attack_seconds, active_attack.hit_delay_seconds) + final_wait:
				if active_attack.kind == AttackData.Kind.DASH_MELEE: _begin_attack_return("")
				else: _set_state(State.RECOVERY)
		State.DASH_RETURN: _dash_step(delta, true)
		State.RECOVERY:
			if active_attack.kind == AttackData.Kind.PROJECTILE and not _return_after_recovery: _ranged_chase_step(delta, distance, sight, false)
			elif _can_pursue() and attack_count > 0 and not _return_after_recovery: _post_attack_step(delta)
			else:
				velocity = Vector3.ZERO
				_stop_pursuit()
			if elapsed >= active_attack.recovery_seconds: _set_state(State.RETURN if _return_after_recovery else State.CHASE)
		State.RETURN:
			if global_position.distance_to(home) <= 0.04: _set_state(State.IDLE)
			else: _walk_towards(walker.home_goal(), delta)
	_update_telegraph_position()

func _horizontal_direction(at: Vector3) -> Vector3:
	var direction := at - global_position
	direction.y = 0.0
	return direction.normalized() if not direction.is_zero_approx() else facing

func inside_home(at: Vector3, margin: float = 0.0) -> bool:
	return debug_unlimited_pursuit or Walker.horizontal(home,at) <= maxf(0.0,settings.leash_radius-margin)

func _attack_position_available() -> bool:
	if performance_diagnostics!=null and not performance_diagnostics.attack_planning_enabled:
		attack_start_reason="DIAGNOSTIC_ATTACK_DISABLED"
		return false
	var frame:=Engine.get_physics_frames()
	var now:=Time.get_ticks_usec()
	var unchanged:=active_attack==_availability_attack and debug_unlimited_pursuit==_availability_unlimited and global_position.distance_to(_availability_origin)<0.08 and player.global_position.distance_to(_availability_target)<0.08
	if unchanged and (_planning_async or _availability_reason!="PLANNING_PENDING") and (frame==_availability_frame or now<_availability_until):
		attack_start_reason=_availability_reason
		attack_blocker=_availability_blocker
		return _availability_value
	_availability_frame=frame
	_availability_origin=global_position
	_availability_target=player.global_position
	_availability_attack=active_attack
	_availability_unlimited=debug_unlimited_pursuit
	_availability_value=_evaluate_attack_position()
	_availability_until=0 if attack_start_reason=="PLANNING_PENDING" else Time.get_ticks_usec()+(150000 if _availability_value else 400000)
	_availability_reason=attack_start_reason
	_availability_blocker=attack_blocker
	return _availability_value

func _evaluate_attack_position() -> bool:
	# Eligibility cache never authorizes a launch: _start_windup/_plan_attack,
	# the committed dash, actual movement and hit retain fresh safety checks.
	if not player_alive() or not (_seen_now if _planning_async else has_sight()):
		attack_start_reason="TARGET_NOT_VISIBLE"
		return false
	if active_attack.weapon == null:
		if active_attack.kind != AttackData.Kind.PROJECTILE: return true
		var clear := _projectile_path_clear(player.global_position)
		attack_start_reason = "OK" if clear else "PROJECTILE_PATH_BLOCKED"
		return clear
	if _in_place_reach(player.global_position):
		_eligibility_job={}
		if show_attack_diagnostics: attack_blocker=StrikeGeometry.report(self,player.global_position).blocker
		attack_start_reason="READY_IN_PLACE"
		return true # Recognition is checked by CHASE/entry; obstruction belongs to the hit.
	if active_attack.weapon.elevation_travel!=null:
		var floor_at: Vector3=walker.target_floor(player.global_position,active_attack.target_ground_probe_depth)
		if not floor_at.is_finite():
			attack_start_reason="TARGET_FLOOR_MISSING"
			return false
		if not _planning_async:
			var immediate:=_terrain_plan(floor_at)
			return not immediate.is_empty() and inside_home(immediate.destination)
		if _eligibility_job.is_empty() or _eligibility_job.weapon!=active_attack.weapon or global_position.distance_to(_eligibility_job.origin)>0.5 or floor_at.distance_to(_eligibility_job.target)>0.5:
			_eligibility_job=Elevation.new_attack_job()
			_eligibility_job.merge({"weapon":active_attack.weapon,"origin":global_position,"target":floor_at,"frame":-1,"started":Time.get_ticks_usec()})
		if _eligibility_job.frame==Engine.get_process_frames() or not PlanningBudget.take():
			attack_start_reason="PLANNING_PENDING"
			return false
		_eligibility_job.frame=Engine.get_process_frames()
		PlanningBudget.begin()
		var diagnostic: Dictionary={"enabled":true,"reason":_eligibility_job.reason}
		Elevation.attack_step(self,floor_at,active_attack.weapon,settings.path,active_attack.stop_distance,active_attack.weapon.motion,Vector3.INF,_eligibility_job,diagnostic)
		PlanningBudget.end()
		if not _eligibility_job.done:
			attack_start_reason="PLANNING_PENDING"
			return false
		attack_start_reason="OK" if not _eligibility_job.result.is_empty() else _eligibility_job.reason
		var plan: Dictionary=_eligibility_job.result
		_eligibility_job={}
		return not plan.is_empty() and inside_home(plan.destination)
	var ground: Vector3 = walker.target_floor(player.global_position,active_attack.target_ground_probe_depth)
	if not ground.is_finite(): return false
	var toward := _horizontal_direction(player.global_position)
	return (Sweep.contains(global_position,toward,ground,active_attack.weapon) and StrikeGeometry.clear(self,player.global_position)) or Path.strike_clear(self,ground,settings.path)

func _projectile_cast_committed() -> bool:
	return active_attack != null and active_attack.kind == AttackData.Kind.PROJECTILE and active_attack.commit_projectile_on_windup and state in [State.WINDUP,State.ATTACK]

func locomotion_held() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.combat): return false
	var combat = player.combat
	return combat.is_busy() and (combat.target == targetable or combat.queued_attack_target == targetable)

func _walk_towards(at: Vector3, delta: float, speed_override: float = -1.0, local_goal: bool=false) -> void:
	velocity = Vector3.ZERO
	if locomotion_held(): return # Chase waits but its attack state machine still runs.
	if walker.retry>0.0 and not walker.busy():
		walker.retry=maxf(0.0,walker.retry-delta)
		return # Do not run route/jump preflights while the mover is waiting.
	var needs_route: bool=debug_unlimited_pursuit or state==State.CHASE
	if not local_goal and needs_route and player_alive() and state in [State.CHASE,State.RECOVERY]:
		at=_pursuit_route.goal(self,at,delta)
		if not at.is_finite(): return
	var direction := _horizontal_direction(at) # Preserve intent before a one-tick goal is consumed.
	var speed := settings.chase_speed if speed_override < 0.0 else speed_override
	walker.walk(at,delta,speed)
	_face_walk_velocity(direction)

func _walk_to_attack_position(delta: float) -> void:
	velocity=Vector3.ZERO
	if locomotion_held(): return
	if walker.retry>0.0:
		walker.retry=maxf(0.0,walker.retry-delta)
		return
	var goal: Vector3=_pursuit_route.combat_goal(self,delta)
	if _pursuit_route.positioning(): _eligibility_job={}
	if goal.is_finite(): _walk_towards(goal,delta,-1.0,true)

func _search_step(delta: float) -> void:
	velocity=Vector3.ZERO
	if _search_behavior.phase=="DONE" or locomotion_held(): return
	if walker.retry>0.0:
		walker.retry=maxf(0.0,walker.retry-delta); return
	var started:=Work.start(self)
	PlanningBudget.begin()
	var destination: Vector3=_search_behavior.goal(self)
	var route:=Vector3.INF
	if destination.is_finite(): route=_pursuit_route.goal(self,destination,delta,true,false,_search_behavior.stand_off(self) if _search_behavior.area_elapsed<0.0 else 0.0)
	PlanningBudget.end()
	Work.finish(self,"enemy.search",started)
	if route.is_finite(): _walk_towards(route,delta,-1.0,true)

func firing_position_clear(at: Vector3) -> bool:
	if not player_alive(): return false
	if not _recognized_from(at,player.global_position): return false
	if active_attack.kind==AttackData.Kind.PROJECTILE:
		return at.distance_to(player.global_position)<=engagement_range() and _projectile_path_clear(player.global_position,at)
	return _in_place_reach(player.global_position,at) and StrikeGeometry.report(self,player.global_position,at).clear

func _face_walk_velocity(climb_direction: Vector3 = Vector3.ZERO) -> void:
	var direction := Vector3(velocity.x,0.0,velocity.z)
	if direction.length_squared()>0.0001: facing = direction.normalized()
	elif walker.busy() and absf(velocity.y)>0.01 and not climb_direction.is_zero_approx(): facing = climb_direction

func _ranged_chase_step(delta: float, distance: float, sight: bool, allow_attack: bool) -> void:
	velocity = Vector3.ZERO
	if not sight:
		if debug_unlimited_pursuit and player_alive() and state==State.CHASE: _walk_to_attack_position(delta)
		elif debug_unlimited_pursuit and player_alive(): _walk_towards(player.global_position,delta)
		return
	var reach := engagement_range()
	# Screen/range eligibility is not a safe firing position. Reuse the cached
	# muzzle/terrain proof, with a fresh proof at warning entry and actual release.
	var firing_clear := distance <= reach and _attack_position_available()
	if allow_attack and distance <= reach and cooldown <= 0.0 and firing_clear:
		_start_windup()
		return
	var margin := clampf(settings.ranged_stop_margin, 0.0, minf(1.0, reach*0.5))
	if distance > reach or not firing_clear: _ranged_pursuit_active = true
	elif distance <= reach - margin: _ranged_pursuit_active = false
	if not _ranged_pursuit_active: return
	if state==State.CHASE:
		# Route toward the real target, not a one-tick point a few centimetres
		# ahead. A* would otherwise regard that point as already reached when a
		# ramp edge blocks direct movement. Range/shot checks above still stop us.
		_walk_to_attack_position(delta)
		return
	var remaining := maxf(0.0, distance - (reach-margin))
	if not firing_clear and distance <= reach:
		if state==State.CHASE:
			_walk_to_attack_position(delta)
			return
		var gap: float = $CollisionShape3D.shape.radius + player.get_node("CollisionShape3D").shape.radius + 0.15
		remaining = maxf(0.0,Walker.horizontal(global_position,player.global_position)-gap)
	var step := minf(settings.chase_speed * delta,remaining)
	_walk_towards(global_position + _horizontal_direction(player.global_position)*step, delta)

func _can_pursue() -> bool:
	return settings.pursuit_enabled and active_attack.weapon != null and active_attack.kind == AttackData.Kind.DASH_MELEE

func preferred_distance() -> float:
	var radius: float = $CollisionShape3D.shape.radius + player.get_node("CollisionShape3D").shape.radius + 0.15
	return maxf(radius, minf(maxf(settings.preferred_attack_distance, active_attack.stop_distance), engagement_range()))

func _stop_combat_move() -> void:
	combat_move_mode = ""
	_combat_move_elapsed = 0.0
	_combat_move_blocked = false

func _work_post_attack_step(delta: float) -> void:
	if debug_unlimited_pursuit and player_alive() and not has_sight():
		_walk_towards(player.global_position,delta)
		return
	if not settings.combat_movement_enabled:
		_pursuit_step(delta)
		return
	velocity = Vector3.ZERO
	if not player_alive() or (not has_sight() and not debug_unlimited_pursuit) or locomotion_held():
		_stop_combat_move()
		_stop_pursuit()
		return
	var offset := player.global_position - global_position
	var distance := Vector2(offset.x, offset.z).length()
	if not inside_home(player.global_position) or not inside_home(global_position):
		_stop_combat_move()
		return
	# Outside the local fighting band, reuse the existing safe pursuit rather than orbit away.
	if distance > engagement_range() + 0.15 or _pursuit_moving:
		_stop_combat_move()
		_pursuit_step(delta)
		return
	_stop_pursuit()
	_combat_move_elapsed += delta
	if combat_move_mode.is_empty() or _combat_move_elapsed >= _combat_move_duration:
		_choose_combat_move()
	if combat_move_mode == "wait" or _combat_move_blocked: return
	var speed := clampf(settings.pursuit_speed, 0.1, 10.0)
	var remaining := Walker.horizontal(global_position,_combat_move_goal)
	if remaining <= 0.001: return # Keep the selected direction until its interval expires.
	var next := global_position + _horizontal_direction(_combat_move_goal) * minf(speed*delta,remaining)
	if next.distance_to(player.global_position) < maxf(active_attack.stop_distance, 0.95) or not walker.can_reach(next):
		_combat_move_blocked = true
		return
	var before := global_position
	_walk_towards(next, delta, speed)
	if global_position.distance_to(before) < minf(speed * delta, remaining) * 0.5:
		_combat_move_blocked = true

func _choose_combat_move() -> void:
	# Weighted, interleaved cycle: reproducible and stable without per-tick random turns.
	var modes: Array[String] = []
	var weights := [clampi(settings.combat_strafe_weight,0,8), clampi(settings.combat_strafe_weight,0,8), clampi(settings.combat_approach_weight,0,8), clampi(settings.combat_retreat_weight,0,8), clampi(settings.combat_wait_weight,0,8)]
	var names := ["left", "right", "approach", "retreat", "wait"]
	for pass_index in range(8):
		for index in range(names.size()):
			if pass_index < weights[index]: modes.append(names[index])
	if modes.is_empty(): modes.append("wait")
	combat_move_mode = modes[_combat_move_index % modes.size()]
	_combat_move_index += 1
	_combat_move_elapsed = 0.0
	_combat_move_duration = clampf(settings.combat_wait_seconds if combat_move_mode == "wait" else settings.combat_direction_interval, 0.05 if combat_move_mode == "wait" else 0.2, 3.0)
	_combat_move_blocked = false
	var toward := _horizontal_direction(player.global_position)
	var distance := global_position.distance_to(player.global_position)
	var step := clampf(settings.pursuit_step_distance, 0.1, 3.0)
	var direction := Vector3.ZERO
	match combat_move_mode:
		"left": direction = toward.cross(Vector3.UP)
		"right": direction = -toward.cross(Vector3.UP)
		"approach":
			direction = toward
			step = minf(step, maxf(0.0, distance - preferred_distance()))
		"retreat":
			direction = -toward
			step = minf(step, maxf(0.0, minf(engagement_range()+0.5, preferred_distance()+0.9) - distance))
	_combat_move_goal = global_position + direction * step
	if not inside_home(_combat_move_goal) or _combat_move_goal.distance_to(player.global_position) < maxf(active_attack.stop_distance,0.95) or not walker.can_reach(_combat_move_goal):
		_combat_move_blocked = true

func _work_pursuit_step(delta: float) -> void:
	velocity = Vector3.ZERO
	if not player_alive() or (not has_sight() and not debug_unlimited_pursuit) or locomotion_held():
		_stop_pursuit()
		return
	var offset := player.global_position - global_position
	var distance := Vector2(offset.x, offset.z).length()
	if not inside_home(player.global_position) or not inside_home(global_position):
		_stop_pursuit()
		return
	# Stop 5mm inside the requested range so float rounding cannot leave the
	# actor infinitesimally outside its next attack's eligibility boundary.
	var preferred := maxf(active_attack.stop_distance, preferred_distance() - 0.005)
	# A level-ground dash may reach from the preferred distance; a riser may not.
	# Keep walking until an attack is actually possible, rather than parking short.
	if active_attack.weapon != null and not _attack_position_available() and attack_start_reason!="PLANNING_PENDING": preferred = maxf(active_attack.stop_distance,0.95)
	if distance <= preferred:
		_stop_pursuit()
		return
	# A small entry band prevents rapid stop/start at the preferred distance.
	if not _pursuit_moving and distance <= preferred + 0.1 and not (state == State.CHASE and distance > engagement_range()): return
	_pursuit_moving = true
	var direction := _horizontal_direction(player.global_position)
	var speed := clampf(settings.pursuit_speed, 0.1, 10.0)
	var to_step := _horizontal_direction(_pursuit_destination)
	if not _pursuit_step_active or Walker.horizontal(global_position,_pursuit_destination) <= 0.001 or direction.dot(to_step) < 0.5:
		# A step is a retargeting guide, never a cap below one physics tick's travel.
		var length := minf(maxf(clampf(settings.pursuit_step_distance, 0.1, 3.0), speed * delta), distance - preferred)
		_pursuit_destination = global_position + direction * length
		if not inside_home(_pursuit_destination) or not walker.can_reach(_pursuit_destination,false):
			_stop_pursuit()
			return
		_pursuit_step_active = true
	to_step = _horizontal_direction(_pursuit_destination)
	# Clamp the final increment if the player comes toward an already chosen step.
	var step := minf(speed * delta, minf(distance - preferred, Walker.horizontal(global_position,_pursuit_destination)))
	_walk_towards(global_position + to_step * step, delta, speed)

func _stop_pursuit() -> void:
	_pursuit_moving = false
	_pursuit_step_active = false

func _start_windup(in_place: bool = false) -> void:
	if walker.busy(): return # Ordinary jumps/steps finish before combat begins.
	if not in_place: last_result = ""
	active_attack = settings.attack.snapshot()
	attack_anchor = global_position
	aim_locked = false
	aim_lock_elapsed = -1.0
	_locked_floor = Vector3.INF
	_locked_plan = {}
	_aim_job = {}
	_aim_plan_ready = false
	_aim_plan_frame = -1
	_forced_in_place = in_place
	_in_place = in_place or locomotion_held()
	dash_destination = attack_anchor
	_commit_minimum = clampf(settings.aim_commit_minimum_seconds, 0.1, 1.5)
	_return_after_recovery = false
	if active_attack.weapon != null and performance_diagnostics != null and not performance_diagnostics.attack_planning_enabled:
		attack_start_reason = "DIAGNOSTIC_ATTACK_DISABLED"
		_set_state(State.RECOVERY)
		return
	# Eligibility is cached, so check live recognition again without repeating a
	# full landing search. The actual fixed-target proof is made only at aim lock.
	if not player_alive() or not has_sight():
		attack_start_reason = "TARGET_NOT_VISIBLE"
		last_result = "Unsafe warning start: "+attack_start_reason
		_set_state(State.RECOVERY)
		return
	if active_attack.kind == AttackData.Kind.PROJECTILE and not _projectile_path_clear(player.global_position):
		attack_start_reason = "PROJECTILE_PATH_BLOCKED"
		return # Keep pursuing; a cached firing hint cannot authorize this warning.
	aimed_position = player.global_position
	facing = _horizontal_direction(aimed_position)
	_set_state(State.WINDUP)
	if active_attack.aim_lock_ratio <= 0.0: _lock_aim()

func _lock_aim() -> void:
	if aim_locked or state != State.WINDUP or not player_alive(): return
	# This is the only target capture in this attack. Planning never re-samples it.
	aimed_position = player.global_position
	facing = _horizontal_direction(aimed_position)
	aim_locked = true
	aim_lock_elapsed = elapsed
	attack_anchor = global_position # WINDUP is stationary; capture the actual launch origin too.
	dash_destination = attack_anchor
	if active_attack.weapon != null and active_attack.weapon.elevation_travel != null:
		_locked_floor = walker.target_floor(aimed_position,active_attack.target_ground_probe_depth)
		_aim_job = Elevation.new_attack_job()
		_aim_job["started"]=Time.get_ticks_usec()
	aim_committed.emit()

func _in_place_reach(at: Vector3, from: Vector3=Vector3.INF) -> bool:
	if active_attack.weapon==null: return false
	var start:=from if from.is_finite() else global_position
	return Sweep.contains(start,at-start,at,active_attack.weapon)

func _advance_locked_plan() -> void:
	if _aim_plan_ready: return
	if active_attack.weapon != null and performance_diagnostics != null and not performance_diagnostics.attack_planning_enabled:
		_begin_attack_return("DIAGNOSTIC_ATTACK_DISABLED")
		return
	if _in_place_reach(aimed_position,attack_anchor):
		_locked_plan={"in_place":true,"destination":attack_anchor,"out":{},"back":{}}
		_apply_locked_plan(_locked_plan)
		_aim_plan_ready=true
		return
	if active_attack.weapon == null or active_attack.weapon.elevation_travel == null:
		_aim_plan_ready = _plan_attack()
		if not _aim_plan_ready: _begin_attack_return("Unsafe locked strike: "+attack_start_reason)
		return
	if not _locked_floor.is_finite():
		_begin_attack_return("Unsafe locked strike: TARGET_FLOOR_MISSING")
		return
	if _aim_plan_frame == Engine.get_process_frames() or not PlanningBudget.take(): return
	_aim_plan_frame = Engine.get_process_frames()
	var diagnostic: Dictionary = {"enabled":true,"reason":_aim_job.reason}
	PlanningBudget.begin()
	Elevation.attack_step(self,_locked_floor,active_attack.weapon,settings.path,active_attack.stop_distance,active_attack.weapon.motion,attack_anchor,_aim_job,diagnostic)
	PlanningBudget.end()
	if not _aim_job.done: return
	_locked_plan = _aim_job.result
	attack_start_reason = "OK" if not _locked_plan.is_empty() else _aim_job.reason
	if _locked_plan.is_empty() or not inside_home(_locked_plan.destination):
		if not _locked_plan.is_empty(): attack_start_reason = "HOME_BOUNDARY"
		_begin_attack_return("Unsafe locked strike: "+attack_start_reason)
		return
	_apply_locked_plan(_locked_plan)
	_aim_plan_ready = true
	if settings.attack_range_indicator_enabled: _refresh_visuals()

func _apply_locked_plan(plan: Dictionary) -> void:
	_in_place = _forced_in_place or locomotion_held() or plan.in_place
	dash_destination = attack_anchor if _in_place else plan.destination
	var motion: Resource = active_attack.weapon.motion
	active_attack.dash_seconds = clampf(attack_anchor.distance_to(dash_destination)/motion.approach_speed,motion.minimum_travel_time,motion.maximum_travel_time)
	if not _in_place and not plan.out.is_empty() and plan.out.air: active_attack.dash_seconds = plan.out.duration

func _plan_attack() -> bool:
	if active_attack.weapon!=null and performance_diagnostics!=null and not performance_diagnostics.attack_planning_enabled:
		attack_start_reason="DIAGNOSTIC_ATTACK_DISABLED"
		return false
	# Synchronous compatibility API; the production elevation warning uses the
	# budgeted job above. Never capture a new target from this planning function.
	if active_attack.kind == AttackData.Kind.PROJECTILE:
		var clear := _projectile_release_clear()
		attack_start_reason = "OK" if clear else "PROJECTILE_PATH_BLOCKED"
		return clear
	if _in_place_reach(aimed_position,attack_anchor):
		_apply_locked_plan({"in_place":true,"destination":attack_anchor,"out":{},"back":{}})
		attack_start_reason="READY_IN_PLACE"
		return true
	_in_place = _forced_in_place or locomotion_held()
	var route_position := aimed_position
	if active_attack.weapon!=null and active_attack.weapon.elevation_travel!=null:
		var floor_at: Vector3=walker.target_floor(aimed_position,active_attack.target_ground_probe_depth)
		if not floor_at.is_finite():
			attack_start_reason="TARGET_FLOOR_MISSING"
			return false
		var plan:=_terrain_plan(floor_at)
		if plan.is_empty(): return false
		if not inside_home(plan.destination):
			attack_start_reason="HOME_BOUNDARY"
			return false
		_apply_locked_plan(plan)
		return true
	if active_attack.weapon != null:
		route_position = walker.target_floor(aimed_position,active_attack.target_ground_probe_depth)
		if not route_position.is_finite(): return false
		var nearby := Sweep.contains(global_position,facing,route_position,active_attack.weapon) and StrikeGeometry.clear(self,aimed_position)
		if not nearby and not Path.strike_clear(self,route_position,settings.path): return false
		_in_place = _in_place or nearby
	var offset := route_position - attack_anchor
	offset.y = 0.0
	# Both original capsules plus 0.15m gap, never a reduced collision shape.
	var radius: float = $CollisionShape3D.shape.radius + player.get_node("CollisionShape3D").shape.radius + 0.15
	var travel := clampf(offset.length() - maxf(active_attack.stop_distance, radius), 0.0, maxf(0.0, active_attack.dash_max_distance))
	dash_destination = attack_anchor + facing * travel if active_attack.kind == AttackData.Kind.DASH_MELEE and not _in_place else attack_anchor
	if active_attack.weapon != null:
		var motion: Resource = active_attack.weapon.motion
		active_attack.dash_seconds = clampf(attack_anchor.distance_to(dash_destination) / motion.approach_speed, motion.minimum_travel_time, motion.maximum_travel_time)
	return true

func _windup_step(_delta: float) -> void:
	velocity = Vector3.ZERO
	if not player_alive():
		_begin_attack_return("Target unavailable")
		return
	if not aim_locked:
		aimed_position = player.global_position
		facing = _horizontal_direction(aimed_position)
		if elapsed + 0.000001 < active_attack.windup_seconds * active_attack.aim_lock_ratio: return
		_lock_aim()
	_advance_locked_plan()
	if state != State.WINDUP: return
	if not _aim_plan_ready:
		if elapsed > active_attack.windup_seconds + 2.0: _begin_attack_return("Locked plan budget timeout")
		return
	var travel := active_attack.dash_seconds if global_position.distance_to(dash_destination) > 0.001 else 0.0
	var arrival_wait: float = active_attack.weapon.motion.approach_attack_delay if active_attack.weapon != null else 0.0
	var minimum_release := aim_lock_elapsed + _commit_minimum - travel - arrival_wait - active_attack.hit_delay_seconds
	var scheduled_release := active_attack.windup_seconds
	if active_attack.weapon != null:
		# Keep M09's post-warning melee cadence. Earlier aim capture changes what
		# the attack can follow, not how soon the existing sword can deal damage.
		scheduled_release += maxf(0.0,_commit_minimum-travel-arrival_wait-active_attack.hit_delay_seconds)
	if elapsed + 0.000001 < maxf(scheduled_release,minimum_release): return
	if active_attack.kind == AttackData.Kind.DASH_MELEE: _begin_dash()
	else: _begin_attack()

func _projectile_release_clear() -> bool:
	# Validate the fixed target, never the player's post-lock position. A wall at
	# the muzzle must reject spawning, not merely consume the bolt a tick later.
	return _projectile_path_clear(aimed_position)

func _projectile_path_clear(at: Vector3, from: Vector3=Vector3.INF) -> bool:
	var muzzle: Vector3=(from if from.is_finite() else global_position)+Vector3.UP*0.9
	var goal := at + Vector3.UP * 0.9
	var record:=not from.is_finite()
	var space:=get_world_3d().direct_space_state
	var line:=space.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle,goal,1))
	if not line.is_empty():
		if record: attack_blocker=str(line.collider.get_path())
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = active_attack.projectile_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,muzzle)
	query.collision_mask = 1
	var overlap:=space.intersect_shape(query,1)
	if not overlap.is_empty():
		if record: attack_blocker=str(overlap[0].collider.get_path())
		return false
	query.motion=goal-muzzle
	var fraction: float=space.cast_motion(query)[0]
	if fraction<1.0:
		if record:
			attack_blocker="PROJECTILE_RADIUS @"+str(muzzle+query.motion*fraction)
			query.transform.origin+=query.motion*minf(1.0,fraction+0.002)
			query.motion=Vector3.ZERO
			var contact:=space.intersect_shape(query,1)
			if not contact.is_empty(): attack_blocker=str(contact[0].collider.get_path())
		return false
	if record: attack_blocker=""
	return true

func _begin_dash() -> void:
	if active_attack.weapon != null and global_position.distance_to(dash_destination) <= 0.001:
		_begin_attack()
		return
	if active_attack.weapon!=null and active_attack.weapon.elevation_travel!=null:
		var plan:=Elevation.plan(self,global_position,dash_destination,settings.path,active_attack.weapon.elevation_travel,active_attack.weapon.motion)
		var back:=Elevation.plan(self,dash_destination,attack_anchor,settings.path,active_attack.weapon.elevation_travel,active_attack.weapon.motion,true)
		if plan.is_empty() or back.is_empty():
			_begin_attack_return("Locked route changed: cancelled")
			return
		if not plan.is_empty() and plan.air:
			_flight.begin(plan)
			_travel_start=global_position
			_set_state(State.DASH_APPROACH)
			return
	if not Path.clear(self, dash_destination, settings.path, global_position):
		_begin_attack_return("Unsafe approach: cancelled")
		return
	_travel_start = global_position
	_set_state(State.DASH_APPROACH)

func _begin_attack() -> void:
	_set_state(State.ATTACK)
	attack_started.emit()
	# Keep the original ranged release timing (no extra physical tick).
	if active_attack.hit_delay_seconds <= 0.0: _execute_attack()

func _begin_attack_return(reason: String) -> void:
	if not reason.is_empty() and state in [State.WINDUP,State.DASH_APPROACH,State.ATTACK]: attack_abort_reason=reason
	if _flight.active:
		_air_return_reason=reason if not reason.is_empty() else "Return after landing"
		return
	if not reason.is_empty(): last_result = reason
	if active_attack.kind != AttackData.Kind.DASH_MELEE:
		_set_state(State.RETURN if _return_after_recovery else State.RECOVERY)
		return
	_travel_start = global_position
	if active_attack.weapon != null:
		if global_position.distance_to(attack_anchor) <= 0.001:
			_set_state(State.RECOVERY)
			return
		var motion: Resource = active_attack.weapon.motion
		var plan:=Elevation.plan(self,global_position,attack_anchor,settings.path,active_attack.weapon.elevation_travel,motion,true)
		if not plan.is_empty() and plan.air:
			_flight.begin(plan)
			active_attack.return_seconds=plan.duration
			_set_state(State.DASH_RETURN)
			return
		active_attack.return_seconds = clampf(global_position.distance_to(attack_anchor) / motion.return_speed, motion.return_minimum_travel_time, motion.return_maximum_travel_time)
	_set_state(State.DASH_RETURN)

func _dash_step(delta: float, returning: bool) -> void:
	if _jump_arrived and not returning:
		_travel_elapsed+=delta
		if _travel_elapsed>=active_attack.dash_seconds+active_attack.weapon.motion.approach_attack_delay: _begin_attack()
		return
	if _flight.active:
		var outcome:=_flight.step(self,delta)
		if outcome==0: return
		if returning: _set_state(State.RECOVERY)
		elif outcome<0 or not _air_return_reason.is_empty():
			_air_return_reason=""
			_begin_attack_return("Jump interrupted")
		else:
			_travel_elapsed=active_attack.dash_seconds
			_jump_arrived=true
			if active_attack.weapon.motion.approach_attack_delay<=0.0: _begin_attack()
		return
	var destination := attack_anchor if returning else dash_destination
	# Zero-distance dash is a timed pose; it does not need a movement lease.
	if locomotion_held() and _travel_start.distance_to(destination) > 0.001:
		velocity = Vector3.ZERO
		_held_elapsed += delta
		if _held_elapsed >= maxf(0.05, active_attack.movement_hold_timeout):
			if returning:
				last_result = "Return held: stopped safely"
				_set_state(State.RECOVERY)
			else:
				last_result = "Approach held: new windup at actual position"
				_start_windup(true)
		return
	_held_elapsed = 0.0
	_travel_elapsed += delta
	var duration := maxf(0.01, active_attack.return_seconds if returning else active_attack.dash_seconds)
	var fraction := clampf(_travel_elapsed / duration, 0.0, 1.0)
	var next := _travel_start.lerp(destination, smoothstep(0.0, 1.0, fraction))
	if not Path.clear(self, next, settings.path, global_position):
		if returning:
			last_result = "Return blocked: stopped safely"
			_set_state(State.RECOVERY)
		else: _begin_attack_return("Approach blocked: cancelled")
		return
	# Actual body collision includes the player. Never push or disable collision.
	var collision := move_and_collide(next - global_position)
	velocity = Vector3.ZERO
	if collision != null:
		if returning:
			last_result = "Return collision: stopped safely"
			_set_state(State.RECOVERY)
		else: _begin_attack_return("Approach collision: cancelled")
	elif fraction >= 1.0:
		if returning: _set_state(State.RECOVERY)
		else:
			var wait: float = active_attack.weapon.motion.approach_attack_delay if active_attack.weapon != null else 0.0
			if _travel_elapsed >= duration + wait: _begin_attack()

func melee_hits() -> bool:
	if not player_alive(): return false
	if active_attack.weapon != null: return _weapon_strike_clear(player.global_position)
	if not has_sight(): return false
	var offset := player.global_position - global_position
	if absf(offset.y) > active_attack.hit_height_tolerance: return false
	offset.y = 0.0
	var hit_direction := facing.rotated(Vector3.UP, deg_to_rad(active_attack.hit_yaw_degrees))
	return offset.length() <= active_attack.hit_radius and (offset.is_zero_approx() or hit_direction.dot(offset.normalized()) >= cos(deg_to_rad(active_attack.hit_half_angle_degrees)))

func _execute_attack() -> void:
	if active_attack.weapon!=null and performance_diagnostics!=null and not performance_diagnostics.attack_planning_enabled:
		attack_executed=true
		return
	if attack_executed or state != State.ATTACK or health.current_hp <= 0.0 or not player_alive(): return
	attack_executed = true
	attack_count += 1
	cooldown = active_attack.minimum_attack_interval
	if active_attack.kind != AttackData.Kind.PROJECTILE:
		var connects:=melee_hits()
		attack_hit_reason="OK" if connects else "BLADE_BLOCKED_OR_OUT_OF_REACH"
		last_hit_blocker=attack_blocker
		if not connects and active_attack.weapon!=null:
			var delta_y:=player.global_position.y-global_position.y
			var weapon: WeaponData=active_attack.weapon
			if delta_y>weapon.hit_height_up or -delta_y>weapon.hit_height_down: attack_hit_reason="HEIGHT_OUT_OF_RANGE"
			elif not Sweep.contains(global_position,facing,player.global_position,weapon): attack_hit_reason="OUT_OF_RANGE_OR_DIRECTION"
			else: attack_hit_reason="BLADE_BLOCKED"
		if connects: player.get_node("HealthComponent").damage(active_attack.damage, self, active_attack.damage_kind)
	elif aim_locked and _projectile_release_clear():
		for index in range(shots.size() - 1, -1, -1):
			if not is_instance_valid(shots[index]) or shots[index].is_queued_for_deletion(): shots.remove_at(index)
		if shots.size() >= active_attack.maximum_projectiles: return
		var shot := Projectile.new()
		shot.settings = active_attack
		shot.player = player
		shot.source = self
		add_child(shot)
		shot.global_position = global_position + Vector3.UP * 0.9
		shot.direction = (aimed_position + Vector3.UP * 0.9 - shot.global_position).normalized()
		shots.append(shot)
		attack_hit_reason="PROJECTILE_RELEASED"
		last_hit_blocker=""
		_play_projectile_launch_sound()
		projectile_released.emit(shot)
		_refresh_visuals()
	else:
		attack_hit_reason="PROJECTILE_BLOCKED"
		last_hit_blocker=attack_blocker

func _play_projectile_launch_sound() -> void:
	var visual: Resource = active_attack.magic_visual
	if visual == null or visual.launch_sound == null: return
	# Independent of the bolt and caster: point-blank hits/death must not cut it.
	var audio := AudioStreamPlayer.new()
	audio.name = "ProjectileLaunchAudio"
	audio.stream = visual.launch_sound
	audio.volume_db = clampf(visual.launch_volume_db,-60.0,0.0)
	audio.pitch_scale = clampf(visual.launch_pitch_scale,0.5,2.0)
	audio.finished.connect(audio.queue_free)
	get_parent().add_child(audio)
	audio.add_to_group("projectile_launch_audio")
	audio.play()

func _set_state(next: State) -> void:
	_jump_arrived=false
	var previous := state
	state = next
	if next not in [State.WINDUP,State.DASH_APPROACH,State.ATTACK,State.DASH_RETURN]:
		aim_locked = false
		_aim_job = {}
		_locked_plan = {}
		_aim_plan_ready = false
	if next not in [State.CHASE,State.RECOVERY]:
		_pursuit_route.reset()
		_search_behavior.reset()
	_availability_until=0
	_availability_frame=-1
	if next!=State.CHASE: _eligibility_job={}
	if next == State.RETURN: walker.begin_return()
	elif next == State.IDLE: walker.reset_home()
	_ranged_pursuit_active = false
	attack_executed = false
	elapsed = 0.0
	_travel_elapsed = 0.0
	_held_elapsed = 0.0
	velocity = Vector3.ZERO
	_stop_pursuit()
	_stop_combat_move()
	_refresh_visuals()
	if next == State.WINDUP and previous != State.WINDUP: attack_warning_started.emit()

func _die(source: Node) -> void:
	if state == State.DEAD: return
	set_physics_process(false)
	_set_state(State.DEAD)
	targetable.set_available(false)
	clear_shots()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.set_deferred("disabled",true)
	$Body.position.y = 0.26
	$DefeatPresentation.start(source)

func clear_shots() -> void:
	for shot in shots:
		if is_instance_valid(shot):
			shot.consumed = true
			shot.queue_free()
	shots.clear()

func _update_telegraph_position() -> void:
	if state in [State.WINDUP, State.DASH_APPROACH] and active_attack.kind == AttackData.Kind.DASH_MELEE:
		telegraph.global_position = dash_destination + Vector3.UP * 0.035
	else: telegraph.position = Vector3.UP * 0.035

func _refresh_visuals() -> void:
	if not is_instance_valid(telegraph): return
	debug_label.visible = show_debug_state and (performance_diagnostics==null or performance_diagnostics.details_enabled)
	debug_label.text = ("RANGED  " if active_attack.kind == AttackData.Kind.PROJECTILE else "MELEE  ") + State.keys()[state]
	if show_attack_diagnostics:
		_update_attack_debug()
	if not last_result.is_empty(): debug_label.text += "\n" + last_result
	telegraph.visible = settings.attack_range_indicator_enabled and state in [State.WINDUP, State.DASH_APPROACH, State.ATTACK]
	var mesh := ImmediateMesh.new()
	if telegraph.visible:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var ranged := active_attack.kind == AttackData.Kind.PROJECTILE
		var half_angle := deg_to_rad(active_attack.hit_half_angle_degrees) if not ranged else (PI if state == State.WINDUP else 0.12)
		var radius: float = active_attack.hit_radius if not ranged else (0.55 if state == State.WINDUP else 1.4)
		var hit_direction := facing if ranged else facing.rotated(Vector3.UP, deg_to_rad(active_attack.hit_yaw_degrees))
		for i in range(24):
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(hit_direction.rotated(Vector3.UP, lerpf(-half_angle, half_angle, float(i) / 24)) * radius)
			mesh.surface_add_vertex(hit_direction.rotated(Vector3.UP, lerpf(-half_angle, half_angle, float(i + 1) / 24)) * radius)
		mesh.surface_end()
	telegraph.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1, 0.65, 0.1, 0.35) if state != State.ATTACK else Color(1, 0.2, 0.1, 0.8)
	telegraph.material_override = material
	_update_telegraph_position()
	# Fixed route line is independent of the moving body; it is never a hit shape.
	dash_guide.visible = settings.attack_range_indicator_enabled and state in [State.WINDUP, State.DASH_APPROACH] and active_attack.kind == AttackData.Kind.DASH_MELEE
	var guide := ImmediateMesh.new()
	if dash_guide.visible:
		guide.surface_begin(Mesh.PRIMITIVE_LINES)
		guide.surface_add_vertex(attack_anchor + Vector3.UP * 0.04)
		guide.surface_add_vertex(dash_destination + Vector3.UP * 0.04)
		guide.surface_end()
	dash_guide.mesh = guide
	dash_guide.material_override = material
	dash_guide.top_level = true
	dash_guide.global_transform = Transform3D.IDENTITY
	$Body.scale = Vector3(1.12, 0.8, 1.12) if state == State.WINDUP else (Vector3(0.9, 1.12, 0.9) if state == State.ATTACK else Vector3.ONE)
	if state in [State.DASH_APPROACH, State.DASH_RETURN]: $Body.scale = Vector3(0.85, 0.9, 1.15)
	if state == State.DEAD: $Body.scale.y = 0.35

func has_sight() -> bool:
	var started:=Work.start(self)
	var result: bool=_work_has_sight()
	Work.finish(self,"enemy.sight",started)
	return result

func _terrain_plan(at: Vector3) -> Dictionary:
	var started:=Work.start(self)
	var result: Dictionary=_work_terrain_plan(at)
	Work.finish(self,"enemy.attack_plan",started)
	return result

func _update_attack_debug() -> void:
	var started:=Work.start(self)
	_work_update_attack_debug()
	Work.finish(self,"enemy.debug",started)

func _physics_process(delta: float) -> void:
	var started:=Work.start(self)
	_planning_async=true
	_work_physics_process(delta)
	_planning_async=false
	if show_attack_diagnostics: _update_attack_debug()
	if performance_diagnostics!=null and performance_diagnostics.capture_timings:
		performance_diagnostics.context={"enemy_position":global_position,"player_position":player.global_position if player_alive() else Vector3.INF,"state":State.keys()[state],"move":walker.blocked_reason,"route":_pursuit_route.reason,"start":attack_start_reason,"abort":attack_abort_reason,"unlimited":debug_unlimited_pursuit,"aim_locked":aim_locked,"aim_lock_elapsed":aim_lock_elapsed,"aim_target":aimed_position,"aim_plan_ready":_aim_plan_ready}
	Work.finish(self,"enemy.physics",started)

func _post_attack_step(delta: float) -> void:
	var started:=Work.start(self)
	_work_post_attack_step(delta)
	Work.finish(self,"enemy.recovery_motion",started)

func _pursuit_step(delta: float) -> void:
	var started:=Work.start(self)
	_work_pursuit_step(delta)
	Work.finish(self,"enemy.pursuit",started)
