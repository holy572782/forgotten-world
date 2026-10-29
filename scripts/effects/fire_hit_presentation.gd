extends Node3D
## One confirmed fire-projectile impact. Its lifetime is independent of the bolt.
var config: Resource
var emitter: EffekseerEmitter3D
var audio: AudioStreamPlayer
var age := 0.0

static func present(receiver: Node3D, settings: Resource) -> Node3D:
	var effect := new()
	effect.config = settings
	receiver.get_parent().add_child(effect)
	effect.global_position = receiver.global_position + Vector3.UP * 0.7
	effect.start()
	return effect

func start() -> void:
	add_to_group("fire_hit_presentations")
	if config.hit_effect != null:
		emitter = EffekseerEmitter3D.new()
		emitter.name = "FireOne1"
		emitter.effect = config.hit_effect
		emitter.autoplay = false
		emitter.autofree = true
		emitter.scale = Vector3.ONE * maxf(0.001,config.hit_effect_scale)
		add_child(emitter)
		emitter.play()
	if config.hit_sound != null:
		audio = AudioStreamPlayer.new()
		audio.name = "Fire2"
		audio.stream = config.hit_sound
		audio.volume_db = clampf(config.hit_volume_db,-60.0,0.0)
		audio.pitch_scale = clampf(config.hit_pitch_scale,0.5,2.0)
		add_child(audio)
		audio.play()

func _process(delta: float) -> void:
	age += delta
	# Bound malformed/looping replacement visuals; audio completes naturally.
	if is_instance_valid(emitter) and age > 6.0:
		emitter.stop()
		emitter.queue_free()
	if (not is_instance_valid(emitter) or not emitter.is_playing()) and (not is_instance_valid(audio) or not audio.playing):
		queue_free()
