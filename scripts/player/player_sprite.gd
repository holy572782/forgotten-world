extends AnimatedSprite3D
## Presentation only. Original 48px frames; locomotion remains on the parent.
const Controller = preload("res://scripts/player/player_controller.gd")
const DIRECTIONS: Array[StringName] = [&"walk_down", &"walk_right", &"walk_up", &"walk_left"]
@export_range(0.001, 0.2) var movement_threshold: float = 0.01
@onready var body: CharacterBody3D = get_parent()

func _process(_delta: float) -> void:
	# Re-evaluate even while idle so orbiting shows the correct side of the body.
	var sector := Controller.direction_sector(body.facing_world, body._movement_basis(), 4)
	var next_animation := DIRECTIONS[sector]
	if animation != next_animation:
		var phase_frame := frame
		var phase_progress := frame_progress
		animation = next_animation
		set_frame_and_progress(phase_frame, phase_progress)
	var actual := Vector2(body.get_real_velocity().x, body.get_real_velocity().z)
	var requested := Vector2(body.velocity.x, body.velocity.z)
	if actual.length() > movement_threshold and requested.length() > movement_threshold:
		play()
	else:
		stop()
		frame = 1
