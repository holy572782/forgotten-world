extends Node
## M05-only adapter. M06 can replace this with formal attack acceptance.
var attack_start_gauge: float = 0.0

func _ready() -> void:
	get_parent().get_node("AnimatedSprite3D").attack_started.connect(_on_attack_started)

func _on_attack_started() -> void:
	attack_start_gauge = get_parent().get_node("AttackGaugeComponent").consume()
