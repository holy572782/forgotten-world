extends AnimatedSprite3D
## Presentation only. Priority: Attack > Jump/Fall > Land > Walk/Idle.
const Controller = preload("res://scripts/player/player_controller.gd")
const DIRECTIONS: Array[StringName] = [&"walk_down", &"walk_right", &"walk_up", &"walk_left"]
const SIDES := ["down", "right", "up", "left"]
signal attack_started
signal attack_completed
@export_range(0.001, 0.2) var movement_threshold: float = 0.01
@export var land_duration: float = 0.12 # Provisional presentation timing only.
var state: StringName = &"Idle"
var _attacking := false
var combat_pose: StringName = &""
var _attack_facing := Vector3.BACK
var _was_airborne := false
var _land_remaining := 0.0
@onready var body: CharacterBody3D = get_parent()

func _ready() -> void:
	var capsule: CapsuleShape3D = body.get_node("CollisionShape3D").shape
	material_override.set_shader_parameter("body_radius", capsule.radius)
	material_override.set_shader_parameter("body_height", capsule.height)
	frame_changed.connect(_sync_shadow)
	animation_changed.connect(_sync_shadow)
	animation_finished.connect(_on_animation_finished)
	_sync_shadow()

func _sync_shadow() -> void:
	# animation_changed can fire with the previous animation's frame index before
	# Godot resets it (e.g. walk frame 3 -> a three-frame jump/attack).
	# Publish neither shadow nor sheet until the frame belongs to the new animation.
	if sprite_frames == null or not sprite_frames.has_animation(animation):
		return
	if frame < 0 or frame >= sprite_frames.get_frame_count(animation):
		return
	var texture := sprite_frames.get_frame_texture(animation, frame) as AtlasTexture
	if texture == null or texture.atlas == null:
		return
	$Shadow.animation = animation
	$Shadow.frame = frame
	material_override.set_shader_parameter("sprite_sheet", texture.atlas)

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(body.combat) and body.combat.is_busy():
		return
	if OS.is_debug_build() and event.is_action_pressed("attack") and not event.is_echo():
		request_attack_preview()

func request_attack_preview() -> bool:
	if _attacking:
		return false
	_attacking = true
	_attack_facing = body.facing_world
	state = &"Attack"
	var sector := Controller.direction_sector(_attack_facing, body._movement_basis(), 4)
	play(StringName("attack_" + SIDES[sector]))
	set_frame_and_progress(0, 0.0)
	_sync_shadow()
	attack_started.emit()
	return true

func _on_animation_finished() -> void:
	if _attacking and String(animation).begins_with("attack_"):
		_attacking = false
		attack_completed.emit()
		_process(0.0)

func _process(delta: float) -> void:
	var airborne := not body.is_on_floor() or body.velocity.y > 0.0
	if _was_airborne and not airborne:
		_land_remaining = land_duration
	_was_airborne = airborne
	_land_remaining = maxf(0.0, _land_remaining - delta)
	var facing: Vector3 = _attack_facing if _attacking else body.facing_world
	var sector := Controller.direction_sector(facing, body._movement_basis(), 4)
	if not combat_pose.is_empty() and not _attacking:
		state = combat_pose
		if combat_pose == &"Attack":
			return # Hold the final attack pose until the physics state starts Return.
		_select_animation(StringName("jump_" + SIDES[sector]))
		stop()
		frame = 0 if combat_pose == &"Approach" else 1
		_sync_shadow()
		return
	if _attacking:
		_select_animation(StringName("attack_" + SIDES[sector]))
		return
	if airborne or _land_remaining > 0.0:
		state = &"Jump" if airborne and body.velocity.y > 0.0 else (&"Fall" if airborne else &"Land")
		_select_animation(StringName("jump_" + SIDES[sector]))
		stop()
		frame = 0 if state == &"Jump" else (1 if state == &"Fall" else 2)
		return
	var actual := Vector2(body.get_real_velocity().x, body.get_real_velocity().z)
	var requested := Vector2(body.velocity.x, body.velocity.z)
	_select_animation(DIRECTIONS[sector])
	if actual.length() > movement_threshold and requested.length() > movement_threshold:
		state = &"Walk"
		play()
	else:
		state = &"Idle"
		stop()
		frame = 0

func _select_animation(next_animation: StringName) -> void:
	if animation == next_animation:
		return
	var same_family := String(animation).get_slice("_", 0) == String(next_animation).get_slice("_", 0)
	var phase_frame := frame if same_family else 0
	var phase_progress := frame_progress if same_family else 0.0
	animation = next_animation
	set_frame_and_progress(phase_frame, phase_progress)
	_sync_shadow()
