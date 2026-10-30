extends CharacterBody3D
const Walker = preload("res://scripts/enemies/enemy_walk.gd")
const StrikeGeometry = preload("res://scripts/enemies/enemy_melee_geometry.gd")
const Settings = preload("res://scripts/enemies/enemy_settings.gd")
const AttackData = preload("res://scripts/enemies/enemy_attack_data.gd")
const CastingVisual = preload("res://scripts/effects/mage_cast_visual.gd")
const Projectile = preload("res://scripts/enemies/practice_projectile.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const Sweep = preload("res://scripts/combat/melee_sweep.gd")
const Elevation=preload("res://scripts/combat/elevation_path.gd")
const Flight=preload("res://scripts/combat/combat_flight.gd")
var _flight:=Flight.new()
var _air_return_reason:=""
var _jump_arrived:=false
# RETURN = home/leash return; DASH_RETURN = attack_anchor.
enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVERY, RETURN, DEAD, DASH_APPROACH, DASH_RETURN }
signal attack_started
signal attack_warning_started
signal projectile_released(shot: CharacterBody3D)
@export var settings: Settings = preload("res://resources/enemies/melee_practice.tres")
@export var player: CharacterBody3D
@export var show_debug_state := true
@export var show_attack_diagnostics := false
var attack_start_reason:=""
var attack_abort_reason:=""
var attack_hit_reason:=""

func _update_attack_debug() -> void:
	debug_label.visible=true
	debug_label.text=State.keys()[state]+"\nSTART: "+attack_start_reason+"\nABORT: "+attack_abort_reason+"\nHIT: "+attack_hit_reason

func _terrain_plan(at: Vector3) -> Dictionary:
	var diagnostic: Dictionary={"enabled":true} if show_attack_diagnostics else {}
	var result:=Elevation.attack(self,at,active_attack.weapon,settings.path,active_attack.stop_distance,active_attack.weapon.motion,Vector3.INF,diagnostic)
	if show_attack_diagnostics: attack_start_reason="OK" if not result.is_empty() else diagnostic.get("reason","NO_SAFE_LANDING")
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
var _late_aim := false
var _forced_in_place := false
var _commit_minimum := 0.0
var _commit_elapsed := 0.0
var _commit_wait := 0.0
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

func has_sight() -> bool:
	if player_alive() and active_attack!=null and active_attack.weapon!=null and active_attack.weapon.hit_height_up>=0.0:
		return Path.sight(self,player.global_position) or StrikeGeometry.clear(self,player.global_position) or Elevation.Blade._line(self,global_position+Vector3.UP*1.6,player.global_position+Vector3.UP*1.6)
	return player_alive() and Path.sight(self, player.global_position)

func engagement_range() -> float:
	return settings.attack.weapon.attack_range if settings.attack.weapon != null else settings.attack_start_distance

func current_weapon_visual() -> Resource:
	if active_attack != null and active_attack.weapon != null: return active_attack.weapon.attack_visual
	return settings.visual.weapon_visual if settings.visual != null else null

func _weapon_strike_clear(at: Vector3) -> bool:
	if not Sweep.contains(global_position, facing, at, active_attack.weapon): return false
	return StrikeGeometry.clear(self,at)

func _physics_process(delta: float) -> void:
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
	var distance := global_position.distance_to(player.global_position) if player_alive() else INF
	if player_alive() and active_attack.weapon!=null: distance=Walker.horizontal(global_position,player.global_position)
	var sight := has_sight()
	if show_attack_diagnostics:
		if walker.busy(): attack_start_reason="ACTOR_AIRBORNE"
		elif not sight: attack_start_reason="TARGET_NOT_VISIBLE"
		elif distance>engagement_range(): attack_start_reason="OUT_OF_RANGE"
		_update_attack_debug()
	sight_lost = 0.0 if sight else sight_lost + delta
	if sight:
		last_seen_position = player.global_position
		_last_seen_valid = true
	var beyond_leash := not inside_home(player.global_position) if player_alive() else true
	beyond_leash = beyond_leash or not inside_home(global_position)
	var committed := _projectile_cast_committed()
	if committed and beyond_leash: _return_after_recovery = true
	var leashed := (beyond_leash and not committed) or sight_lost >= settings.sight_loss_seconds
	# Complete an attack return before going home; never replace its anchor.
	if leashed and state in [State.CHASE, State.WINDUP]: _set_state(State.RETURN)
	elif leashed and state in [State.DASH_APPROACH, State.ATTACK, State.DASH_RETURN]:
		_return_after_recovery = true
		if state != State.DASH_RETURN: _begin_attack_return("Leash or sight lost")
	if leashed and state == State.RECOVERY and not _return_after_recovery: _set_state(State.RETURN)
	if walker.busy() and state in [State.CHASE,State.RECOVERY,State.RETURN]:
		if locomotion_held() and not walker.airborne(): velocity = Vector3.ZERO
		else:
			walker.continue_climb(delta)
			_face_walk_velocity()
		return
	match state:
		State.IDLE:
			if sight and distance <= settings.detection_radius and inside_home(player.global_position,settings.leash_reentry_margin): _set_state(State.CHASE)
		State.CHASE:
			if not sight:
				velocity = Vector3.ZERO
				if _last_seen_valid and sight_lost < settings.sight_loss_seconds: _walk_towards(last_seen_position,delta)
			elif active_attack.kind == AttackData.Kind.PROJECTILE: _ranged_chase_step(delta, distance, sight, true)
			elif sight and distance <= engagement_range() and cooldown <= 0.0 and _attack_position_available(): _start_windup()
			elif sight and (distance > engagement_range() or not _attack_position_available()):
				if _can_pursue() and attack_count > 0: _pursuit_step(delta)
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
	return Walker.horizontal(home,at) <= maxf(0.0,settings.leash_radius-margin)

