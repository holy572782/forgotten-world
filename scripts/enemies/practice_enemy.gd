extends CharacterBody3D
const Settings = preload("res://scripts/enemies/enemy_settings.gd")
const Projectile = preload("res://scripts/enemies/practice_projectile.gd")
const Path = preload("res://scripts/combat/dash_path.gd")
const PathSettings = preload("res://resources/target_dash_settings.tres")
enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVERY, RETURN, DEAD }
@export var settings: Settings = preload("res://resources/enemies/melee_practice.tres")
@export var player: CharacterBody3D
@export var show_debug_state := true
@onready var health: HealthComponent = $HealthComponent
@onready var targetable: Node3D = $Targetable
var state := State.IDLE
var home := Vector3.ZERO
var facing := Vector3.FORWARD
var elapsed := 0.0
var cooldown := 0.0
var sight_lost := 0.0
var attack_count := 0
var attack_executed := false
var shots: Array[Node] = []
var telegraph: MeshInstance3D
var debug_label: Label3D

func _ready() -> void:
	process_physics_priority = 1 # Player chooses/fixes its target before enemy locomotion.
	home = global_position
	health.depleted.connect(_die)
	telegraph = MeshInstance3D.new()
	add_child(telegraph)
	debug_label = Label3D.new()
	debug_label.position.y = 2.95
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.font_size = 26
	debug_label.pixel_size = 0.008
	add_child(debug_label)
	_refresh_visuals()

func player_alive() -> bool:
	return is_instance_valid(player) and player.get_node("HealthComponent").current_hp > 0.0

func has_sight() -> bool:
	return player_alive() and Path.sight(self, player.global_position)

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return
	if health.current_hp <= 0.0:
		_die(null)
		return
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	var distance := global_position.distance_to(player.global_position) if player_alive() else INF
	var sight := has_sight()
	sight_lost = 0.0 if sight else sight_lost + delta
	if state != State.RETURN and state != State.IDLE and (not player_alive() or distance > settings.leash_radius or global_position.distance_to(home) > settings.leash_radius or sight_lost >= settings.sight_loss_seconds):
		_set_state(State.RETURN)
	match state:
		State.IDLE:
			if sight and distance <= settings.detection_radius: _set_state(State.CHASE)
		State.CHASE:
			if sight and distance <= settings.attack_start_distance and cooldown <= 0.0:
				facing = _horizontal_direction(player.global_position)
				_set_state(State.WINDUP)
			elif sight and distance > settings.attack_start_distance:
				_walk_towards(player.global_position, delta)
		State.WINDUP:
			if elapsed >= settings.windup_seconds:
				_set_state(State.ATTACK)
				_execute_attack()
		State.ATTACK:
			if elapsed >= settings.attack_seconds: _set_state(State.RECOVERY)
		State.RECOVERY:
			if elapsed >= settings.recovery_seconds: _set_state(State.CHASE)
		State.RETURN:
			if global_position.distance_to(home) <= 0.04: _set_state(State.IDLE)
			else: _walk_towards(home, delta)

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
	if locomotion_held(): return # Only movement pauses; windup, attacks and cooldown continue.
	var direction := _horizontal_direction(at)
	var next := global_position + direction * minf(settings.chase_speed * delta, global_position.distance_to(at))
	if not Path.clear(self, next, PathSettings, global_position): return
	facing = direction
	velocity = (next - global_position) / maxf(delta, 0.0001)
	move_and_collide(next - global_position)

func melee_hits() -> bool:
	if not player_alive() or not has_sight(): return false
	var offset := player.global_position - global_position
	if absf(offset.y) > settings.hit_height_tolerance: return false
	offset.y = 0.0
	return offset.length() <= settings.hit_radius and (offset.is_zero_approx() or facing.dot(offset.normalized()) >= cos(deg_to_rad(settings.hit_half_angle_degrees)))

func _execute_attack() -> void:
	if attack_executed or state != State.ATTACK or health.current_hp <= 0.0 or not player_alive(): return
	attack_executed = true
	attack_count += 1
	cooldown = settings.minimum_attack_interval
	if settings.attack_kind == 0:
		if melee_hits(): player.get_node("HealthComponent").damage(settings.damage, self)
	elif has_sight() and global_position.distance_to(player.global_position) <= settings.attack_start_distance:
		for index in range(shots.size() - 1, -1, -1):
			if not is_instance_valid(shots[index]) or shots[index].is_queued_for_deletion(): shots.remove_at(index)
		if shots.size() >= settings.maximum_projectiles: return
		var shot := Projectile.new()
		shot.settings = settings
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
	velocity = Vector3.ZERO
	_refresh_visuals()

func _die(_source: Node) -> void:
	_set_state(State.DEAD)
	targetable.set_available(false)
	clear_shots()
	$Body.scale = Vector3(1, 0.35, 1)
	$Body.position.y = 0.26

func clear_shots() -> void:
	for shot in shots:
		if is_instance_valid(shot):
			shot.consumed = true
			shot.queue_free()
	shots.clear()

func _refresh_visuals() -> void:
	if not is_instance_valid(telegraph): return
	debug_label.visible = show_debug_state
	debug_label.text = ("MELEE  " if settings.attack_kind == 0 else "RANGED  ") + State.keys()[state]
	telegraph.visible = state in [State.WINDUP, State.ATTACK]
	# Melee sector = exact hit footprint. Ranged charges in a disk, then shows
	# the release direction: its aim is intentionally acquired only at release.
	var mesh := ImmediateMesh.new()
	if telegraph.visible:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var half_angle := deg_to_rad(settings.hit_half_angle_degrees) if settings.attack_kind == 0 else (PI if state == State.WINDUP else 0.12)
		var radius: float = settings.hit_radius if settings.attack_kind == 0 else (0.55 if state == State.WINDUP else 1.4)
		for i in range(24):
			mesh.surface_add_vertex(Vector3(0, 0.035, 0))
			mesh.surface_add_vertex(facing.rotated(Vector3.UP, lerpf(-half_angle, half_angle, float(i) / 24)) * radius + Vector3.UP * 0.035)
			mesh.surface_add_vertex(facing.rotated(Vector3.UP, lerpf(-half_angle, half_angle, float(i + 1) / 24)) * radius + Vector3.UP * 0.035)
		mesh.surface_end()
	telegraph.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1, 0.65, 0.1, 0.35) if state == State.WINDUP else Color(1, 0.2, 0.1, 0.8)
	telegraph.material_override = material
	# Pose distinguishes preparation, release and recovery without relying on color.
	$Body.scale = Vector3(1.12, 0.8, 1.12) if state == State.WINDUP else (Vector3(0.9, 1.12, 0.9) if state == State.ATTACK else Vector3.ONE)
	if state == State.DEAD: $Body.scale.y = 0.35
