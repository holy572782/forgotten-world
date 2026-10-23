extends "res://scripts/player/weapon_swing_visual.gd"
## Optional effect slots follow body phase. No gameplay callbacks or timer.
const EffectDepth = preload("res://assets/shaders/actor_attachment_effect.gdshader")
@export_enum("WeaponEffect", "SlashEffect") var effect_slot := 0

func _attachment_shader() -> Shader:
	return EffectDepth

func _ready() -> void:
	super._ready()
	process_priority = 11+effect_slot
	material_override.render_priority = effect_slot
	material_override.set_shader_parameter("layer_depth_bias",0.000003+effect_slot*0.000001)

func _process(_delta: float) -> void:
	_sync_from_body()
	if visible:
		var weapon := body.get_node("WeaponSwing")
		weapon.update_depth_occlusion(true)
		material_override.set_shader_parameter("owner_floor_occluded",weapon.material_override.get_shader_parameter("owner_floor_occluded"))

func _body_phase() -> float:
	var total := 0.0
	var cursor := 0.0
	for index in range(action_sprite.sprite_frames.get_frame_count(action_sprite.animation)):
		var weight := action_sprite.sprite_frames.get_frame_duration(action_sprite.animation,index)
		total += weight
		if index < action_sprite.frame: cursor += weight
		elif index == action_sprite.frame: cursor += weight*action_sprite.frame_progress
	return cursor/maxf(total,0.000001)

func _sync_from_body() -> void:
	visible = false
	var combat: Node = body.combat
	if not is_instance_valid(combat) or combat.state != combat.State.Attack: return
	if not action_sprite._attacking or not action_sprite.visible: return
	var weapon: WeaponData = combat._active_weapon
	if weapon == null or weapon.attack_visual == null: return
	var config: WeaponEffectData = weapon.attack_visual.weapon_effect if effect_slot == 0 else weapon.attack_visual.slash_effect
	if config == null: return
	var next := action_sprite.animation
	if not String(next).begins_with("attack_"): return
	var sampled := config.sample(next,_body_phase())
	if sampled.x < 0.0: return
	if sprite_frames != config.frames: sprite_frames = config.frames
	animation = next
	stop()
	set_frame_and_progress(int(sampled.x),sampled.y)
	visible = _apply_frame_layout(config.direction_offset(String(next).get_slice("_",1)))
