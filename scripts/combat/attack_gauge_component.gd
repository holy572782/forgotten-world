class_name AttackGaugeComponent
extends Node
## Time-based recovery. Does not decide whether an attack may begin.
const Balance = preload("res://scripts/combat/combat_balance.gd")
signal gauge_changed(current: float, maximum: float)
@export var balance: Balance = preload("res://resources/combat_balance.tres")
var _value: float = 0.0
var value: float:
	get: return _value
var maximum: float:
	get: return clampf(balance.gauge_max, 1.0, 100.0)
var recovery_rate: float:
	get: return maximum / maxf(0.01, balance.gauge_recovery_seconds)

func _ready() -> void:
	_value = clampf(balance.initial_gauge, 0.0, maximum)
	gauge_changed.emit(_value, maximum)

func _process(delta: float) -> void:
	if is_finite(delta) and delta > 0.0:
		_set_value(_value + recovery_rate * delta)

## Return the attack-start snapshot for the future M06 damage calculation.
func consume() -> float:
	var snapshot := _value
	_set_value(0.0)
	return snapshot

func _set_value(next: float) -> void:
	var bounded := clampf(next, 0.0, maximum)
	if bounded == _value:
		return
	_value = bounded
	gauge_changed.emit(_value, maximum)
