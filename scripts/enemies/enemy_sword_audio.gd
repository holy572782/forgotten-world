extends Node
## Observe the existing enemy swing clock and actual player HP confirmation.
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
var config: Resource
var swing_audio: AudioStreamPlayer
var hit_audio: AudioStreamPlayer
var swing_played := false
var hit_played := false
var blocked := false
@onready var actor: CharacterBody3D = get_parent()
signal swing_presented
signal hit_presented

func _ready() -> void:
	process_physics_priority = 2 # After enemy AI; sample even if rendering skips a fast swing frame.
	swing_audio = AudioStreamPlayer.new()
	swing_audio.name = "SwingAudio"
	add_child(swing_audio)
	hit_audio = AudioStreamPlayer.new()
	hit_audio.name = "HitAudio"
	add_child(hit_audio)
	actor.attack_started.connect(_strike)
	actor.get_node("HealthComponent").depleted.connect(_stop)
	if is_instance_valid(actor.player):
		var health: Node = actor.player.get_node_or_null("HealthComponent")
		if health != null: health.damage_applied.connect(_damaged)
		var combat: Object = actor.player.get("combat")
		if is_instance_valid(combat) and combat.has_signal("guard_succeeded"):
			combat.guard_succeeded.connect(_blocked)

func _strike() -> void:
	config = actor.active_attack.weapon.feedback.snapshot() if actor.active_attack.weapon != null and actor.active_attack.weapon.feedback != null else null
	swing_played = false
	hit_played = false
	blocked = false
	_sample_swing()

func _sample_swing() -> void:
	if config == null or swing_played or actor.state != actor.State.ATTACK: return
	var frames: SpriteFrames = actor.settings.visual.attack_frames if actor.settings.visual != null else null
	if frames == null: return
	var weights := Motion.weights(frames,&"attack_down",actor.active_attack.weapon.motion.frame_time_ratios)
	var at := Motion.phase_at(weights,mini(config.swing_frame,weights.size()-1),config.swing_frame_percent/100.0)
	var duration: float = maxf(0.001,maxf(actor.active_attack.attack_seconds,actor.active_attack.hit_delay_seconds))
	if actor.elapsed/duration+0.000001 < at: return
	swing_played = true
	_play(swing_audio,config.swing_sound,config.swing_volume_db,config.swing_pitch_scale)
	swing_presented.emit()

func _physics_process(_delta: float) -> void:
	_sample_swing()

func _blocked(source: Node) -> void:
	if source == actor: blocked = true # Player CombatFeedback already plays Sword2.

func _damaged(_amount: float, source: Node) -> void:
	if source != actor or config == null or hit_played or blocked or actor.state != actor.State.ATTACK: return
	_sample_swing()
	hit_played = true
	_play(hit_audio,config.hit_sound,config.hit_volume_db,config.hit_pitch_scale)
	hit_presented.emit()

func _play(player: AudioStreamPlayer, stream: AudioStream, volume: float, pitch: float) -> void:
	if stream == null: return
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.play()

func _stop(_source: Node = null) -> void:
	swing_audio.stop()
	hit_audio.stop()
