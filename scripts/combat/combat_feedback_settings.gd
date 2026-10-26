extends Resource
## Presentation only. No damage, travel or attack duration settings live here.
@export_group("Sound")
@export var swing_sound: AudioStream
@export_range(-60.0, 0.0) var swing_volume_db := -9.0
@export_range(0.5, 2.0, 0.01) var swing_pitch_scale := 1.0
@export var hit_sound: AudioStream
@export_range(-60.0, 0.0) var hit_volume_db := -12.0
@export_range(0.5, 2.0, 0.01) var hit_pitch_scale := 1.0
## Zero-based body frame and percentage within it; uses the weighted swing timeline.
@export_range(0, 63) var swing_frame := 1
@export_range(0.0, 100.0) var swing_frame_percent := 0.0
@export_group("Enemy flash")
@export_range(0.01, 1.0) var flash_duration := 0.1
@export_range(0.0, 1.0) var flash_strength := 0.55
@export var flash_color := Color(1.0, 0.96, 0.82)
@export_group("Impact sparks")
@export var spark_scene: PackedScene
@export_range(0.01, 1.0) var spark_duration := 0.14
@export_range(0, 12) var spark_count := 5
@export_range(1.0, 4.0) var spark_size_pixels := 2.0
@export_range(0.0, 0.5) var spark_spread := 0.18
@export_range(0.005, 0.1) var pixel_size := 0.0375

func snapshot() -> Resource:
	var copy := duplicate()
	var bounds := {
		"swing_volume_db": Vector3(-60,0,-9), "hit_volume_db": Vector3(-60,0,-12),
		"swing_pitch_scale": Vector3(0.5,2,1), "hit_pitch_scale": Vector3(0.5,2,1),
		"swing_frame_percent": Vector3(0,100,0), "flash_duration": Vector3(0.01,1,0.1),
		"flash_strength": Vector3(0,1,0.55), "spark_duration": Vector3(0.01,1,0.14),
		"spark_size_pixels": Vector3(1,4,2), "spark_spread": Vector3(0,0.5,0.18),
		"pixel_size": Vector3(0.005,0.1,0.0375)}
	for key in bounds:
		var value: float = copy.get(key)
		var bound: Vector3 = bounds[key]
		copy.set(key, clampf(value,bound.x,bound.y) if is_finite(value) else bound.z)
	copy.swing_frame = clampi(swing_frame,0,63)
	copy.spark_count = clampi(spark_count,0,12)
	var color: Color = copy.flash_color
	if not Vector4(color.r,color.g,color.b,color.a).is_finite(): copy.flash_color = Color(1,0.96,0.82)
	return copy
