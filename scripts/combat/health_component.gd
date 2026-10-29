class_name HealthComponent
extends Node
## Owns HP and notifications only; no death animation or respawn behavior.
const DamageTypes = preload("res://scripts/combat/damage_types.gd")
const Balance = preload("res://scripts/combat/combat_balance.gd")
signal hp_changed(current: float, maximum: float)
signal depleted(source: Node)
signal damage_applied(amount: float, source: Node)
@export var balance: Balance = preload("res://resources/combat_balance.tres")
var _hp: float = 0.0
## Optional receiver-owned mitigation. HP validation/clamping stays here.
var damage_filter: Callable
## Scoped only to the receiver filter; legacy two-argument filters remain valid.
var incoming_damage_kind: DamageTypes.Kind = DamageTypes.Kind.PHYSICAL
var current_hp: float:
	get: return _hp
var max_hp: float:
	get: return maxf(1.0, balance.max_hp)

func _ready() -> void:
	_hp = clampf(balance.initial_hp, 0.0, max_hp)
	hp_changed.emit(_hp, max_hp)

func damage(amount: float, source: Variant = null, kind: DamageTypes.Kind = DamageTypes.Kind.PHYSICAL) -> void:
	if is_finite(amount) and amount > 0.0:
		var source_node: Node = source if is_instance_valid(source) and source is Node else null
		if damage_filter.is_valid():
			var previous_kind := incoming_damage_kind
			incoming_damage_kind = kind
			amount = damage_filter.call(amount, source_node)
			incoming_damage_kind = previous_kind
		if not is_finite(amount) or amount <= 0.0: return
		_set_hp(_hp - amount, source_node)

func heal(amount: float) -> void:
	if is_finite(amount) and amount > 0.0:
		_set_hp(_hp + amount)

func _set_hp(next: float, source: Node = null) -> void:
	var bounded := clampf(next, 0.0, max_hp)
	if bounded == _hp:
		return
	var was_alive := _hp > 0.0
	var lost := _hp - bounded
	_hp = bounded
	if lost > 0.0: damage_applied.emit(lost, source)
	hp_changed.emit(_hp, max_hp)
	if was_alive and _hp == 0.0:
		depleted.emit(source)
