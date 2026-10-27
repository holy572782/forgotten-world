extends Node
## Presentation only: read the AI clock, never extend or restart its windup.
const MIN_SWITCH_SECONDS := 0.08
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
@export var visual_path := NodePath("../AnimatedSprite3D")
@export var hit_feedback_path := NodePath("../HitFeedback")
@onready var actor: CharacterBody3D = get_parent()
@onready var visual := get_node_or_null(visual_path) as GeometryInstance3D
@onready var hit_feedback: Node = get_node_or_null(hit_feedback_path)
var _indicator_enabled := false
var warning_audio: AudioStreamPlayer
signal warning_sound_presented

func _ready() -> void:
	process_priority = 20 # After the existing white flash has advanced/restored.
	_indicator_enabled = actor.settings.attack_range_indicator_enabled
	actor.get_node("HealthComponent").depleted.connect(_depleted)
	warning_audio = AudioStreamPlayer.new()
	warning_audio.name = "WarningAudio"
	add_child(warning_audio)
	actor.attack_warning_started.connect(_play_sound)

static func pulse_on(elapsed: float, duration: float, count: int, interval: float = 0.09) -> bool:
	if not is_finite(elapsed) or not is_finite(duration) or duration <= 0.0 or elapsed < 0.0 or elapsed >= duration: return false
	# Too-short warnings use one steady pulse instead of sub-frame flicker.
	var step := Motion.bounded(interval, MIN_SWITCH_SECONDS, 1.0, 0.09)
	if duration < step * 2.0: return true
	var effective := mini(clampi(count, 1, 8), maxi(1, floori(duration / (step * 2.0))))
	var index := floori((elapsed + 0.0000001) / step)
	return index < effective * 2 and index % 2 == 1 # Normal -> red -> normal.

func _play_sound() -> void:
	var settings: Resource = actor.settings
	if not settings.attack_warning_sound_enabled or settings.attack_warning_sound == null: return
	warning_audio.stream = settings.attack_warning_sound
	warning_audio.volume_db = Motion.bounded(settings.attack_warning_volume_db, -60.0, 0.0, -12.0)
	warning_audio.pitch_scale = Motion.bounded(settings.attack_warning_pitch_scale, 0.5, 2.0, 1.0)
	warning_audio.play()
	warning_sound_presented.emit()

func _depleted(source: Node) -> void:
	_clear(source)
	warning_audio.stop()

func _clear(_source: Node = null) -> void:
	if is_instance_valid(visual) and visual.material_override is ShaderMaterial:
		visual.material_override.set_shader_parameter("attack_warning_strength", 0.0)

func _process(_delta: float) -> void:
	var settings: Resource = actor.settings
	if not settings.attack_warning_sound_enabled and warning_audio.playing: warning_audio.stop()
	if _indicator_enabled != settings.attack_range_indicator_enabled:
		_indicator_enabled = settings.attack_range_indicator_enabled
		actor._refresh_visuals() # Rebuild only on a display toggle; no AI mutation.
	_clear()
	if not settings.attack_warning_flash_enabled or actor.state != actor.State.WINDUP: return
	if actor.active_attack == null or not actor.is_visible_in_tree(): return
	if not is_instance_valid(visual) or not visual.is_visible_in_tree() or not visual.material_override is ShaderMaterial: return
	if is_instance_valid(hit_feedback) and hit_feedback.remaining > 0.0: return
	if not pulse_on(actor.elapsed, actor.active_attack.windup_seconds, settings.attack_warning_flash_count, settings.attack_warning_flash_interval): return
	visual.material_override.set_shader_parameter("attack_warning_color", settings.attack_warning_flash_color)
	visual.material_override.set_shader_parameter("attack_warning_strength", Motion.bounded(settings.attack_warning_flash_strength, 0.0, 1.0, 0.75))

func _exit_tree() -> void:
	_clear()
	if is_instance_valid(warning_audio): warning_audio.stop()
