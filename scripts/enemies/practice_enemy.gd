extends CharacterBody3D
const Settings = preload("res://scripts/enemies/enemy_settings.gd")
const AttackData = preload("res://scripts/enemies/enemy_attack_data.gd")
const Projectile = preload("res://scripts/enemies/practice_projectile.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
# RETURN = home/leash return; DASH_RETURN = attack_anchor.
enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVERY, RETURN, DEAD, DASH_APPROACH, DASH_RETURN }
@export var settings: Settings = preload("res://resources/enemies/melee_practice.tres")
@export var player: CharacterBody3D
@export var show_debug_state := true
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

func _ready() -> void:
	process_physics_priority = 1 # Player reserves a stable target before enemy motion.
	home = global_position
	active_attack = settings.attack.duplicate(true)
	health.depleted.connect(_die)
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
	return player_alive() and Path.sight(self, player.global_position)

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return
	if health.current_hp <= 0.0:
		_die(null)
		return
	if not player_alive():
		clear_shots()
		if state != State.RETURN and state != State.IDLE: _set_state(State.RETURN)
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	var distance := global_position.distance_to(player.global_position) if player_alive() else INF
	var sight := has_sight()
	sight_lost = 0.0 if sight else sight_lost + delta
	var leashed := distance > settings.leash_radius or global_position.distance_to(home) > settings.leash_radius or sight_lost >= settings.sight_loss_seconds
	# Complete an attack return before going home; never replace its anchor.
	if leashed and state in [State.CHASE, State.WINDUP]: _set_state(State.RETURN)
	elif leashed and state in [State.DASH_APPROACH, State.ATTACK, State.DASH_RETURN]:
		_return_after_recovery = true
		if state != State.DASH_RETURN: _begin_attack_return("Leash or sight lost")
	match state:
		State.IDLE:
			if sight and distance <= settings.detection_radius: _set_state(State.CHASE)
		State.CHASE:
			if sight and distance <= settings.attack_start_distance and cooldown <= 0.0: _start_windup()
			elif sight and distance > settings.attack_start_distance: _walk_towards(player.global_position, delta)
		State.WINDUP:
			if elapsed >= active_attack.windup_seconds:
				if active_attack.kind == AttackData.Kind.DASH_MELEE: _begin_dash()
				else: _begin_attack()
		State.DASH_APPROACH: _dash_step(delta, false)
		State.ATTACK:
			if not attack_executed and elapsed >= active_attack.hit_delay_seconds: _execute_attack()
			if state == State.ATTACK and elapsed >= maxf(active_attack.attack_seconds, active_attack.hit_delay_seconds):
				if active_attack.kind == AttackData.Kind.DASH_MELEE: _begin_attack_return("")
				else: _set_state(State.RECOVERY)
		State.DASH_RETURN: _dash_step(delta, true)
		State.RECOVERY:
			if elapsed >= active_attack.recovery_seconds: _set_state(State.RETURN if _return_after_recovery else State.CHASE)
		State.RETURN:
			if global_position.distance_to(home) <= 0.04: _set_state(State.IDLE)
			else: _walk_towards(home, delta)
	_update_telegraph_position()

func _horizontal_direction(at: Vector3) -> Vector3:
	var direction := at - global_position
	direction.y = 0.0
	return direction.normalized() if not direction.is_zero_approx() else facing

func locomotion_held() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.combat): return false
	var combat = player.combat
	return combat.is_busy() and (combat.target == targetable or combat.queued_attack_target == targetable)

func _walk_towards(at: Vector3, delta: float) -> void:
	velocity = Vector3.ZERO
	if locomotion_held(): return # Chase waits but its attack state machine still runs.
	var direction := _horizontal_direction(at)
	var next := global_position + direction * minf(settings.chase_speed * delta, global_position.distance_to(at))
	if not Path.clear(self, next, settings.path, global_position): return
	facing = direction
	velocity = (next - global_position) / maxf(delta, 0.0001)
	move_and_collide(next - global_position)

func _start_windup(in_place: bool = false) -> void:
	if not in_place: last_result = ""
	active_attack = settings.attack.duplicate(true)
	attack_anchor = global_position
	aimed_position = player.global_position
	facing = _horizontal_direction(aimed_position)
	_in_place = in_place or locomotion_held()
	_return_after_recovery = false
	var offset := aimed_position - attack_anchor
	offset.y = 0.0
	# Both original capsules plus 0.15m gap, never a reduced collision shape.
	var radius: float = $CollisionShape3D.shape.radius + player.get_node("CollisionShape3D").shape.radius + 0.15
	var travel := clampf(offset.length() - maxf(active_attack.stop_distance, radius), 0.0, maxf(0.0, active_attack.dash_max_distance))
	dash_destination = attack_anchor + facing * travel if active_attack.kind == AttackData.Kind.DASH_MELEE and not _in_place else attack_anchor
	_set_state(State.WINDUP)

func _begin_dash() -> void:
	if not Path.clear(self, dash_destination, settings.path, global_position):
		_begin_attack_return("Unsafe approach: cancelled")
		return
	_travel_start = global_position
	_set_state(State.DASH_APPROACH)

func _begin_attack() -> void:
	_set_state(State.ATTACK)
	# Keep the original ranged release timing (no extra physical tick).
	if active_attack.hit_delay_seconds <= 0.0: _execute_attack()

func _begin_attack_return(reason: String) -> void:
	if not reason.is_empty(): last_result = reason
	if active_attack.kind != AttackData.Kind.DASH_MELEE:
		_set_state(State.RETURN if _return_after_recovery else State.RECOVERY)
		return
	_travel_start = global_position
	_set_state(State.DASH_RETURN)

func _dash_step(delta: float, returning: bool) -> void:
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
		else: _begin_attack()

func melee_hits() -> bool:
	if not player_alive() or not has_sight(): return false
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
		if melee_hits(): player.get_node("HealthComponent").damage(active_attack.damage, self)
	elif has_sight() and global_position.distance_to(player.global_position) <= settings.attack_start_distance:
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
		facing = _horizontal_direction(player.global_position)
		_refresh_visuals()

func _set_state(next: State) -> void:
	state = next
	attack_executed = false
	elapsed = 0.0
	_travel_elapsed = 0.0
	_held_elapsed = 0.0
	velocity = Vector3.ZERO
	_refresh_visuals()

func _die(_source: Node) -> void:
	_set_state(State.DEAD)
	targetable.set_available(false)
	clear_shots()
	$Body.position.y = 0.26

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
	if not last_result.is_empty(): debug_label.text += "\n" + last_result
	telegraph.visible = state in [State.WINDUP, State.DASH_APPROACH, State.ATTACK]
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
	dash_guide.visible = state in [State.WINDUP, State.DASH_APPROACH] and active_attack.kind == AttackData.Kind.DASH_MELEE
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
