class_name AttackStockComponent
extends Node
const Settings = preload("res://scripts/combat/attack_stock_settings.gd")
signal stock_changed(current: int, maximum: int)
@export var settings: Settings = preload("res://resources/attack_stock_settings.tres")
var _current: int = 0
var current: int:
	get: return _current
var maximum: int:
	get: return maxi(1, settings.maximum)
var recovery_progress: float:
	get: return _elapsed / maxf(0.01, settings.recovery_seconds)
var _elapsed := 0.0
var _recovery_allowed := true

func _ready() -> void:
	_current = clampi(settings.initial, 0, maximum)
	stock_changed.emit(current, maximum)

func can_spend(cost: int = 1) -> bool:
	return cost > 0 and current >= cost

func spend(cost: int = 1) -> bool:
	if not can_spend(cost): return false
	_current -= cost
	_elapsed = 0.0
	stock_changed.emit(current, maximum)
	return true

## Other states (including future guard/step) may inhibit recovery.
## Prototype rule: entering an inhibited state discards the partial interval.
func set_recovery_allowed(allowed: bool) -> void:
	_recovery_allowed = allowed
	if not allowed: _elapsed = 0.0

## Explicitly advanced by the owning controller, never a parallel process timer.
func advance(delta: float) -> void:
	if not _recovery_allowed or not is_finite(delta) or delta <= 0.0: return
	if current >= maximum:
		_elapsed = 0.0
		return
	_elapsed += delta
	var interval := maxf(0.01, settings.recovery_seconds)
	while _elapsed + 0.000001 >= interval and current < maximum:
		_elapsed = maxf(0.0, _elapsed - interval)
		_current += 1
		stock_changed.emit(current, maximum)
	if current == maximum: _elapsed = 0.0
