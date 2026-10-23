class_name WeaponEffectData
extends Resource
## Visual-only phase window; any positive frame count/durations per direction.
@export var enabled := true
@export var frames: SpriteFrames
## Retain the existing serialized representation; Inspector aliases have no storage.
@export_storage var start_phase := 0.0
@export_storage var end_phase := 1.0
@export_storage var playback_speed := 1.0
@export_range(0.0, 100.0) var start_percent: float:
	get: return start_phase * 100.0
	set(value):
		var next := AttackMotionSettings.bounded(value, 0.0, 100.0, 0.0) / 100.0
		var span := duration_percent / 100.0
		playback_speed = 1.0
		start_phase = next
		end_phase = next + span
## Percentage of one swing, regardless of frame count. Clipped at attack completion.
@export_range(0.1, 100.0) var duration_percent: float:
	get: return (end_phase-start_phase) / maxf(playback_speed, 1.0) * 100.0
	set(value):
		playback_speed = 1.0
		end_phase = start_phase + AttackMotionSettings.bounded(value, 0.1, 100.0, 100.0) / 100.0
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

func _validate_property(property: Dictionary) -> void:
	if property.name in ["start_percent", "duration_percent"]:
		property.usage = property.usage & ~PROPERTY_USAGE_STORAGE

func sample(animation: StringName, attack_phase: float, ratios := PackedFloat32Array()) -> Vector2:
	if not enabled or frames == null or not frames.has_animation(animation): return Vector2(-1,0)
	if not is_finite(start_phase) or not is_finite(end_phase) or not is_finite(playback_speed) or attack_phase >= 1.0: return Vector2(-1,0)
	if not String(animation).get_slice("_",1) in enabled_directions: return Vector2(-1,0)
	if end_phase <= start_phase or playback_speed <= 0.0 or attack_phase < start_phase or attack_phase >= end_phase: return Vector2(-1,0)
	var phase := (attack_phase-start_phase)/(end_phase-start_phase)*playback_speed
	if phase >= 1.0: return Vector2(-1,0)
	for index in range(frames.get_frame_count(animation)):
		var atlas := frames.get_frame_texture(animation,index) as AtlasTexture
		if atlas == null or atlas.atlas == null or not atlas.region.has_area(): return Vector2(-1,0)
	return AttackMotionSettings.sample(AttackMotionSettings.weights(frames, animation, ratios), phase)
