extends Node3D
## Place this at an attack point, independently of the enemy's visual centre.
@export var health_path: NodePath = NodePath("../HealthComponent")
@onready var health: HealthComponent = get_node(health_path)
@onready var marker: Area3D = $Marker

func _ready() -> void:
	add_to_group("combat_targets")
	set_available(false)
	health.hp_changed.connect(_update_label)
	_update_label(health.current_hp, health.max_hp)

func alive() -> bool:
	return is_instance_valid(health) and health.current_hp > 0.0 and is_visible_in_tree()

func set_available(available: bool) -> void:
	marker.visible = available
	marker.collision_layer = 8 if available else 0

func _update_label(current: float, maximum: float) -> void:
	$HealthLabel.text = "TRAINING  %d / %d" % [ceili(current), ceili(maximum)]
