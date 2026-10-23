class_name WeaponEffectData
extends Resource
## Visual-only phase window; any positive frame count/durations per direction.
@export var enabled := true
@export var frames: SpriteFrames
@export_range(0.0, 1.0) var start_phase := 0.0
@export_range(0.0, 1.0) var end_phase := 1.0
@export_range(0.1, 5.0) var playback_speed := 1.0
@export var enabled_directions := PackedStringArray(["down", "left", "right", "up"])
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

func sample(animation: StringName, attack_phase: float) -> Vector2:
	if not enabled or frames == null or not frames.has_animation(animation): return Vector2(-1,0)
	if not String(animation).get_slice("_",1) in enabled_directions: return Vector2(-1,0)
	if end_phase <= start_phase or playback_speed <= 0.0 or attack_phase < start_phase or attack_phase >= end_phase: return Vector2(-1,0)
	var phase := (attack_phase-start_phase)/(end_phase-start_phase)*playback_speed
	if phase >= 1.0: return Vector2(-1,0)
	var total := 0.0
	for index in range(frames.get_frame_count(animation)):
		var atlas := frames.get_frame_texture(animation,index) as AtlasTexture
		if atlas == null or atlas.atlas == null or not atlas.region.has_area(): return Vector2(-1,0)
		total += frames.get_frame_duration(animation,index)
	if total <= 0.0: return Vector2(-1,0)
	var cursor := phase*total
	for index in range(frames.get_frame_count(animation)):
		var weight := frames.get_frame_duration(animation,index)
		if cursor < weight: return Vector2(index,cursor/weight)
		cursor -= weight
	return Vector2(-1,0)
