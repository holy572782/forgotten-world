extends Node3D
## Place this at an attack point, independently of the enemy's visual centre.
@export var health_path: NodePath = NodePath("../HealthComponent")
## Explicit selection volumes: whole body for small enemies, individual parts for bosses.
## Paths are relative to this attack point. Assign each collider to one Targetable only.
@export var click_collider_paths: Array[NodePath] = []
@onready var health: HealthComponent = get_node(health_path)
@onready var marker: Area3D = $Marker

func _ready() -> void:
	add_to_group("combat_targets")
	set_available(false)
	health.hp_changed.connect(_update_label)
	_update_label(health.current_hp, health.max_hp)

func alive() -> bool:
	return is_instance_valid(health) and health.current_hp > 0.0 and is_visible_in_tree()

func accepts_click(collider: CollisionObject3D) -> bool:
	if collider == marker:
		return true
	for path in click_collider_paths:
		if not path.is_empty() and get_node_or_null(path) == collider:
			return true
	return false

func set_available(available: bool) -> void:
	marker.visible = available
	marker.collision_layer = 8 if available else 0

func _update_label(current: float, maximum: float) -> void:
	$HealthLabel.text = "TRAINING  %d / %d" % [ceili(current), ceili(maximum)]
