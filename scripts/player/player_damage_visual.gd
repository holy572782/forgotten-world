extends AnimatedSprite3D
## Presentation only: the original action sprite keeps animating while hidden.
## No attack cancellation, hit stun, movement change, mitigation or invulnerability.
const SIDES := ["down", "left", "right", "up"]
@onready var body: CharacterBody3D = get_parent()
@onready var action_sprite: AnimatedSprite3D = body.get_node("AnimatedSprite3D")
@onready var health: HealthComponent = body.get_node("HealthComponent")
var _previous_hp := 0.0
var _remaining := 0.0
var _restore_visible := true

func _ready() -> void:
	visible = false
	_previous_hp = health.current_hp
	health.hp_changed.connect(_on_hp_changed)
	frame_changed.connect(_sync_shadow)
	animation_changed.connect(_sync_shadow)
	var capsule: CapsuleShape3D = body.get_node("CollisionShape3D").shape
	material_override.set_shader_parameter("body_radius", capsule.radius)
	material_override.set_shader_parameter("body_height", capsule.height)
	_sync_shadow()

func _on_hp_changed(current: float, _maximum: float) -> void:
	var previous := _previous_hp
	_previous_hp = current
	if current < previous:
		if _guarding(): clear_damage()
		else: _show_damage()
	elif current > previous: clear_damage() # Trial reset/healing also clears a lingering pose.

func _guarding() -> bool:
	return is_instance_valid(body.combat) and body.combat.state == body.combat.State.Guard

func _damage_animation() -> StringName:
	# Reuse the action sprite's existing camera-relative direction, including combat.
	var side := String(action_sprite.animation).get_slice("_", 1)
	return StringName("damage_" + (side if side in SIDES else "down"))

func _frames_valid() -> bool:
	if sprite_frames == null: return false
	for side in SIDES:
		var name := StringName("damage_" + side)
		if not sprite_frames.has_animation(name) or sprite_frames.get_frame_count(name) != 3 or sprite_frames.get_animation_speed(name) <= 0.0: return false
		for index in range(3):
			var texture := sprite_frames.get_frame_texture(name,index) as AtlasTexture
			if texture == null or texture.atlas == null or not texture.region.has_area(): return false
	return true

func _show_damage() -> void:
	if not _frames_valid(): return
	if _remaining <= 0.0: _restore_visible = action_sprite.visible
	var next := _damage_animation()
	_remaining = 0.0
	for index in range(sprite_frames.get_frame_count(next)):
		_remaining += sprite_frames.get_frame_duration(next,index) / sprite_frames.get_animation_speed(next)
	action_sprite.visible = false
	visible = _restore_visible
	speed_scale = 1.0
	play(next)
	set_frame_and_progress(0,0.0)
	_sync_shadow()

func _process(delta: float) -> void:
	if _remaining <= 0.0: return
	if _guarding():
		clear_damage()
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining <= 0.0 or not _frames_valid():
		clear_damage()
		return
	var next := _damage_animation()
	if animation != next:
		var old_frame := frame
		var progress := frame_progress
		animation = next
		set_frame_and_progress(old_frame,progress)
	_sync_shadow()

func clear_damage() -> void:
	if _remaining > 0.0 or visible:
		if is_instance_valid(action_sprite): action_sprite.visible = _restore_visible
	_remaining = 0.0
	visible = false
	stop()

func _sync_shadow() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(animation): return
	if frame < 0 or frame >= sprite_frames.get_frame_count(animation): return
	var texture := sprite_frames.get_frame_texture(animation,frame) as AtlasTexture
	if texture == null or texture.atlas == null: return
	$Shadow.sprite_frames = sprite_frames
	$Shadow.animation = animation
	$Shadow.frame = frame
	material_override.set_shader_parameter("sprite_sheet",texture.atlas)

func _exit_tree() -> void:
	if is_instance_valid(action_sprite): action_sprite.visible = _restore_visible
