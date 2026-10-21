extends Node3D
## Place this at an attack point, independently of the enemy's visual centre.
@export var health_path: NodePath = NodePath("../HealthComponent")
## Explicit selection volumes: whole body for small enemies, individual parts for bosses.
## Paths are relative to this attack point. Assign each collider to one Targetable only.
@export var click_collider_paths: Array[NodePath] = []
@onready var health: HealthComponent = get_node(health_path)
@onready var marker: Area3D = $Marker
var selected := false
var _filled_mesh: ImmediateMesh
var _hollow_mesh: ImmediateMesh

func _ready() -> void:
	add_to_group("combat_targets")
	_filled_mesh = _make_marker(0.0)
	_hollow_mesh = _make_marker(0.17)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.72, 0.12)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	$Marker/Mesh.material_override = material
	set_available(false)
	health.hp_changed.connect(_update_label)
	_update_label(health.current_hp, health.max_hp)

func alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(health) and health.current_hp > 0.0 and is_visible_in_tree()

func accepts_click(collider: CollisionObject3D) -> bool:
	if collider == marker:
		return true
	for path in click_collider_paths:
		if not path.is_empty() and get_node_or_null(path) == collider:
			return true
	return false

func set_available(available: bool, is_selected: bool = false) -> void:
	selected = available and is_selected
	$Marker/Mesh.mesh = _filled_mesh if selected else _hollow_mesh
	marker.visible = available
	marker.collision_layer = 8 if available else 0

func _make_marker(inner_radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(32):
		var a := Vector3(cos(TAU * index / 32.0), sin(TAU * index / 32.0), 0.0)
		var b := Vector3(cos(TAU * (index + 1) / 32.0), sin(TAU * (index + 1) / 32.0), 0.0)
		for vertex in [a * 0.25, b * 0.25, a * inner_radius, b * 0.25, b * inner_radius, a * inner_radius]:
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh

func _update_label(current: float, maximum: float) -> void:
	$HealthLabel.text = "TRAINING  %d / %d" % [ceili(current), ceili(maximum)]
