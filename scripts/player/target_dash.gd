extends Node
const DamageTypes = preload("res://scripts/combat/damage_types.gd")
const MotionSettings = preload("res://scripts/combat/attack_motion_settings.gd")
## Single-owner state machine. Controller calls physics_step before locomotion.
const Settings = preload("res://scripts/combat/target_dash_settings.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const Target = preload("res://scripts/combat/targetable.gd")
const Sweep = preload("res://scripts/combat/melee_sweep.gd")
const BladeTerrain = preload("res://scripts/combat/melee_terrain.gd")
const Elevation=preload("res://scripts/combat/elevation_path.gd")
const Flight=preload("res://scripts/combat/combat_flight.gd")
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
const PlanningBudget=preload("res://scripts/combat/planning_budget.gd")
@export var performance_diagnostics: Work
var _flight:=Flight.new()
var _travel_unavailable:=false
var _elevation_cycle:=false
var _travel_history: Array[Vector3]=[]
var _return_goals: Array[Vector3]=[]
var _air_return_reason:=""
var _plan_cache: Dictionary={}
var _plan_frame:=-1
var _preview_only:=false
var _preview_cache: Dictionary={}
var _preview_jobs: Dictionary={}

func _work_elevation_plan(candidate: Node3D, weapon: WeaponData) -> Dictionary:
	if performance_diagnostics!=null and not performance_diagnostics.attack_planning_enabled: return {}
	if _preview_only:
		var id: int=candidate.get_instance_id()
		var origin: Vector3=_flight.data.finish if _flight.active else body.global_position
		var now:=Time.get_ticks_usec()
		var cached: Dictionary=_preview_cache.get(id,{})
		if not cached.is_empty() and cached.weapon==weapon and now<cached.until and origin.distance_to(cached.origin)<0.1 and candidate.global_position.distance_to(cached.target)<0.1:
			return cached.plan
		var hint: Dictionary={}
		if not cached.is_empty() and cached.weapon==weapon and now<cached.until+120000 and origin.distance_to(cached.origin)<0.3 and candidate.global_position.distance_to(cached.target)<0.3: hint=cached.plan
		var job: Dictionary=_preview_jobs.get(id,{})
		if job.is_empty() or job.weapon!=weapon or origin.distance_to(job.origin)>0.5 or candidate.global_position.distance_to(job.target)>0.5:
			job=Elevation.new_attack_job()
			job.merge({"weapon":weapon,"origin":origin,"target":candidate.global_position,"frame":-1})
			if not hint.is_empty() and hint.has("candidate_index"):
				job.index=hint.candidate_index
				job["preferred"]=true
		if job.frame==Engine.get_process_frames() or not PlanningBudget.take(): return hint
		job.frame=Engine.get_process_frames()
		PlanningBudget.begin()
		Elevation.attack_step(body,candidate.global_position,weapon,settings,settings.stop_distance,weapon.motion,origin,job)
		PlanningBudget.end()
		if job.has("preferred") and not job.done:
			job.erase("preferred")
			job.index=-1
		if _preview_jobs.size()>64: _preview_jobs.clear()
		_preview_jobs[id]=job
		if not job.done: return hint
		_preview_jobs.erase(id)
		var plan: Dictionary=job.result
		if _preview_cache.size()>64: _preview_cache.clear()
		_preview_cache[id]={"weapon":weapon,"origin":origin,"target":candidate.global_position,"until":Time.get_ticks_usec()+(120000 if not plan.is_empty() else 400000),"plan":plan}
		return plan
	var frame:=Engine.get_physics_frames()
	if _plan_frame!=frame:
		_plan_frame=frame
		_plan_cache.clear()
	var from: Vector3=_flight.data.finish if _flight.active else body.global_position
	var key:=str(candidate.get_instance_id())+str(from)+str(candidate.global_position)+str(weapon.get_instance_id())
	if not _plan_cache.has(key): _plan_cache[key]=Elevation.attack(body,candidate.global_position,weapon,settings,settings.stop_distance,weapon.motion,from)
	return _plan_cache[key]
const RETURN_POSITION_EPSILON := 0.001 # Metres; ignore numerical drift without snapping.
enum State { Idle, Approach, Attack, Return, Guard, Recover }
signal state_changed(next: int)
signal hit(target: Node)
signal attack_accepted(attack_id: int, combo: int)
signal attack_rejected(reason: String)
signal guard_succeeded(source: Node)
@export var settings: Settings = preload("res://resources/target_dash_settings.tres")
@export var defense: Resource = preload("res://resources/defense_settings.tres")
@export var camera_rig: Node3D
@export var show_debug_attack_range: bool = false
@export var equipped_weapon: WeaponData = preload("res://resources/weapons/one_handed_sword.tres"):
	set(value):
		if value != null and not is_busy(): equipped_weapon = value
var combo_hits := 0
var attack_id := 0
var queued := false
var queued_attack_target: Node3D
var _waiting := false
var _grace_elapsed := 0.0
var _active_weapon: WeaponData
var _active_motion: MotionSettings
var _finishing_reason := ""
var state: State = State.Idle
var return_anchor := Vector3.ZERO
var return_error := 0.0
var last_result := ""
var target: Node3D
var selected_target: Node3D
var _manual_selection := false
var _manual_facing := Vector3.ZERO
var _aim_candidate: Node3D
var _aim_elapsed := 0.0
var _target_anchor := Vector3.ZERO
var _destination := Vector3.ZERO
var _travel_start := Vector3.ZERO
var _duration := 0.3
var _elapsed := 0.0
var _hit_pending := false
var _hit_done := false
var _attack_finished := false
var _planned_hits := 0
var _sequence_slots := 0 # Includes silent slots after a target disappears.
var _target_lost := false
var _empty_slot := false
var _empty_duration := 0.0
var strike_facing := Vector3.FORWARD
var motion_owned_tick := false
var _combat_cycle := false
var _resume_return := false
var _return_input_armed := false
var _return_press_seen := 0
var _return_neutral_seen := 0
var _pending_guard := false
var _mouse_guard_held := false
var _wait_defense_release := false
var _pending_click := false
var _pending_selected_attack := false
var _click_position := Vector2.ZERO
var _ring: MeshInstance3D
var _range_guides: MeshInstance3D
@onready var body: CharacterBody3D = get_parent()
@onready var stock: AttackStockComponent = body.get_node("AttackStockComponent")
@onready var sprite: AnimatedSprite3D = body.get_node("AnimatedSprite3D")

func _ready() -> void:
	body.combat = self
	body.collision_mask |= 4
	sprite.frame_changed.connect(_on_frame)
	sprite.attack_completed.connect(_on_finished)
	body.get_node("HealthComponent").depleted.connect(func(_source: Node): cancel())
	body.get_node("HealthComponent").damage_filter = filter_damage
	_ring = MeshInstance3D.new()
	_ring.visible = false
	var mesh := TorusMesh.new()
	mesh.inner_radius = equipped_weapon.attack_range - 0.025
	mesh.outer_radius = equipped_weapon.attack_range + 0.025
	mesh.rings = 64
	mesh.ring_segments = 8
	_ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.36, 0.7, 0.8, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child.call_deferred(_ring)
	_ring.position.y = 0.04
	_range_guides = MeshInstance3D.new()
	_range_guides.name = "RangeCenterGuides"
	_range_guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var guide_material := material.duplicate() as StandardMaterial3D
	guide_material.albedo_color.a = 0.22
	_range_guides.material_override = guide_material
	_ring.add_child(_range_guides)
	_update_range_guides()

func _update_range_guides() -> void:
	# Perspective shifts the ellipse's apparent center, not its world origin.
	# Ground-plane diameters reveal that origin without moving the range boundary.
	var guides := ImmediateMesh.new()
	guides.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		guides.surface_add_vertex(-axis * equipped_weapon.attack_range)
		guides.surface_add_vertex(axis * equipped_weapon.attack_range)
	guides.surface_end()
	_range_guides.mesh = guides

func is_busy() -> bool:
	return state != State.Idle

func _input(event: InputEvent) -> void:
	# Releases must reach the input adapter even over UI that consumes the event.
	if event is InputEventMouseButton and event.is_action_released("guard"):
		_mouse_guard_held = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return
	if event.is_action_pressed("guard"):
		if event is InputEventMouseButton: _mouse_guard_held = true
		_pending_guard = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_on"):
		cycle_target()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		if is_busy():
			if event is InputEventMouseButton:
				var candidate := pick_attack_target(event.position)
				if candidate != null: request_followup(candidate, true)
				else: _reject("No valid click target")
			else:
				request_followup()
		elif not _pending_click and not _pending_selected_attack and event is InputEventMouseButton:
			_pending_click = true
			_click_position = event.position
		elif not _pending_click:
			_pending_selected_attack = true
		get_viewport().set_input_as_handled()

func _work_physics_step(delta: float) -> void:
	var was_busy := is_busy()
	motion_owned_tick = was_busy
	if body.get_node("HealthComponent").current_hp <= 0.0:
		cancel()
		body.clear_combat_input()
		stock.set_recovery_allowed(false)
		motion_owned_tick = true
		_update_markers()
		return
	if not is_busy():
		_refresh_selection(delta)
	# Consume intent even in Guard/Return: it must not be deferred until exit.
	var direction_return := _direction_return_requested()
	var interrupted := _defense_input()
	if not interrupted and direction_return:
		_begin_return("Direction input: return to start")
		interrupted = true
	if interrupted:
		_pending_click = false
		_pending_selected_attack = false
	if _pending_click:
		_pending_click = false
		var selected := pick_attack_target(_click_position)
		if selected != null:
			request_attack(selected)
	elif _pending_selected_attack and not is_busy():
		var requested:=selected_target
		if not is_instance_valid(requested):
			# Keyboard input must not depend on the advisory display job finishing.
			requested=_best_auto_target(valid_candidates(),Vector3(body.facing_world.x,0,body.facing_world.z).normalized())
		request_attack(requested)
	_pending_selected_attack = false
	if is_busy():
		if state == State.Approach or state == State.Attack:
			if _target_alive() and not _target_lost and not _framed(target):
				_begin_return("Target or player outside view")
		_elapsed += delta
		match state:
			State.Approach: _approach(delta)
			State.Attack: _attack(delta)
			State.Return: _return(delta)
			State.Guard: _guard()
			State.Recover: _recover(delta)
	motion_owned_tick = motion_owned_tick or is_busy() or interrupted
	stock.set_recovery_allowed(not was_busy and not is_busy() and body.get_node("HealthComponent").current_hp > 0.0)
	stock.advance(delta)
	_update_markers()

func _direction_return_requested() -> bool:
	var new_press: bool = body.movement_press_serial != _return_press_seen
	if body.movement_neutral_serial != _return_neutral_seen:
		_return_input_armed = true
	_return_press_seen = body.movement_press_serial
	_return_neutral_seen = body.movement_neutral_serial
	return _combat_cycle and _return_input_armed and new_press and state in [State.Approach, State.Attack, State.Recover]

func _guard_pressed() -> bool:
	if not Input.is_action_pressed("guard"): return false
	if _mouse_guard_held: return true
	var bindings := InputMap.action_get_events("guard")
	var mouse_pressed := false
	for binding in bindings:
		if binding is InputEventMouseButton and Input.is_mouse_button_pressed(binding.button_index):
			mouse_pressed = true
	if not mouse_pressed: return true # Existing keyboard/pad and synthetic action input.
	# A UI-consumed mouse press updates global Input too. Ignore that source, while
	# still allowing concurrently held keyboard/pad bindings from the same InputMap.
	for binding in bindings:
		if binding is InputEventKey:
			if binding.physical_keycode != 0 and Input.is_physical_key_pressed(binding.physical_keycode): return true
			if binding.keycode != 0 and Input.is_key_pressed(binding.keycode): return true
		elif binding is InputEventJoypadButton:
			for device in Input.get_connected_joypads():
				if (binding.device < 0 or binding.device == device) and Input.is_joy_button_pressed(device, binding.button_index): return true
	return false

func _defense_input() -> bool:
	var guard_pressed := _guard_pressed()
	var guard_request := guard_pressed or _pending_guard
	_pending_guard = false
	if _wait_defense_release:
		if not guard_pressed: _wait_defense_release = false
		return false
	if guard_request:
		if state != State.Guard:
			if not _defense_grounded(): return _reject("Guard rejected: airborne or unsafe floor")
			if _flight.active: _resume_return=true
			_interrupt_attack()
			_set_state(State.Guard)
			_show_defense_pose(&"Guard")
		return true
	return false

func _defense_grounded() -> bool:
	if _flight.active: return true # Guard may change pose, never suspend a validated flight.
	# Combat travel uses move_and_collide, whose floor flag is stale; validate
	# the actual capsule footprint as well. Airborne FREE input is rejected.
	if state == State.Idle: return body.is_on_floor() and body.velocity.y <= 0.0
	return _standing_safe()

func _standing_safe() -> bool:
	if Path.clear(body,body.global_position,settings,body.global_position): return true
	var weapon:=_active_weapon if _combat_cycle else equipped_weapon
	if weapon.hit_height_up<0.0 or not body.is_on_floor() or body.velocity.y>0.0: return false
	var ground:=BladeTerrain.ground_at(body,body.global_position,0.1)
	return ground.is_finite() and absf(ground.y-body.global_position.y)<0.05 and Path._sweep_clear(body,body.global_position,body.global_position,5)

func _interrupt_attack() -> void:
	_resume_return = _resume_return or state == State.Return
	queued = false
	queued_attack_target = null
	_waiting = false
	_hit_pending = false
	_empty_slot = false
	_finishing_reason = ""
	# A paid strike keeps its ID and hit history. Only _start_strike resets them.
	sprite._attacking = false
	sprite.stop()
	sprite.speed_scale = 1.0
	body.clear_combat_input()
	_pending_click = false
	_pending_selected_attack = false
	stock.set_recovery_allowed(false)
	last_result = "Attack interrupted" if _combat_cycle else ""

func _show_defense_pose(pose: StringName) -> void:
	_face_defense_target()
	sprite.combat_pose = pose
	sprite._process(0.0)

func _face_defense_target() -> void:
	var candidate := selected_target if is_instance_valid(selected_target) and selected_target.alive() else target
	if not is_instance_valid(candidate) or not candidate.alive(): return
	var facing: Vector3 = candidate.global_position - body.global_position
	facing.y = 0.0
	if not facing.is_zero_approx(): body.facing_world = facing.normalized()
	body.facing_index = body.direction_sector(body.facing_world, body._movement_basis())

func _guard() -> void:
	if _flight.active:
		var outcome:=_flight.step(body,get_physics_process_delta_time())
		_face_defense_target()
		if outcome==0:
			if not _guard_pressed():
				_air_return_reason="Guard released: return after landing"
				_set_state(State.Approach)
				sprite.combat_pose=&"Approach"
			return
		if outcome<0 and not Elevation.supported(body,body.global_position):
			_finish(true)
			return
	body.velocity = Vector3.ZERO
	_face_defense_target()
	if not _guard_pressed(): _after_defense()

func _after_defense() -> void:
	body.velocity = Vector3.ZERO
	if not _combat_cycle:
		_finish()
	elif _resume_return:
		_begin_return("Resume interrupted return")
	elif _sequence_slots >= _planned_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
		_begin_return("No follow-up available")
	else:
		_set_state(State.Recover)
		sprite.combat_pose = &"Stance"
		sprite._process(0.0)

func _recover(_delta: float) -> void:
	body.velocity = Vector3.ZERO
	if queued:
		_advance_queued()
	elif _elapsed >= defense.followup_window:
		_begin_return("Defense follow-up window ended")

func filter_damage(amount: float, source: Node) -> float:
	if body.get_node("HealthComponent").incoming_damage_kind == DamageTypes.Kind.MAGIC and not defense.guard_magic_enabled: return amount
	# Unknown/freed/nonspatial or colocated sources get full damage, never a free guard.
	if state != State.Guard or not is_instance_valid(source) or not source is Node3D: return amount
	var direction: Vector3 = source.global_position - body.global_position
	direction.y = 0.0
	if direction.is_zero_approx(): return amount
	var facing := Vector3(body.facing_world.x, 0.0, body.facing_world.z).normalized()
	if facing.dot(direction.normalized()) >= cos(deg_to_rad(defense.guard_half_angle_degrees)) - 0.000001:
		guard_succeeded.emit(source)
		return amount * defense.guard_damage_multiplier
	return amount

func _work_update_markers() -> void:
	var near_enemy := false
	var facing := Vector3(body.facing_world.x, 0.0, body.facing_world.z).normalized()
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if body.global_position.distance_to(candidate.global_position) <= equipped_weapon.attack_range + 2.0:
			near_enemy = true
		candidate.set_available(_candidate_valid(candidate), candidate == selected_target, _aim_angle(candidate, facing) <= settings.auto_aim_half_angle_degrees)
	_ring.visible = show_debug_attack_range and near_enemy and not is_busy() and body.is_on_floor()
	var mesh: TorusMesh = _ring.mesh
	if not is_equal_approx(mesh.outer_radius, equipped_weapon.attack_range + 0.025):
		mesh.inner_radius = equipped_weapon.attack_range - 0.025
		mesh.outer_radius = equipped_weapon.attack_range + 0.025
		_update_range_guides()

func valid_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if _candidate_valid(candidate): candidates.append(candidate)
	# Scene paths provide a stable order independent of facing/camera/group iteration.
	candidates.sort_custom(func(a: Node3D, b: Node3D): return String(a.get_path()) < String(b.get_path()))
	return candidates

func _work_refresh_selection(delta: float = 0.0) -> void:
	if is_busy(): return
	var current_valid := is_instance_valid(selected_target) and can_select(selected_target)
	var facing := Vector3(body.facing_world.x, 0.0, body.facing_world.z).normalized()
	if _manual_selection and current_valid:
		if rad_to_deg(facing.angle_to(_manual_facing)) < settings.manual_aim_release_degrees: return
		_manual_selection = false
	var best := _best_auto_target(valid_candidates(), facing)
	if not current_valid:
		selected_target = best
		_manual_selection = false
		_aim_candidate = null
		_aim_elapsed = 0.0
		return
	if best == selected_target or not _auto_target_improves(best, facing):
		_aim_candidate = null
		_aim_elapsed = 0.0
		return
	if _aim_candidate != best:
		_aim_candidate = best
		_aim_elapsed = 0.0
	_aim_elapsed += delta
	if _aim_elapsed >= settings.aim_stability_seconds:
		selected_target = best
		_aim_candidate = null
		_aim_elapsed = 0.0

func _aim_distance(candidate: Node3D) -> float:
	var direction := candidate.global_position - body.global_position
	return Vector2(direction.x, direction.z).length()

func _aim_angle(candidate: Node3D, facing: Vector3) -> float:
	var direction := candidate.global_position - body.global_position
	direction.y = 0.0
	return rad_to_deg(facing.angle_to(direction.normalized()))

func _best_auto_target(candidates: Array[Node3D], facing: Vector3) -> Node3D:
	var front: Array[Node3D] = []
	var nearest := INF
	for candidate in candidates:
		if _aim_angle(candidate, facing) <= settings.auto_aim_half_angle_degrees:
			front.append(candidate)
			nearest = minf(nearest, _aim_distance(candidate))
	var pool := front if not front.is_empty() else candidates
	var best: Node3D
	var best_angle := INF
	# candidates arrive in stable NodePath order. Compare the near-distance band
	# against its minimum, avoiding a non-transitive approximate-distance sort.
	for candidate in pool:
		if not front.is_empty() and _aim_distance(candidate) > nearest + settings.auto_aim_distance_tie: continue
		var angle := _aim_angle(candidate, facing)
		if best == null or (angle < best_angle and not is_equal_approx(angle, best_angle)):
			best = candidate
			best_angle = angle
	return best

func _auto_target_improves(candidate: Node3D, facing: Vector3) -> bool:
	if candidate == null: return false
	var next_angle := _aim_angle(candidate, facing)
	var current_angle := _aim_angle(selected_target, facing)
	if next_angle <= settings.auto_aim_half_angle_degrees:
		# Entry uses the strict cone; only the existing selection gets an exit band.
		if current_angle > settings.auto_aim_half_angle_degrees + settings.aim_hysteresis_degrees: return true
		var gain := _aim_distance(selected_target) - _aim_distance(candidate)
		if gain > settings.auto_aim_distance_hysteresis: return true
		return absf(gain) <= settings.auto_aim_distance_tie and current_angle - next_angle > settings.aim_hysteresis_degrees
	# No forward candidate: keep the existing angle-only fallback hysteresis.
	return current_angle - next_angle > settings.aim_hysteresis_degrees

func _select_manually(candidate: Node3D) -> void:
	selected_target = candidate
	_manual_selection = true
	_manual_facing = Vector3(body.facing_world.x, 0.0, body.facing_world.z).normalized()
	_aim_candidate = null
	_aim_elapsed = 0.0

func cycle_target() -> void:
	if state == State.Return: return
	var candidates := valid_candidates()
	if candidates.is_empty():
		selected_target = null
		return
	var index := candidates.find(selected_target)
	_select_manually(candidates[(index + 1) % candidates.size()])
	if queued: queued_attack_target = selected_target

func pick_target(screen_position: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return null
	var origin := camera.project_ray_origin(screen_position)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 200.0, 1 | 4 | 8)
	ray.collide_with_areas = true
	var result := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if result.is_empty(): return null
	# Resolve only the frontmost collider. Never select through an unassigned body or wall.
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if candidate is Target and candidate.accepts_click(result.collider):
			if _candidate_valid(candidate): return candidate
			return null
	return null

func pick_attack_target(screen_position: Vector2) -> Node3D:
	# Preserve the existing frontmost valid direct click before offering assistance.
	var direct := pick_target(screen_position)
	if direct != null: return direct
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(body.global_position): return null
	if not screen_position.is_finite() or not get_viewport().get_visible_rect().has_point(screen_position): return null
	# Logical foot points share a ground plane; marker/sprite offsets must not tilt aim.
	var screen_origin := camera.unproject_position(body.global_position)
	var click_direction := screen_position - screen_origin
	if click_direction.is_zero_approx(): return null
	var tolerance := deg_to_rad(MotionSettings.bounded(settings.directional_click_tolerance_degrees, 0.0, 90.0, 20.0))
	var best: Node3D
	var best_angle := INF
	var best_distance := INF
	# Reuse marker eligibility (including combo rules), then the existing distance
	# priority and stable NodePath order for equal screen angles. Facing is irrelevant.
	for candidate in valid_candidates():
		if camera.is_position_behind(candidate.global_position) or not _framed(candidate): continue
		var direction := camera.unproject_position(candidate.global_position) - screen_origin
		if direction.is_zero_approx(): continue
		var angle := absf(click_direction.angle_to(direction))
		if angle > tolerance + 0.000001: continue
		if candidate == selected_target: return candidate
		var distance := _aim_distance(candidate)
		if best == null or (angle < best_angle and not is_equal_approx(angle, best_angle)) or (is_equal_approx(angle, best_angle) and distance < best_distance and not is_equal_approx(distance, best_distance)):
			best = candidate
			best_angle = angle
			best_distance = distance
	return best

func can_select(candidate: Node3D) -> bool:
	if not stock.can_spend(equipped_weapon.stock_cost_per_hit): return false
	if not is_instance_valid(candidate) or not candidate is Target or not candidate.alive(): return false
	if not body.is_on_floor() or body.velocity.y > 0.0 or sprite._attacking: return false
	if body.get_node("HealthComponent").current_hp <= 0.0: return false
	var difference := candidate.global_position - body.global_position
	if Vector2(difference.x, difference.z).length() > equipped_weapon.attack_range: return false
	if equipped_weapon.hit_height_up<0.0 and absf(difference.y)>settings.floor_tolerance: return false
	return _target_path_safe(candidate)

func _candidate_valid(candidate: Node3D) -> bool:
	return can_combo_select(candidate) if is_busy() else can_select(candidate)

func can_combo_select(candidate: Node3D) -> bool:
	if not _finishing_reason.is_empty(): return false
	if state != State.Approach and state != State.Attack and state != State.Recover: return false
	var unpaid := 1 if state == State.Approach else 0
	if _sequence_slots + unpaid >= _planned_hits: return false
	if not stock.can_spend(_active_weapon.stock_cost_per_hit * (1 + unpaid)): return false
	return _next_target_safe(candidate)

func _next_target_safe(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or not candidate is Target or not candidate.alive(): return false
	var difference := candidate.global_position - return_anchor
	if Vector2(difference.x, difference.z).length() > _active_weapon.attack_range: return false
	if not _framed(candidate): return false
	return _target_path_safe(candidate)

func _target_path_safe(candidate: Node3D) -> bool:
	var weapon:=_active_weapon if _combat_cycle else equipped_weapon
	if weapon.elevation_travel!=null:
		var plan:=_elevation_plan(candidate,weapon)
		return not plan.is_empty() and (not plan.in_place or _flight.active or _standing_safe())
	if weapon.hit_height_up>=0.0 and _in_place(candidate,weapon): return _blade_clear(candidate.global_position)
	return Path.clear(body, attack_position(candidate), settings, body.global_position) and Path.strike_clear(body, candidate.global_position, settings)

func _blade_clear(at: Vector3) -> bool:
	var weapon:=_active_weapon if _combat_cycle else equipped_weapon
	return BladeTerrain.clear(body,at,settings) if weapon.hit_height_up>=0.0 else Path.strike_clear(body,at,settings)

func _strike_in_range(candidate: Node3D, weapon: WeaponData, facing: Vector3) -> bool:
	# One geometry predicate for movement decisions and the existing damage path.
	if weapon.hit_shape == WeaponData.HitShape.SINGLE_TARGET:
		return body.global_position.distance_to(candidate.global_position) <= settings.stop_distance + 0.1
	return Sweep.contains(body.global_position, facing, candidate.global_position, weapon)

func _in_place(candidate: Node3D, weapon: WeaponData) -> bool:
	return _strike_in_range(candidate, weapon, candidate.global_position - body.global_position)

func _framed(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate): return false
	if not is_instance_valid(camera_rig): return true
	var destination := attack_position(candidate)
	var points: Array[Vector3] = []
	for base in [body.global_position, destination, candidate.global_position]:
		points.append(base + Vector3.UP * 0.1)
		points.append(base + Vector3.UP * 1.7)
	return camera_rig.frames_points(points, settings.screen_margin)

func attack_position(candidate: Node3D) -> Vector3:
	var weapon := _active_weapon if _combat_cycle else equipped_weapon
	if weapon.elevation_travel!=null:
		var result:=_elevation_plan(candidate,weapon)
		if not result.is_empty(): return result.destination
	if _in_place(candidate, weapon): return body.global_position
	var direction := candidate.global_position - body.global_position
	direction.y = 0.0
	var stopping := settings.stop_distance
	if weapon.hit_shape == WeaponData.HitShape.SWEEP: stopping = minf(stopping, weapon.melee_reach)
	if direction.length() <= stopping: return body.global_position
	return candidate.global_position - direction.normalized() * stopping

func request_attack(candidate: Node3D) -> bool:
	# Display hints never authorize actions, even in the same physics frame.
	_plan_cache.clear()
	_plan_frame=-1
	if is_busy() or not can_select(candidate): return _reject("Invalid target, state or stock")
	_active_weapon = equipped_weapon.duplicate()
	if _active_weapon.elevation_travel!=null: _active_weapon.elevation_travel=_active_weapon.elevation_travel.duplicate()
	_elevation_cycle=false
	_travel_history.clear()
	_return_goals.clear()
	_air_return_reason=""
	_finishing_reason = ""
	_active_motion = (_active_weapon.motion if _active_weapon.motion != null else MotionSettings.new()).snapshot()
	_active_weapon.combo_stance_duration = MotionSettings.bounded(_active_weapon.combo_stance_duration, 0.0, 1.0, 0.12)
	_active_weapon.combo_input_window = MotionSettings.bounded(_active_weapon.combo_input_window, 0.0, 2.0, 0.5)
	_planned_hits = mini(_active_weapon.max_combo_hits, int(stock.current / maxi(1, _active_weapon.stock_cost_per_hit)))
	_sequence_slots = 0
	_target_lost = false
	_empty_slot = false
	_combat_cycle = true
	body.sample_movement_input()
	_return_press_seen = body.movement_press_serial
	_return_neutral_seen = body.movement_neutral_serial
	_return_input_armed = body.movement_neutral
	_resume_return = false
	combo_hits = 0
	queued = false
	queued_attack_target = null
	_waiting = false
	stock.set_recovery_allowed(false)
	return_anchor = body.global_position
	return_error = 0.0
	last_result = ""
	target = candidate
	_select_manually(candidate)
	_target_anchor = candidate.global_position
	_destination = attack_position(candidate)
	_face_target()
	_manual_facing = body.facing_world
	if is_instance_valid(camera_rig): camera_rig.hold_follow()
	body.clear_combat_input()
	_hit_done = false
	_hit_pending = false
	_attack_finished = false
	if _in_place(target, _active_weapon): _start_strike()
	else: _begin_travel(State.Approach, _destination, _active_motion.approach_speed)
	return true

func _reject(reason: String) -> bool:
	last_result = reason
	attack_rejected.emit(reason)
	return false

func request_followup(candidate: Node3D = null, replace: bool = false) -> bool:
	if not _finishing_reason.is_empty(): return _reject("Attack sequence ending")
	if state != State.Approach and state != State.Attack and state != State.Recover: return _reject("Not accepting input")
	if queued and not replace: return _reject("Queue full")
	if state != State.Recover and _target_alive() and not _target_lost and not _target_valid(): return _reject("Target moved")
	if candidate == null:
		if not is_instance_valid(selected_target): return _reject("Selected target lost")
		candidate = selected_target
	# Approach has not paid for the first strike yet; reserve room for both strikes.
	var pending_first := 1 if state == State.Approach else 0
	if _sequence_slots + pending_first >= _planned_hits: return _reject("Combo limit")
	if not stock.can_spend(_active_weapon.stock_cost_per_hit * (1 + pending_first)): return _reject("No stock")
	if not _next_target_safe(candidate): return _reject("Next target unsafe or offscreen")
	_select_manually(candidate)
	queued = true
	queued_attack_target = candidate
	return true

func _advance_queued() -> void:
	if not is_instance_valid(queued_attack_target) or not queued_attack_target.alive():
		queued = false
		queued_attack_target = null
		_start_empty_slot()
		return
	if not _next_target_safe(queued_attack_target):
		_begin_return("Queued target unsafe")
		return
	var next := queued_attack_target
	queued = false
	queued_attack_target = null
	_target_lost = false
	_empty_slot = false
	var needs_travel := not _in_place(next, _active_weapon)
	var refresh_anchor := not _target_alive() or next != target or state == State.Recover or needs_travel
	target = next
	if refresh_anchor: _target_anchor = target.global_position
	_waiting = false
	_face_target()
	if needs_travel: _begin_travel(State.Approach, attack_position(target), _active_motion.approach_speed)
	else: _start_strike()

func _start_strike() -> void:
	if not _target_alive():
		_start_empty_slot()
		return
	if not _target_valid() or _sequence_slots >= _planned_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
		_begin_return("Strike no longer available")
		return
	queued = false
	queued_attack_target = null
	_waiting = false
	_grace_elapsed = 0.0
	_hit_done = false
	_hit_pending = false
	_attack_finished = false
	_target_lost = false
	_empty_slot = false
	_finishing_reason = ""
	sprite.combat_pose = &"Attack"
	strike_facing = body.facing_world
	_set_state(State.Attack)
	if not sprite.request_attack_preview(_strike_duration(), _active_motion):
		_begin_return("Animation unavailable")
		return
	stock.spend(_active_weapon.stock_cost_per_hit)
	combo_hits += 1
	_sequence_slots += 1
	attack_id += 1
	_hit_pending = _hit_due()
	attack_accepted.emit(attack_id, combo_hits)

func _strike_duration() -> float:
	return _active_weapon.swing_duration()

func _start_empty_slot(approach_remaining: float = 0.0) -> void:
	# Preserve the weapon's planned rhythm, without an animation, ID, hit or cost.
	if _sequence_slots >= _planned_hits:
		_begin_return("Attack sequence finished")
		return
	_target_lost = true
	_empty_slot = true
	target = null
	_sequence_slots += 1
	_empty_duration = _strike_duration() + approach_remaining
	_attack_finished = false
	_hit_pending = false
	_waiting = true
	_grace_elapsed = 0.0
	body.velocity = Vector3.ZERO
	sprite._attacking = false
	sprite.stop()
	sprite.speed_scale = 1.0
	sprite.combat_pose = &"Stance"
	_set_state(State.Attack)
	sprite._process(0.0)

func _face_target() -> void:
	if not is_instance_valid(target): return
	var facing := target.global_position - body.global_position
	facing.y = 0.0
	if not facing.is_zero_approx(): body.facing_world = facing.normalized()
	body.facing_index = body.direction_sector(body.facing_world, body._movement_basis())

func _begin_travel(next: State, destination: Vector3, speed: float) -> void:
	_travel_start = body.global_position
	_destination = destination
	_travel_unavailable=false
	if next==State.Approach: _travel_history.append(_travel_start)
	var air:=Elevation.plan(body,_travel_start,destination,settings,_active_weapon.elevation_travel,_active_motion,next==State.Return)
	if not air.is_empty() and air.air:
		_elevation_cycle=true
		_flight.begin(air)
		_duration=air.duration
		_set_state(next)
		sprite.combat_pose=&"Approach" if next==State.Approach else &"Return"
		return
	if absf(destination.y-_travel_start.y)>settings.floor_tolerance:
		_travel_unavailable=true
	var resolved := Path.contact_position(body, destination, settings)
	if resolved.is_finite() and Path.clear(body, destination, settings, _travel_start):
		# Apply only the bounded native recovery already accepted by Path.clear.
		# Plan from/to those safe positions so interpolation cannot steer back into contact.
		body.move_and_collide(Vector3.ZERO, false, body.safe_margin)
		_travel_start = body.global_position
		_destination = resolved
	var minimum := _active_motion.return_minimum_travel_time if next == State.Return else _active_motion.minimum_travel_time
	var maximum := _active_motion.return_maximum_travel_time if next == State.Return else _active_motion.maximum_travel_time
	_duration = clampf(_travel_start.distance_to(_destination) / maxf(speed, 0.1), minimum, maximum)
	_set_state(next)
	sprite.combat_pose = &"Approach" if next == State.Approach else &"Return"
	sprite._process(0.0)

func _set_state(next: State) -> void:
	state = next
	_elapsed = 0.0
	state_changed.emit(state)

func _target_alive() -> bool:
	return is_instance_valid(target) and target.alive()

func _target_valid() -> bool:
	return _target_alive() and target.global_position.distance_to(_target_anchor) < 0.05

func _approach(delta: float) -> void:
	if _flight.active:
		var outcome:=_flight.step(body,delta)
		if outcome==0: return
		if outcome<0:
			_begin_return("Jump obstructed")
			return
		if not _air_return_reason.is_empty():
			var reason:=_air_return_reason
			_air_return_reason=""
			_begin_return(reason)
			return
	if not _target_alive():
		_start_empty_slot(maxf(0.0, _duration + _active_motion.approach_attack_delay - _elapsed))
		return
	if not _target_valid():
		_begin_return("Target lost or moved")
		return
	_face_target()
	if not _move_travel(delta):
		_begin_return("Approach blocked")
	elif _elapsed >= _duration:
		body.velocity = Vector3.ZERO
		sprite.combat_pose = &"Stance"
		if _elapsed < _duration + _active_motion.approach_attack_delay: return
		var reserved := queued
		var reserved_target := queued_attack_target
		_start_strike()
		if state == State.Attack:
			queued = reserved
			queued_attack_target = reserved_target

func _move_travel(delta: float) -> bool:
	if _flight.active:
		var outcome:=_flight.step(body,delta)
		if outcome>0: _elapsed=_duration
		return outcome>=0
	if _travel_unavailable: return false
	if _elevation_cycle and _elapsed>=_duration and body.global_position.distance_to(_destination)<0.02: return true
	var fraction := clampf(_elapsed / _duration, 0.0, 1.0)
	# Smooth acceleration/deceleration; the capsule follows the visible route.
	var next := _travel_start.lerp(_destination, smoothstep(0.0, 1.0, fraction))
	if not Path.clear(body, next, settings, body.global_position): return false
	var motion := next - body.global_position
	body.velocity = motion / maxf(delta, 0.0001)
	var collision := body.move_and_collide(motion, false, body.safe_margin)
	return collision == null

func _on_frame() -> void:
	if _hit_due():
		_hit_pending = true

func _hit_due() -> bool:
	return state == State.Attack and not _empty_slot and _active_motion != null and String(sprite.animation).begins_with("attack_") and sprite.attack_phase() + 0.000001 >= _active_motion.hit_phase(sprite.sprite_frames, sprite.animation)

func _on_finished() -> void:
	if state == State.Attack:
		if _hit_due(): _hit_pending = true
		_attack_finished = true
		_waiting = true
		_grace_elapsed = 0.0
		sprite.combat_pose = &"Stance"

func _strike_targets() -> Array[Node3D]:
	var recipients: Array[Node3D] = []
	if _active_weapon.hit_shape == WeaponData.HitShape.SINGLE_TARGET:
		if _target_alive() and _strike_in_range(target, _active_weapon, strike_facing) and _blade_clear(target.global_position):
			recipients.append(target)
		return recipients
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if not candidate is Target or not candidate.alive(): continue
		# The original cycle boundary remains fixed even for incidental victims.
		var from_anchor: Vector3 = candidate.global_position - return_anchor
		if Vector2(from_anchor.x,from_anchor.z).length() > _active_weapon.attack_range: continue
		if not _strike_in_range(candidate, _active_weapon, strike_facing): continue
		if not _blade_clear(candidate.global_position): continue
		var points: Array[Vector3] = [candidate.global_position+Vector3.UP*0.1,candidate.global_position+Vector3.UP*1.7]
		if is_instance_valid(camera_rig) and not camera_rig.frames_points(points,settings.screen_margin): continue
		recipients.append(candidate)
	recipients.sort_custom(func(a: Node3D,b: Node3D): return String(a.get_path()) < String(b.get_path()))
	return recipients

func _attack(delta: float) -> void:
	body.velocity = Vector3.ZERO
	if not _standing_safe():
		_begin_return("Attack path blocked")
		return
	if not _target_alive(): _target_lost = true
	if not _target_lost:
		if not _target_valid() or not _blade_clear(target.global_position):
			_begin_return("Target moved or attack path blocked")
			return
		_face_target()
	# Frame boundaries and sub-frame offsets read the same engine animation phase.
	# Polling also catches a very short frame skipped between physics ticks.
	if _hit_due(): _hit_pending = true
	if _hit_pending and not _hit_done and not _target_lost:
		_hit_done = true
		# Snapshot before damage signals can kill/free targets. One HP owner per swing,
		# including multiple selectable parts that share the same HealthComponent.
		var paid_id := attack_id
		var damaged: Dictionary = {}
		for victim in _strike_targets():
			if state != State.Attack or attack_id != paid_id: break
			if not is_instance_valid(victim) or not victim.alive(): continue
			var hp: HealthComponent = victim.health
			if damaged.has(hp.get_instance_id()): continue
			damaged[hp.get_instance_id()] = true
			hp.damage(_active_weapon.base_damage,body)
			if is_instance_valid(victim): hit.emit(victim)
	# Damage/death callbacks can free the target or cancel the player's cycle.
	if state != State.Attack: return
	if not _target_alive(): _target_lost = true
	if _empty_slot and not _attack_finished and _elapsed >= _empty_duration:
		_attack_finished = true
		_grace_elapsed = 0.0
	var timeout := maxf(settings.attack_timeout, _strike_duration() + 0.5)
	if _empty_slot and not _attack_finished: return
	if not _attack_finished and _elapsed >= timeout:
		_begin_return("Animation timeout")
	elif _attack_finished:
		if not _finishing_reason.is_empty():
			_finish_attack_cycle(_finishing_reason, delta)
		elif _sequence_slots >= _planned_hits:
			_finish_attack_cycle("Combo finished", delta)
		elif _target_lost:
			_grace_elapsed += delta
			if _grace_elapsed >= _active_weapon.combo_stance_duration:
				if queued: _advance_queued()
				else: _start_empty_slot()
		elif not stock.can_spend(_active_weapon.stock_cost_per_hit):
			_finish_attack_cycle("No stock", delta)
		else:
			_grace_elapsed += delta
			if queued:
				if _grace_elapsed >= _active_weapon.combo_stance_duration: _advance_queued()
			elif _grace_elapsed >= _active_weapon.combo_input_window:
				_finish_attack_cycle("Input window ended", delta)

func _finish_attack_cycle(reason: String, delta: float) -> void:
	if _finishing_reason.is_empty():
		_finishing_reason = reason
		_grace_elapsed = 0.0
	else:
		_grace_elapsed += delta
	if _grace_elapsed >= _active_motion.final_attack_wait:
		_begin_return(reason)

func _begin_return(reason: String) -> void:
	if not _combat_cycle or state == State.Return: return
	if _flight.active:
		_air_return_reason=reason
		_interrupt_attack()
		return
	_interrupt_attack()
	last_result = reason
	if body.global_position.distance_squared_to(return_anchor) <= RETURN_POSITION_EPSILON * RETURN_POSITION_EPSILON:
		_finish(true)
		return
	if _elevation_cycle:
		_return_goals.assign(_travel_history)
		_return_goals.reverse()
		while not _return_goals.is_empty() and body.global_position.distance_to(_return_goals[0])<0.02: _return_goals.pop_front()
		if _return_goals.is_empty(): _return_goals.append(return_anchor)
		_begin_travel(State.Return,_return_goals.pop_front(),_active_motion.return_speed)
	else: _begin_travel(State.Return, return_anchor, _active_motion.return_speed)

func _return(delta: float) -> void:
	if not _move_travel(delta):
		last_result += "; return blocked, stopped at safe position"
		_finish(true)
	elif _elapsed >= _duration:
		if not _return_goals.is_empty(): _begin_travel(State.Return,_return_goals.pop_front(),_active_motion.return_speed)
		else: _finish(true)

func _finish(resume_held_movement: bool = false) -> void:
	_flight.active=false
	_air_return_reason=""
	_return_goals.clear()
	return_error = body.global_position.distance_to(return_anchor) if _combat_cycle else 0.0
	if _combat_cycle:
		if resume_held_movement: body.resume_movement_input()
		else: body.require_movement_release()
	_combat_cycle = false
	_return_input_armed = false
	_resume_return = false
	queued = false
	queued_attack_target = null
	_waiting = false
	target = null
	sprite.combat_pose = &""
	body.clear_combat_input()
	if is_instance_valid(camera_rig): camera_rig.release_follow()
	_manual_facing = body.facing_world
	_set_state(State.Idle)
	sprite._process(0.0)

func cancel() -> void:
	_pending_guard = false
	_mouse_guard_held = false
	_return_input_armed = false
	_wait_defense_release = true
	_pending_click = false
	_pending_selected_attack = false
	queued = false
	queued_attack_target = null
	if not is_busy(): return
	last_result = "Cancelled"
	sprite._attacking = false
	sprite.speed_scale = 1.0
	_finish()

func _exit_tree() -> void:
	if is_instance_valid(body): body.get_node("HealthComponent").damage_filter = Callable()
	queued = false
	queued_attack_target = null
	if is_instance_valid(camera_rig): camera_rig.release_follow()
	_pending_click = false
	_pending_selected_attack = false

func _elevation_plan(candidate: Node3D, weapon: WeaponData) -> Dictionary:
	var started:=Work.start(body)
	var result: Dictionary=_work_elevation_plan(candidate,weapon)
	Work.finish(body,"player.preview_plan",started)
	return result

func physics_step(delta: float) -> void:
	var started:=Work.start(body)
	_work_physics_step(delta)
	Work.finish(body,"player.physics",started)

func _update_markers() -> void:
	var started:=Work.start(body)
	var previous:=_preview_only
	_preview_only=true
	_work_update_markers()
	_preview_only=previous
	Work.finish(body,"player.markers",started)

func _refresh_selection(delta: float = 0.0) -> void:
	var started:=Work.start(body)
	var previous:=_preview_only
	_preview_only=true
	_work_refresh_selection(delta)
	_preview_only=previous
	Work.finish(body,"player.selection",started)
