extends "res://scripts/enemies/enemy_weapon_visual.gd"
## Same effect Resource, phase sampler, layout and depth as the player.
const EffectDepth = preload("res://assets/shaders/actor_attachment_effect.gdshader")
@export_enum("WeaponEffect", "SlashEffect") var effect_slot := 0

func _attachment_shader() -> Shader:
	return EffectDepth

func _ready() -> void:
	super._ready()
	process_priority = 11 + effect_slot
	material_override.render_priority = effect_slot
	material_override.set_shader_parameter("layer_depth_bias", 0.000003 + effect_slot*0.000001)

func _process(_delta: float) -> void:
	_sync_from_body()
	if visible:
		var weapon := body.get_node("WeaponSwing")
		weapon.update_depth_occlusion(true)
		material_override.set_shader_parameter("owner_floor_occluded", weapon.material_override.get_shader_parameter("owner_floor_occluded"))

func _sync_from_body() -> void:
	visible = false
	if body.state != body.State.ATTACK or not action_sprite.visible: return
	var visual: Resource = body.current_weapon_visual()
	if visual == null: return
	var config: Resource = visual.weapon_effect if effect_slot == 0 else visual.slash_effect
	if config == null: return
	var next := action_sprite.animation
	if not String(next).begins_with("attack_"): return
	var sampled: Vector2 = config.sample(next, action_sprite.attack_phase(), action_sprite.attack_ratios())
	if sampled.x < 0.0: return
	if sprite_frames != config.frames: sprite_frames = config.frames
	animation = next
	stop()
	set_frame_and_progress(int(sampled.x), sampled.y)
	visible = _apply_frame_layout(config.direction_offset(String(next).get_slice("_", 1)))
