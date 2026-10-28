extends Node
## The dead actor is invalid immediately; a sibling owns the temporary visual.
@onready var actor: CharacterBody3D = get_parent()
var started := false
var effect: Node
var defeat_audio: AudioStreamPlayer
signal defeat_started(visual: Node)
signal defeat_sound_presented(audio: AudioStreamPlayer)

func start(source: Node) -> void:
	if started: return
	started = true
	var settings: Resource = actor.settings.defeat
	if settings == null: return
	_play_sound(settings)
	if settings.mode == 0 or settings.scene == null or actor.settings.visual == null: return
	effect = settings.scene.instantiate()
	if not effect.has_method("configure") or not effect.has_signal("finished"):
		effect.free()
		effect = null
		return
	effect.configure(actor,source,settings)
	effect.finished.connect(_finished)
	effect.tree_exiting.connect(_visual_exiting)
	actor.get_parent().add_child(effect)
	actor.hide()
	defeat_started.emit(effect)

func _finished(_reason: String) -> void:
	# Original owner may have been deleted/reset independently of the visual.
	if is_instance_valid(actor) and not actor.is_queued_for_deletion(): actor.queue_free()

func _visual_exiting() -> void:
	_finished("removed") # Reset/scene teardown must also release the inert owner.

func _play_sound(settings: Resource) -> void:
	if settings.defeat_sound == null: return
	# A sibling of both actor and visual: either can be freed without cutting Cry1.
	defeat_audio = AudioStreamPlayer.new()
	defeat_audio.name = "EnemyDefeatAudio"
	defeat_audio.stream = settings.defeat_sound
	defeat_audio.volume_db = clampf(settings.defeat_volume_db,-60.0,0.0)
	defeat_audio.pitch_scale = clampf(settings.defeat_pitch_scale,0.5,2.0)
	defeat_audio.finished.connect(defeat_audio.queue_free)
	actor.get_parent().add_child(defeat_audio)
	defeat_audio.add_to_group("enemy_defeat_audio")
	defeat_audio.play()
	defeat_sound_presented.emit(defeat_audio)
