extends Node
## Single-owner state machine. Controller calls physics_step before locomotion.
const Settings = preload("res://scripts/combat/target_dash_settings.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const Target = preload("res://scripts/combat/targetable.gd")
enum State { Idle, Approach, Attack, Return, Guard, Recover }
signal state_changed(next: int)
signal hit(target: Node)
signal attack_accepted(attack_id: int, combo: int)
signal attack_rejected(reason: String)
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
var motion_owned_tick := false
var _combat_cycle := false
var _resume_return := false
var _return_input_armed := false
var _return_press_seen := 0
var _return_neutral_seen := 0
var _pending_guard := false
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return
	if event.is_action_pressed("guard"):
		_pending_guard = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_on"):
		cycle_target()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") or event.is_action_pressed("target_attack"):
		if is_busy():
			if event is InputEventMouseButton:
				var candidate := pick_target(event.position)
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

func physics_step(delta: float) -> void:
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
		var selected := pick_target(_click_position)
		if selected != null:
			request_attack(selected)
	elif _pending_selected_attack and not is_busy():
		request_attack(selected_target)
	_pending_selected_attack = false
	if is_busy():
		if state == State.Approach or state == State.Attack:
			if not is_instance_valid(target):
				_begin_return("Target lost")
			elif not _framed(target):
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

func _defense_input() -> bool:
	var guard_pressed := Input.is_action_pressed("guard")
	var guard_request := guard_pressed or _pending_guard
	_pending_guard = false
	if _wait_defense_release:
		if not guard_pressed: _wait_defense_release = false
		return false
	if guard_request:
		if state != State.Guard:
			if not _defense_grounded(): return _reject("Guard rejected: airborne or unsafe floor")
			_interrupt_attack()
			_set_state(State.Guard)
			_show_defense_pose(&"Guard")
		return true
	return false

func _defense_grounded() -> bool:
	# Combat travel uses move_and_collide, whose floor flag is stale; validate
	# the actual capsule footprint as well. Airborne FREE input is rejected.
	if state == State.Idle: return body.is_on_floor() and body.velocity.y <= 0.0
	return Path.clear(body, body.global_position, settings, body.global_position)

func _interrupt_attack() -> void:
	_resume_return = _resume_return or state == State.Return
	queued = false
	queued_attack_target = null
	_waiting = false
	_hit_pending = false
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
	body.velocity = Vector3.ZERO
	_face_defense_target()
	if not Input.is_action_pressed("guard"): _after_defense()

func _after_defense() -> void:
	body.velocity = Vector3.ZERO
	if not _combat_cycle:
		_finish()
	elif _resume_return:
		_begin_return("Resume interrupted return")
	elif combo_hits >= _active_weapon.max_combo_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
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
	# Unknown/freed/nonspatial or colocated sources get full damage, never a free guard.
	if state != State.Guard or not is_instance_valid(source) or not source is Node3D: return amount
	var direction: Vector3 = source.global_position - body.global_position
	direction.y = 0.0
	if direction.is_zero_approx(): return amount
	var facing := Vector3(body.facing_world.x, 0.0, body.facing_world.z).normalized()
	if facing.dot(direction.normalized()) >= cos(deg_to_rad(defense.guard_half_angle_degrees)) - 0.000001:
		return amount * defense.guard_damage_multiplier
	return amount

func _update_markers() -> void:
	var near_enemy := false
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if body.global_position.distance_to(candidate.global_position) <= equipped_weapon.attack_range + 2.0:
			near_enemy = true
		candidate.set_available(_candidate_valid(candidate), candidate == selected_target)
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

func _refresh_selection(delta: float = 0.0) -> void:
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

func can_select(candidate: Node3D) -> bool:
	if not stock.can_spend(equipped_weapon.stock_cost_per_hit): return false
	if not is_instance_valid(candidate) or not candidate is Target or not candidate.alive(): return false
	if not body.is_on_floor() or body.velocity.y > 0.0 or sprite._attacking: return false
	if body.get_node("HealthComponent").current_hp <= 0.0: return false
	var difference := candidate.global_position - body.global_position
	if Vector2(difference.x, difference.z).length() > equipped_weapon.attack_range: return false
	if absf(difference.y) > settings.floor_tolerance: return false
	return Path.sight(body, candidate.global_position) and Path.clear(body, attack_position(candidate), settings, body.global_position)

func _candidate_valid(candidate: Node3D) -> bool:
	return can_combo_select(candidate) if is_busy() else can_select(candidate)

func can_combo_select(candidate: Node3D) -> bool:
	if state != State.Approach and state != State.Attack and state != State.Recover: return false
	var unpaid := 1 if state == State.Approach else 0
	if combo_hits + unpaid >= _active_weapon.max_combo_hits: return false
	if not stock.can_spend(_active_weapon.stock_cost_per_hit * (1 + unpaid)): return false
	return _next_target_safe(candidate)

func _next_target_safe(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or not candidate is Target or not candidate.alive(): return false
	var difference := candidate.global_position - return_anchor
	if Vector2(difference.x, difference.z).length() > _active_weapon.attack_range: return false
	if not _framed(candidate): return false
	return Path.sight(body, candidate.global_position) and Path.clear(body, attack_position(candidate), settings, body.global_position)

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
	var direction := candidate.global_position - body.global_position
	direction.y = 0.0
	if direction.length() <= settings.stop_distance: return body.global_position
	return candidate.global_position - direction.normalized() * settings.stop_distance

func request_attack(candidate: Node3D) -> bool:
	if is_busy() or not can_select(candidate): return _reject("Invalid target, state or stock")
	_active_weapon = equipped_weapon.duplicate()
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
	_begin_travel(State.Approach, _destination, settings.approach_speed)
	return true

func _reject(reason: String) -> bool:
	last_result = reason
	attack_rejected.emit(reason)
	return false

func request_followup(candidate: Node3D = null, replace: bool = false) -> bool:
	if state != State.Approach and state != State.Attack and state != State.Recover: return _reject("Not accepting input")
	if queued and not replace: return _reject("Queue full")
	if state != State.Recover and not _target_valid(): return _reject("Target lost")
	if candidate == null:
		if not is_instance_valid(selected_target): return _reject("Selected target lost")
		candidate = selected_target
	# Approach has not paid for the first strike yet; reserve room for both strikes.
	var pending_first := 1 if state == State.Approach else 0
	if combo_hits + pending_first >= _active_weapon.max_combo_hits: return _reject("Combo limit")
	if not stock.can_spend(_active_weapon.stock_cost_per_hit * (1 + pending_first)): return _reject("No stock")
	if not _next_target_safe(candidate): return _reject("Next target unsafe or offscreen")
	_select_manually(candidate)
	queued = true
	queued_attack_target = candidate
	return true

func _advance_queued() -> void:
	if not is_instance_valid(queued_attack_target) or not _next_target_safe(queued_attack_target):
		_begin_return("Queued target lost or unsafe")
		return
	var next := queued_attack_target
	queued = false
	queued_attack_target = null
	if next != target or body.global_position.distance_to(attack_position(next)) > 0.05 or state == State.Recover:
		target = next
		_target_anchor = target.global_position
		_waiting = false
		_face_target()
		_begin_travel(State.Approach, attack_position(target), settings.approach_speed)
	else:
		_start_strike()

func _start_strike() -> void:
	if not _target_valid() or combo_hits >= _active_weapon.max_combo_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
		_begin_return("Strike no longer available")
		return
	queued = false
	queued_attack_target = null
	_waiting = false
	_grace_elapsed = 0.0
	_hit_done = false
	_hit_pending = false
	_attack_finished = false
	sprite.combat_pose = &"Attack"
	_set_state(State.Attack)
	var duration := _active_weapon.attack_duration / maxf(0.1, _active_weapon.attack_speed_multiplier)
	if not sprite.request_attack_preview(duration):
		_begin_return("Animation unavailable")
		return
	stock.spend(_active_weapon.stock_cost_per_hit)
	combo_hits += 1
	attack_id += 1
	_hit_pending = sprite.frame == settings.hit_frame
	attack_accepted.emit(attack_id, combo_hits)

func _face_target() -> void:
	if not is_instance_valid(target): return
	var facing := target.global_position - body.global_position
	facing.y = 0.0
	if not facing.is_zero_approx(): body.facing_world = facing.normalized()
	body.facing_index = body.direction_sector(body.facing_world, body._movement_basis())

func _begin_travel(next: State, destination: Vector3, speed: float) -> void:
	_travel_start = body.global_position
	_destination = destination
	var resolved := Path.contact_position(body, destination, settings)
	if resolved.is_finite() and Path.clear(body, destination, settings, _travel_start):
		# Apply only the bounded native recovery already accepted by Path.clear.
		# Plan from/to those safe positions so interpolation cannot steer back into contact.
		body.move_and_collide(Vector3.ZERO, false, body.safe_margin)
		_travel_start = body.global_position
		_destination = resolved
	_duration = clampf(_travel_start.distance_to(_destination) / maxf(speed, 0.1), settings.minimum_travel_time, maxf(settings.minimum_travel_time, settings.maximum_travel_time))
	_set_state(next)
	sprite.combat_pose = &"Approach" if next == State.Approach else &"Return"
	sprite._process(0.0)

func _set_state(next: State) -> void:
	state = next
	_elapsed = 0.0
	state_changed.emit(state)

func _target_valid() -> bool:
	return is_instance_valid(target) and target.alive() and target.global_position.distance_to(_target_anchor) < 0.05

func _approach(delta: float) -> void:
	if not _target_valid():
		_begin_return("Target lost or moved")
		return
	_face_target()
	if not _move_travel(delta):
		_begin_return("Approach blocked")
	elif _elapsed >= _duration:
		var reserved := queued
		var reserved_target := queued_attack_target
		_start_strike()
		if state == State.Attack:
			queued = reserved
			queued_attack_target = reserved_target

func _move_travel(delta: float) -> bool:
	var fraction := clampf(_elapsed / _duration, 0.0, 1.0)
	# Smooth acceleration/deceleration; the capsule follows the visible route.
	var next := _travel_start.lerp(_destination, smoothstep(0.0, 1.0, fraction))
	if not Path.clear(body, next, settings, body.global_position): return false
	var motion := next - body.global_position
	body.velocity = motion / maxf(delta, 0.0001)
	var collision := body.move_and_collide(motion, false, body.safe_margin)
	return collision == null

func _on_frame() -> void:
	if state == State.Attack and String(sprite.animation).begins_with("attack_") and sprite.frame == settings.hit_frame:
		_hit_pending = true

func _on_finished() -> void:
	if state == State.Attack:
		_attack_finished = true
		_waiting = true
		_grace_elapsed = 0.0
		sprite.combat_pose = &"Stance"

func _attack(delta: float) -> void:
	body.velocity = Vector3.ZERO
	if not _target_valid():
		_begin_return("Target lost or moved")
		return
	if not Path.sight(body, target.global_position) or not Path.clear(body, body.global_position, settings, body.global_position):
		_begin_return("Attack path blocked")
		return
	_face_target()
	if _hit_pending and not _hit_done:
		_hit_done = true
		if body.global_position.distance_to(target.global_position) <= settings.stop_distance + 0.1 and Path.sight(body, target.global_position):
			target.health.damage(_active_weapon.base_damage, body)
			hit.emit(target)
	if not _target_valid():
		_begin_return("Target lost or defeated")
		return
	var timeout := maxf(settings.attack_timeout, _active_weapon.attack_duration / maxf(0.1, _active_weapon.attack_speed_multiplier) + 0.5)
	if not _attack_finished and _elapsed >= timeout:
		_begin_return("Animation timeout")
	elif _attack_finished:
		if combo_hits >= _active_weapon.max_combo_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
			_begin_return("Combo finished")
		else:
			_grace_elapsed += delta
			if queued:
				if _grace_elapsed >= _active_weapon.combo_stance_duration: _advance_queued()
			elif _grace_elapsed >= _active_weapon.combo_input_window:
				_begin_return("Input window ended")

func _begin_return(reason: String) -> void:
	if not _combat_cycle or state == State.Return: return
	_interrupt_attack()
	last_result = reason
	_begin_travel(State.Return, return_anchor, settings.return_speed)

func _return(delta: float) -> void:
	if not _move_travel(delta):
		last_result += "; return blocked, stopped at safe position"
		_finish()
	elif _elapsed >= _duration:
		_finish()

func _finish() -> void:
	return_error = body.global_position.distance_to(return_anchor) if _combat_cycle else 0.0
	if _combat_cycle: body.require_movement_release()
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