func _attack_position_available() -> bool:
	if active_attack.weapon == null: return true
	if active_attack.weapon.elevation_travel!=null:
		var floor_at: Vector3=walker.target_floor(player.global_position,active_attack.target_ground_probe_depth)
		if not floor_at.is_finite(): return false
		var plan:=_terrain_plan(floor_at)
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

func _walk_towards(at: Vector3, delta: float, speed_override: float = -1.0) -> void:
	velocity = Vector3.ZERO
	if locomotion_held(): return # Chase waits but its attack state machine still runs.
	var direction := _horizontal_direction(at) # Preserve intent before a one-tick goal is consumed.
	var speed := settings.chase_speed if speed_override < 0.0 else speed_override
	walker.walk(at,delta,speed)
	_face_walk_velocity(direction)

func _face_walk_velocity(climb_direction: Vector3 = Vector3.ZERO) -> void:
	var direction := Vector3(velocity.x,0.0,velocity.z)
	if direction.length_squared()>0.0001: facing = direction.normalized()
	elif walker.busy() and absf(velocity.y)>0.01 and not climb_direction.is_zero_approx(): facing = climb_direction

func _ranged_chase_step(delta: float, distance: float, sight: bool, allow_attack: bool) -> void:
	velocity = Vector3.ZERO
	if not sight: return
	var reach := engagement_range()
	if allow_attack and distance <= reach and cooldown <= 0.0:
		_start_windup()
		return
	var margin := clampf(settings.ranged_stop_margin, 0.0, minf(1.0, reach*0.5))
	if distance > reach: _ranged_pursuit_active = true
	elif distance <= reach - margin: _ranged_pursuit_active = false
	if not _ranged_pursuit_active: return
	var step := minf(settings.chase_speed * delta, maxf(0.0, distance - (reach-margin)))
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

func _post_attack_step(delta: float) -> void:
	if not settings.combat_movement_enabled:
		_pursuit_step(delta)
		return
	velocity = Vector3.ZERO
	if not player_alive() or not has_sight() or locomotion_held():
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

func _pursuit_step(delta: float) -> void:
	velocity = Vector3.ZERO
	if not player_alive() or not has_sight() or locomotion_held():
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
	if active_attack.weapon != null and not _attack_position_available(): preferred = maxf(active_attack.stop_distance,0.95)
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
	_late_aim = settings.track_windup_target and active_attack.weapon != null and active_attack.kind == AttackData.Kind.DASH_MELEE
	aim_locked = not _late_aim
	_forced_in_place = in_place
	_commit_minimum = clampf(settings.aim_commit_minimum_seconds, 0.1, 1.5)
	_commit_elapsed = 0.0
	_commit_wait = 0.0
	_return_after_recovery = false
	if not _plan_attack():
		last_result = "Unsafe weapon strike path"
		_set_state(State.RECOVERY)
		return
	_set_state(State.WINDUP)

func _plan_attack() -> bool:
	# Preview follows the player only during WINDUP. Once committed this is never called.
	aimed_position = player.global_position
	facing = _horizontal_direction(aimed_position)
	_in_place = _forced_in_place or locomotion_held()
	var route_position := aimed_position
	if active_attack.weapon!=null and active_attack.weapon.elevation_travel!=null:
		var floor_at: Vector3=walker.target_floor(aimed_position,active_attack.target_ground_probe_depth)
		if not floor_at.is_finite(): return false
		var plan:=_terrain_plan(floor_at)
		if plan.is_empty() or not inside_home(plan.destination): return false
		_in_place=_in_place or plan.in_place
		dash_destination=attack_anchor if _in_place else plan.destination
		var motion: Resource=active_attack.weapon.motion
		active_attack.dash_seconds=clampf(attack_anchor.distance_to(dash_destination)/motion.approach_speed,motion.minimum_travel_time,motion.maximum_travel_time)
		if not plan.out.is_empty() and plan.out.air: active_attack.dash_seconds=plan.out.duration
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

