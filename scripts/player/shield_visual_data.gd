class_name ShieldVisualData
extends Resource
## Presentation data only; no equipment UI or defensive stats.
@export var display_name: String = ""
@export var guard_frames: SpriteFrames
@export var held_frame: int = 1
@export var sprite_offset := Vector2(0, 23)
@export var pixel_size: float = 0.0375

func is_valid() -> bool:
	if guard_frames == null or held_frame < 0 or pixel_size <= 0.0:
		return false
	for side in ["down", "left", "right", "up"]:
		var animation := StringName("guard_" + side)
		if not guard_frames.has_animation(animation) or guard_frames.get_frame_count(animation) <= held_frame:
			return false
		for index in range(guard_frames.get_frame_count(animation)):
			var texture := guard_frames.get_frame_texture(animation, index) as AtlasTexture
			if texture == null or texture.atlas == null or not texture.region.has_area():
				return false
			if not Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region):
				return false
	return true
