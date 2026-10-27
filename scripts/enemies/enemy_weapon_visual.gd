extends "res://scripts/player/weapon_swing_visual.gd"
## Reuse the player's attachment layout and terrain-aware depth implementation.
## The enemy AI's attack elapsed time is the only attack clock.
func _ready() -> void:
	visible = false
	process_priority = 10
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = _attachment_shader()
	var capsule: CapsuleShape3D = body.get_node("CollisionShape3D").shape
	material.set_shader_parameter("body_radius", capsule.radius)
	material.set_shader_parameter("body_height", capsule.height)
	material_override = material

func _sync_from_body() -> void:
	visible = false
	if body.state != body.State.ATTACK or not action_sprite.visible: return
	var config: Resource = body.settings.visual
	var visual: Resource = body.current_weapon_visual()
	if config == null or visual == null or not visual.is_valid(): return
	if body.active_attack.weapon != null and action_sprite.attack_phase() >= 1.0: return
	var next := action_sprite.animation
	if not String(next).begins_with("attack_") or not visual.attack_frames.has_animation(next): return
	if sprite_frames != visual.attack_frames: sprite_frames = visual.attack_frames
	animation = next
	stop()
	var sampled := MotionSettings.sample(MotionSettings.weights(sprite_frames, next, action_sprite.attack_ratios()), action_sprite.attack_phase())
	set_frame_and_progress(int(sampled.x), sampled.y)
	var side := String(next).get_slice("_", 1)
	var extra: Vector2 = config.weapon_offset(side, frame) if body.active_attack.weapon == null else Vector2.ZERO
	visible = _apply_frame_layout(visual.direction_offset(side) + extra)
