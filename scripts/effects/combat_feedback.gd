extends Node
## Presentation observer. One weighted body timeline; HP confirmation comes from receivers.
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
var combat: Node
var sprite: AnimatedSprite3D
var swing_audio: AudioStreamPlayer
var hit_audio: AudioStreamPlayer
var config: Resource
var observed_id := -1
var swing_played := false
signal swing_presented(attack_id: int)
signal impact_presented(receiver: Node)

func _ready() -> void:
	combat = get_parent().get_node("TargetDash")
	sprite = get_parent().get_node("AnimatedSprite3D")
	swing_audio = AudioStreamPlayer.new()
	swing_audio.name = "SwingAudio"
	add_child(swing_audio)
	hit_audio = AudioStreamPlayer.new()
	hit_audio.name = "HitAudio"
	hit_audio.max_polyphony = 4
	add_child(hit_audio)
	combat.attack_accepted.connect(_strike)
	sprite.frame_changed.connect(_sample_swing)
	sprite.attack_completed.connect(_sample_swing)
	process_priority = 15

func current_settings() -> Resource:
	return config

func _strike(id: int, _combo: int) -> void:
	observed_id = id
	swing_played = false
	config = combat._active_weapon.feedback.snapshot() if combat._active_weapon.feedback != null else null
	_sample_swing()

func _sample_swing() -> void:
	if config == null or swing_played or observed_id != combat.attack_id: return
	if combat.state != combat.State.Attack or combat._empty_slot: return
	if not String(sprite.animation).begins_with("attack_"): return
	var values := Motion.weights(sprite.sprite_frames,sprite.animation)
	var phase := Motion.phase_at(values,mini(config.swing_frame,values.size()-1),config.swing_frame_percent/100.0)
	if sprite.attack_phase()+0.000001 < phase: return
	swing_played = true
	if config.swing_sound != null:
		swing_audio.stream = config.swing_sound
		swing_audio.volume_db = config.swing_volume_db
		swing_audio.play()
	swing_presented.emit(observed_id)

func _process(_delta: float) -> void:
	_sample_swing()

func confirmed_hit(receiver: Node, settings: Resource) -> void:
	# HP confirmation can share the swing-frame boundary; sample it first.
	_sample_swing()
	if settings.hit_sound != null:
		if hit_audio.stream != settings.hit_sound: hit_audio.stream = settings.hit_sound
		hit_audio.volume_db = settings.hit_volume_db
		hit_audio.play()
	if settings.spark_scene != null and settings.spark_count > 0:
		var burst: Node = settings.spark_scene.instantiate()
		if burst is Node3D:
			if burst.has_method("configure"): burst.configure(settings)
			get_parent().get_parent().add_child(burst)
			burst.global_position = receiver.impact_position()
		else:
			burst.free()
	impact_presented.emit(receiver)
