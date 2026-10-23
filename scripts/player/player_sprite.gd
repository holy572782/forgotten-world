extends AnimatedSprite3D
const MotionSettings = preload("res://scripts/combat/attack_motion_settings.gd")
## Presentation only. Priority: Attack > Jump/Fall > Land > Walk/Idle.
const Controller = preload("res://scripts/player/player_controller.gd")
const ShieldVisual = preload("res://scripts/player/shield_visual_data.gd")
const DIRECTIONS: Array[StringName] = [&"walk_down", &"walk_right", &"walk_up", &"walk_left"]
const SIDES := ["down", "right", "up", "left"]
signal attack_started
signal attack_completed
@export_range(0.001, 0.2) var movement_threshold: float = 0.01
@export var land_duration: float = 0.12 # Provisional presentation timing only.
@export var equipped_shield: ShieldVisual:
	set(value):
		equipped_shield = value
		if is_node_ready():
			_rebuild_guard_frames()
var _base_frames: SpriteFrames
var _base_offset: Vector2
var _base_pixel_size: float
var _shield_ready := false
var _rebuilding_frames := false
var state: StringName = &"Idle"
var _attacking := false
var attack_motion: MotionSettings
var _attack_completed := false
var _requested_swing_duration := 0.0
var combat_pose: StringName = &""
var _attack_facing := Vector3.BACK
var _was_airborne := false
var _land_remaining := 0.0
@onready var body: CharacterBody3D = get_parent()

func _ready() -> void:
	_base_frames = sprite_frames
	_base_offset = offset
	_base_pixel_size = pixel_size
	var capsule: CapsuleShape3D = body.get_node("CollisionShape3D").shape
	material_override.set_shader_parameter("body_radius", capsule.radius)
	material_override.set_shader_parameter("body_height", capsule.height)
	frame_changed.connect(_sync_shadow)
	animation_changed.connect(_sync_shadow)
	animation_finished.connect(_on_animation_finished)
	_rebuild_guard_frames()
	_sync_shadow()

func _rebuild_guard_frames() -> void:
	# Never edit the scene's shared walk/attack/jump Resource or another player.
	_rebuilding_frames = true
	var old_animation := animation
	var old_frame := frame
	var old_progress := frame_progress
	_shield_ready = equipped_shield != null and equipped_shield.is_valid()
	var combined := _base_frames.duplicate() as SpriteFrames
	if _shield_ready:
		for side in SIDES:
			var name := StringName("guard_" + side)
			combined.add_animation(name)
			combined.set_animation_loop(name, false)
			for index in range(equipped_shield.guard_frames.get_frame_count(name)):
				combined.add_frame(name, equipped_shield.guard_frames.get_frame_texture(name, index))
	$Shadow.sprite_frames = combined
	sprite_frames = combined
	animation = old_animation if combined.has_animation(old_animation) else &"walk_down"
	set_frame_and_progress(mini(old_frame, combined.get_frame_count(animation) - 1), old_progress)
	_rebuilding_frames = false
	_set_guard_layout(false)
	_sync_shadow()

func _set_guard_layout(active: bool) -> void:
	var next_offset: Vector2 = equipped_shield.sprite_offset if active else _base_offset
	var next_pixel_size: float = equipped_shield.pixel_size if active else _base_pixel_size
	if offset != next_offset: offset = next_offset
	if not is_equal_approx(pixel_size, next_pixel_size): pixel_size = next_pixel_size
	if $Shadow.offset != next_offset: $Shadow.offset = next_offset
	if not is_equal_approx($Shadow.pixel_size, next_pixel_size): $Shadow.pixel_size = next_pixel_size

func _sync_shadow() -> void:
	# animation_changed can fire with the previous animation's frame index before
	# Godot resets it (e.g. walk frame 3 -> a three-frame jump/attack).
	# Publish neither shadow nor sheet until the frame belongs to the new animation.
	if _rebuilding_frames or sprite_frames == null or not sprite_frames.has_animation(animation):
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
	# Combat owns attack input. Keep the legacy preview only in isolated fixtures.
	if is_instance_valid(body.combat):
		return
	if OS.is_debug_build() and event.is_action_pressed("attack") and not event.is_echo():
		request_attack_preview()

func request_attack_preview(duration: float = 0.0, motion: MotionSettings = null) -> bool:
	if _attacking:
		return false
	attack_motion = motion
	_attack_completed = false
	_requested_swing_duration = duration
	# Private frame durations, rebuilt from the authored source for each weapon.
	for side in SIDES:
		var name := StringName("attack_" + side)
		var values := MotionSettings.weights(_base_frames, name, motion.frame_time_ratios if motion != null else PackedFloat32Array())
		for index in range(values.size()):
			sprite_frames.set_frame(name, index, _base_frames.get_frame_texture(name, index), values[index])
	_set_guard_layout(false)
	_attacking = true
	_attack_facing = body.facing_world
	state = &"Attack"
	var sector := Controller.direction_sector(_attack_facing, body._movement_basis(), 4)
	var attack_animation := StringName("attack_" + SIDES[sector])
	_set_attack_speed(attack_animation)
	play(attack_animation)
	set_frame_and_progress(0, 0.0)
	_sync_shadow()
	attack_started.emit()
	return true

func _set_attack_speed(name: StringName) -> void:
	var original_duration := 0.0
	for index in range(sprite_frames.get_frame_count(name)):
		original_duration += sprite_frames.get_frame_duration(name, index) / sprite_frames.get_animation_speed(name)
	speed_scale = original_duration / _requested_swing_duration if _requested_swing_duration > 0.0 else 1.0

func attack_phase() -> float:
	if _attack_completed: return 1.0
	if not _attacking or not String(animation).begins_with("attack_"): return 0.0
	return MotionSettings.phase_at(MotionSettings.weights(sprite_frames, animation), frame, frame_progress)

func attack_ratios() -> PackedFloat32Array:
	return attack_motion.frame_time_ratios if attack_motion != null else PackedFloat32Array()

func _on_animation_finished() -> void:
	if _attacking and String(animation).begins_with("attack_"):
		_attack_completed = true
		_attacking = false
		speed_scale = 1.0
		attack_completed.emit()
		_process(0.0)

func _process(delta: float) -> void:
	var show_shield := combat_pose == &"Guard" and not _attacking and _shield_ready
	_set_guard_layout(show_shield)
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
		if combat_pose == &"Stance" or combat_pose == &"Guard":
			if show_shield:
				_select_animation(StringName("guard_" + SIDES[sector]))
				stop()
				frame = equipped_shield.held_frame
				_sync_shadow()
				return
			_select_animation(DIRECTIONS[sector])
			stop()
			frame = 1 if combat_pose == &"Guard" else 0
			_sync_shadow()
			return
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
	if same_family and _attacking:
		var phase := attack_phase()
		animation = next_animation
		_set_attack_speed(next_animation)
		var sampled := MotionSettings.sample(MotionSettings.weights(sprite_frames, next_animation), phase)
		set_frame_and_progress(int(sampled.x), sampled.y)
		_sync_shadow()
		return
	var phase_frame := frame if same_family else 0
	var phase_progress := frame_progress if same_family else 0.0
	animation = next_animation
	set_frame_and_progress(phase_frame, phase_progress)
	_sync_shadow()
