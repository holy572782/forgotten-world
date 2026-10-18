extends Node
## M05 gauge adapter retained through M06. Stock migration belongs to M07.
var attack_start_gauge: float = 0.0

func _ready() -> void:
	get_parent().get_node("AnimatedSprite3D").attack_started.connect(_on_attack_started)

func _on_attack_started() -> void:
	attack_start_gauge = get_parent().get_node("AttackGaugeComponent").consume()