func _windup_step(delta: float) -> void:
	if _late_aim:
		if not aim_locked:
			if not _plan_attack():
				if show_attack_diagnostics: attack_abort_reason=attack_start_reason
				_begin_attack_return("Unsafe tracked strike: cancelled")
				return
			if settings.attack_range_indicator_enabled: _refresh_visuals() # Optional debug route follows the preview too.
			if elapsed < active_attack.windup_seconds: return
			aim_locked = true
			var travel := active_attack.dash_seconds if global_position.distance_to(dash_destination) > 0.001 else 0.0
			var arrival_wait: float = active_attack.weapon.motion.approach_attack_delay
			_commit_wait = maxf(0.0, _commit_minimum - travel - arrival_wait - active_attack.hit_delay_seconds)
			_commit_elapsed = 0.0
		else: _commit_elapsed += delta
		if _commit_elapsed + 0.000001 < _commit_wait: return
	elif elapsed < active_attack.windup_seconds: return
	if active_attack.kind == AttackData.Kind.DASH_MELEE: _begin_dash()
	else: _begin_attack()

func _begin_dash() -> void:
	if active_attack.weapon != null and global_position.distance_to(dash_destination) <= 0.001:
		_begin_attack()
		return
	if active_attack.weapon!=null and active_attack.weapon.elevation_travel!=null:
		var plan:=Elevation.plan(self,global_position,dash_destination,settings.path,active_attack.weapon.elevation_travel,active_attack.weapon.motion)
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
	if show_attack_diagnostics and not reason.is_empty() and state in [State.WINDUP,State.DASH_APPROACH,State.ATTACK]: attack_abort_reason=reason
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
	if not player_alive() or not has_sight(): return false
	if active_attack.weapon != null: return _weapon_strike_clear(player.global_position)
	var offset := player.global_position - global_position
	if absf(offset.y) > active_attack.hit_height_tolerance: return false
	offset.y = 0.0
	var hit_direction := facing.rotated(Vector3.UP, deg_to_rad(active_attack.hit_yaw_degrees))
	return offset.length() <= active_attack.hit_radius and (offset.is_zero_approx() or hit_direction.dot(offset.normalized()) >= cos(deg_to_rad(active_attack.hit_half_angle_degrees)))

func _execute_attack() -> void:
	if attack_executed or state != State.ATTACK or health.current_hp <= 0.0 or not player_alive(): return
	attack_executed = true
	attack_count += 1
	cooldown = active_attack.minimum_attack_interval
	if active_attack.kind != AttackData.Kind.PROJECTILE:
		var connects:=melee_hits()
		if show_attack_diagnostics:
			attack_hit_reason="OK" if connects else "BLADE_BLOCKED_OR_OUT_OF_REACH"
			if not connects and active_attack.weapon!=null:
				var delta_y:=player.global_position.y-global_position.y
				var weapon: WeaponData=active_attack.weapon
				if delta_y>weapon.hit_height_up or -delta_y>weapon.hit_height_down: attack_hit_reason="HEIGHT_OUT_OF_RANGE"
				elif not Sweep.contains(global_position,facing,player.global_position,weapon): attack_hit_reason="OUT_OF_RANGE_OR_DIRECTION"
				else: attack_hit_reason="BLADE_BLOCKED"
		if connects: player.get_node("HealthComponent").damage(active_attack.damage, self, active_attack.damage_kind)
	elif has_sight() and (_projectile_cast_committed() or global_position.distance_to(player.global_position) <= settings.attack_start_distance):
		for index in range(shots.size() - 1, -1, -1):
			if not is_instance_valid(shots[index]) or shots[index].is_queued_for_deletion(): shots.remove_at(index)
		if shots.size() >= active_attack.maximum_projectiles: return
		var shot := Projectile.new()
		shot.settings = active_attack
		shot.player = player
		shot.source = self
		add_child(shot)
		shot.global_position = global_position + Vector3.UP * 0.9
		shot.direction = (player.global_position + Vector3.UP * 0.9 - shot.global_position).normalized()
		shots.append(shot)
		_play_projectile_launch_sound()
		projectile_released.emit(shot)
		facing = _horizontal_direction(player.global_position)
		_refresh_visuals()

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
	debug_label.visible = show_debug_state
	debug_label.text = ("RANGED  " if active_attack.kind == AttackData.Kind.PROJECTILE else "MELEE  ") + State.keys()[state]
	if show_attack_diagnostics:
		debug_label.visible=true
		debug_label.text+="\nSTART: "+attack_start_reason+"\nABORT: "+attack_abort_reason+"\nHIT: "+attack_hit_reason
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
