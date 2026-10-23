class_name WeaponAttackVisualData
extends Resource
## Display only. Offsets are pixels (+x right, +y up), relative to the body centre.
const SIDES := ["down", "left", "right", "up"]
@export var attack_frames: SpriteFrames
@export var weapon_effect: WeaponEffectData
@export var slash_effect: WeaponEffectData
@export var offset_down := Vector2.ZERO
@export var offset_left := Vector2.ZERO
@export var offset_right := Vector2.ZERO
@export var offset_up := Vector2.ZERO

func direction_offset(side: String) -> Vector2:
	match side:
		"down": return offset_down
		"left": return offset_left
		"right": return offset_right
		"up": return offset_up
	return Vector2.ZERO

func is_valid() -> bool:
	if attack_frames == null: return false
	for side in SIDES:
		var name := StringName("attack_"+side)
		if not attack_frames.has_animation(name) or attack_frames.get_frame_count(name) < 1: return false
		for index in range(attack_frames.get_frame_count(name)):
			var frame := attack_frames.get_frame_texture(name,index) as AtlasTexture
			if frame == null or frame.atlas == null or not frame.region.has_area(): return false
	return true
