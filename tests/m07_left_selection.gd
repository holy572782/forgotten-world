extends "res://tests/m06_target_selection.gd"
## Reuse M06 whole-body/registered-part/occlusion checks with the new left input.
func _click(position: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	super._click(position, button)
