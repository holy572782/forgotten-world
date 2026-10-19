extends Node
## Single-owner state machine. Controller calls physics_step before locomotion.
const Settings = preload("res://scripts/combat/target_dash_settings.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const Target = preload("res://scripts/combat/targetable.gd")
enum State { Idle, Approach, Attack, Return }
signal state_changed(next: int)
signal hit(target: Node)
signal attack_accepted(attack_id: int, combo: int)
signal attack_rejected(reason: String)
@export var settings: Settings = preload("res://resources/target_dash_settings.tres")
@export var equipped_weapon: WeaponData = preload("res://resources/weapons/one_handed_sword.tres"):
	set(value):
		if value != null and not is_busy(): equipped_weapon = value
var combo_hits := 0
var attack_id := 0
var queued := false
var _waiting := false
var _grace_elapsed := 0.0
var _active_weapon: WeaponData
var state: State = State.Idle
var return_anchor := Vector3.ZERO
var return_error := 0.0
var last_result := ""
var target: Node3D
var _target_anchor := Vector3.ZERO
var _destination := Vector3.ZERO
var _travel_start := Vector3.ZERO
var _duration := 0.3
var _elapsed := 0.0
var _hit_pending := false
var _hit_done := false
var _attack_finished := false
var _pending_click := false
var _click_position := Vector2.ZERO
var _ring: MeshInstance3D
@onready var body: CharacterBody3D = get_parent()
@onready var stock: AttackStockComponent = body.get_node("AttackStockComponent")
@onready var sprite: AnimatedSprite3D = body.get_node("AnimatedSprite3D")

func _ready() -> void:
	body.combat = self
	body.collision_mask |= 4
	sprite.frame_changed.connect(_on_frame)
	sprite.attack_completed.connect(_on_finished)
	body.get_node("HealthComponent").depleted.connect(func(_source: Node): cancel())
	_ring = MeshInstance3D.new()
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

func is_busy() -> bool:
	return state != State.Idle

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_action_pressed("target_attack"):
		if not is_busy():
			_pending_click = true
			_click_position = event.position
		else:
			request_followup()
		get_viewport().set_input_as_handled()

func physics_step(delta: float) -> void:
	var was_busy := is_busy()
	if _pending_click:
		_pending_click = false
		var selected := pick_target(_click_position)
		if selected != null:
			request_attack(selected)
	if is_busy():
		_elapsed += delta
		match state:
			State.Approach: _approach(delta)
			State.Attack: _attack(delta)
			State.Return: _return(delta)
	stock.set_recovery_allowed(not was_busy and not is_busy() and body.get_node("HealthComponent").current_hp > 0.0)
	stock.advance(delta)
	_update_markers()

func _update_markers() -> void:
	var near_enemy := false
	for candidate in get_tree().get_nodes_in_group("combat_targets"):
		if body.global_position.distance_to(candidate.global_position) <= equipped_weapon.attack_range + 2.0:
			near_enemy = true
		candidate.set_available(not is_busy() and can_select(candidate))
	_ring.visible = near_enemy and not is_busy() and body.is_on_floor()
	var mesh: TorusMesh = _ring.mesh
	if not is_equal_approx(mesh.outer_radius, equipped_weapon.attack_range + 0.025):
		mesh.inner_radius = equipped_weapon.attack_range - 0.025
		mesh.outer_radius = equipped_weapon.attack_range + 0.025

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
			if candidate.marker.visible and can_select(candidate): return candidate
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

func attack_position(candidate: Node3D) -> Vector3:
	var direction := candidate.global_position - body.global_position
	direction.y = 0.0
	if direction.length() <= settings.stop_distance: return body.global_position
	return candidate.global_position - direction.normalized() * settings.stop_distance

func request_attack(candidate: Node3D) -> bool:
	if is_busy() or not can_select(candidate): return _reject("Invalid target, state or stock")
	_active_weapon = equipped_weapon.duplicate()
	combo_hits = 0
	queued = false
	_waiting = false
	stock.set_recovery_allowed(false)
	return_anchor = body.global_position
	return_error = 0.0
	last_result = ""
	target = candidate
	_target_anchor = candidate.global_position
	_destination = attack_position(candidate)
	_face_target()
	body.clear_combat_input()
	_hit_done = false
	_hit_pending = false
	_attack_finished = false
	_begin_travel(State.Approach, _destination, settings.approach_speed)
	return true

func _reject(reason: String) -> bool:
	attack_rejected.emit(reason)
	return false

func request_followup() -> bool:
	if state != State.Approach and state != State.Attack: return _reject("Not accepting input")
	if queued or not _target_valid(): return _reject("Queue full or target lost")
	# Approach has not paid for the first strike yet; reserve room for both strikes.
	var pending_first := 1 if state == State.Approach else 0
	if combo_hits + pending_first >= _active_weapon.max_combo_hits: return _reject("Combo limit")
	if not stock.can_spend(_active_weapon.stock_cost_per_hit * (1 + pending_first)): return _reject("No stock")
	queued = true
	return true

func _start_strike() -> void:
	if not _target_valid() or combo_hits >= _active_weapon.max_combo_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
		_begin_return("Strike no longer available")
		return
	queued = false
	_waiting = false
	_grace_elapsed = 0.0
	_hit_done = false
	_hit_pending = false
	_attack_finished = false
	sprite.combat_pose = &"Attack"
	_set_state(State.Attack)
	if not sprite.request_attack_preview():
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
	_duration = clampf(_travel_start.distance_to(destination) / maxf(speed, 0.1), settings.minimum_travel_time, maxf(settings.minimum_travel_time, settings.maximum_travel_time))
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
		_start_strike()
		if state == State.Attack: queued = reserved

func _move_travel(delta: float) -> bool:
	var fraction := clampf(_elapsed / _duration, 0.0, 1.0)
	# Smooth acceleration/deceleration; the capsule follows the visible route.
	var next := _travel_start.lerp(_destination, smoothstep(0.0, 1.0, fraction))
	if not Path.clear(body, next, settings, body.global_position): return false
	var motion := next - body.global_position
	body.velocity = motion / maxf(delta, 0.0001)
	var collision := body.move_and_collide(motion)
	return collision == null

func _on_frame() -> void:
	if state == State.Attack and String(sprite.animation).begins_with("attack_") and sprite.frame == settings.hit_frame:
		_hit_pending = true

func _on_finished() -> void:
	if state == State.Attack:
		_attack_finished = true

func _attack(delta: float) -> void:
	body.velocity = Vector3.ZERO
	if not _target_valid():
		_begin_return("Target lost or moved")
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
	if not _attack_finished and _elapsed >= settings.attack_timeout:
		_begin_return("Animation timeout")
	elif _attack_finished:
		if combo_hits >= _active_weapon.max_combo_hits or not stock.can_spend(_active_weapon.stock_cost_per_hit):
			_begin_return("Combo finished")
		elif queued:
			_start_strike()
		elif not _waiting:
			_waiting = true
			_grace_elapsed = 0.0
		else:
			_grace_elapsed += delta
			if _grace_elapsed >= _active_weapon.combo_input_window: _begin_return("Input window ended")

func _begin_return(reason: String) -> void:
	queued = false
	_waiting = false
	last_result = reason
	sprite._attacking = false
	_begin_travel(State.Return, return_anchor, settings.return_speed)

func _return(delta: float) -> void:
	if not _move_travel(delta):
		last_result += "; return blocked, stopped at safe position"
		_finish()
	elif _elapsed >= _duration:
		_finish()

func _finish() -> void:
	queued = false
	_waiting = false
	return_error = body.global_position.distance_to(return_anchor)
	target = null
	sprite.combat_pose = &""
	body.clear_combat_input()
	_set_state(State.Idle)
	sprite._process(0.0)

func cancel() -> void:
	_pending_click = false
	queued = false
	if not is_busy(): return
	last_result = "Cancelled"
	sprite._attacking = false
	_finish()

func _exit_tree() -> void:
	queued = false
	_pending_click = false
