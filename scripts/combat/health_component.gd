class_name HealthComponent
extends Node
## Owns HP and notifications only; no death animation or respawn behavior.
const Balance = preload("res://scripts/combat/combat_balance.gd")
signal hp_changed(current: float, maximum: float)
signal depleted(source: Node)
@export var balance: Balance = preload("res://resources/combat_balance.tres")
var _hp: float = 0.0
var current_hp: float:
	get: return _hp
var max_hp: float:
	get: return maxf(1.0, balance.max_hp)

func _ready() -> void:
	_hp = clampf(balance.initial_hp, 0.0, max_hp)
	hp_changed.emit(_hp, max_hp)

func damage(amount: float, source: Node = null) -> void:
	if is_finite(amount) and amount > 0.0:
		_set_hp(_hp - amount, source)

func heal(amount: float) -> void:
	if is_finite(amount) and amount > 0.0:
		_set_hp(_hp + amount)

func _set_hp(next: float, source: Node = null) -> void:
	var bounded := clampf(next, 0.0, max_hp)
	if bounded == _hp:
		return
	var was_alive := _hp > 0.0
	_hp = bounded
	hp_changed.emit(_hp, max_hp)
	if was_alive and _hp == 0.0:
		depleted.emit(source)
