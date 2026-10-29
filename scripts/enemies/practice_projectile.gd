extends CharacterBody3D
## Swept sphere; non-homing. Enemy is the guard-direction source for its lifetime.
const FireVisual = preload("res://scripts/effects/fireball_visual.gd")
const FireHit = preload("res://scripts/effects/fire_hit_presentation.gd")
const DamageTypes = preload("res://scripts/combat/damage_types.gd")
var source: Node3D
var player: CharacterBody3D
var settings: Resource
var direction := Vector3.FORWARD
var age := 0.0
var travelled := 0.0
var consumed := false

func _ready() -> void:
	top_level = true
	collision_layer = 0
	collision_mask = 3 # Terrain + player; never markers or the emitting enemy.
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = settings.projectile_radius
	shape.shape = sphere
	add_child(shape)
	if settings.magic_visual != null:
		var fire := FireVisual.new()
		fire.name = "FireballVisual"
		add_child(fire)
		return
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = sphere.radius
	mesh.height = sphere.radius * 2.0
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.45, 0.8, 1.0)
	visual.material_override = material
	add_child(visual)

func _physics_process(delta: float) -> void:
	if consumed: return
	if not is_instance_valid(source) or source.health.current_hp <= 0.0 or not is_instance_valid(player) or player.get_node("HealthComponent").current_hp <= 0.0:
		_consume(null)
		return
	age += delta
	if age >= settings.projectile_lifetime or travelled >= settings.projectile_range:
		_consume(null)
		return
	# Also detect initial overlaps (e.g. point-blank launch); terrain wins ties.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = $CollisionShape3D.shape
	query.transform = global_transform
	query.collision_mask = 3
	var overlaps := get_world_3d().direct_space_state.intersect_shape(query)
	for overlap in overlaps:
		if overlap.collider != player:
			_consume(null)
			return
	if not overlaps.is_empty():
		_consume(player)
		return
	var motion: Vector3 = direction * minf(settings.projectile_speed * delta, settings.projectile_range - travelled)
	var collision := move_and_collide(motion)
	travelled += motion.length()
	if collision != null: _consume(collision.get_collider())
	elif travelled >= settings.projectile_range: _consume(null)

func _consume(collider: Object) -> void:
	if consumed: return
	consumed = true
	if collider == player and is_instance_valid(source):
		var health: HealthComponent = player.get_node("HealthComponent")
		var before := health.current_hp
		health.damage(settings.damage, source, settings.damage_kind)
		if health.current_hp < before and settings.damage_kind == DamageTypes.Kind.MAGIC and settings.magic_visual != null:
			FireHit.present(player,settings.magic_visual)
			var hurt := player.get_node_or_null("DamageVisual")
			if hurt != null: hurt.show_magic_hit()
	queue_free()
