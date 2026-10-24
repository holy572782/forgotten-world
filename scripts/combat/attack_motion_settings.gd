class_name AttackMotionSettings
extends Resource
## Weapon-specific presentation/travel. AnimatedSprite3D remains the only swing clock.
@export_group("Approach travel (metres per second; seconds)")
@export_range(0.1, 40.0) var approach_speed := 12.0
@export_range(0.05, 2.0) var minimum_travel_time := 0.25
@export_range(0.05, 2.0) var maximum_travel_time := 0.4
@export_group("Return travel (metres per second)")
@export_range(0.1, 40.0) var return_speed := 12.0
## Legacy Resource storage only; constant-speed return ignores these limits.
@export_storage var return_minimum_travel_time := 0.1
@export_storage var return_maximum_travel_time := 0.35
@export_group("Waits (seconds)")
@export_range(0.0, 5.0) var approach_attack_delay := 0.0
@export_range(0.0, 5.0) var final_attack_wait := 0.0
@export_group("Shared swing timeline")
## Positive relative durations. A different frame count uses its authored weights.
@export var frame_time_ratios := PackedFloat32Array([1.0, 1.0, 1.0])
## Zero-based index: 1 is the second frame. Hit follows the weighted frame boundary.
@export_range(0, 63) var hit_frame := 1
@export_range(0.0, 100.0) var hit_frame_percent := 0.0

static func bounded(value: float, low: float, high: float, fallback: float) -> float:
	return clampf(value, low, high) if is_finite(value) else fallback

func snapshot() -> AttackMotionSettings:
	var result := duplicate() as AttackMotionSettings
	result.approach_speed = bounded(approach_speed, 0.1, 40.0, 12.0)
	result.return_speed = bounded(return_speed, 0.1, 40.0, 12.0)
	result.minimum_travel_time = bounded(minimum_travel_time, 0.05, 2.0, 0.25)
	result.maximum_travel_time = maxf(result.minimum_travel_time, bounded(maximum_travel_time, 0.05, 2.0, 0.4))
	result.approach_attack_delay = bounded(approach_attack_delay, 0.0, 5.0, 0.0)
	result.final_attack_wait = bounded(final_attack_wait, 0.0, 5.0, 0.0)
	result.hit_frame = clampi(hit_frame, 0, 63)
	result.hit_frame_percent = bounded(hit_frame_percent, 0.0, 100.0, 0.0)
	return result

static func weights(frames: SpriteFrames, name: StringName, ratios := PackedFloat32Array()) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for index in range(frames.get_frame_count(name)):
		var value := float(ratios[index]) if ratios.size() == frames.get_frame_count(name) else frames.get_frame_duration(name, index)
		result.append(bounded(value, 0.001, 1000.0, 1.0) if value > 0.0 else 1.0)
	return result

static func phase_at(values: PackedFloat32Array, index: int, progress: float) -> float:
	var total := 0.0
	var cursor := 0.0
	for i in range(values.size()):
		total += values[i]
		if i < index: cursor += values[i]
		elif i == index: cursor += values[i] * clampf(progress, 0.0, 1.0)
	return clampf(cursor / maxf(total, 0.000001), 0.0, 1.0)

static func sample(values: PackedFloat32Array, phase: float) -> Vector2:
	var total := 0.0
	for value in values: total += value
	var cursor := clampf(phase, 0.0, 1.0) * total
	for index in range(values.size()):
		if cursor < values[index] or index == values.size()-1:
			return Vector2(index, clampf(cursor / values[index], 0.0, 1.0))
		cursor -= values[index]
	return Vector2(-1, 0)

func hit_phase(frames: SpriteFrames, name: StringName) -> float:
	var values := weights(frames, name)
	return phase_at(values, clampi(hit_frame, 0, values.size()-1), hit_frame_percent / 100.0)
