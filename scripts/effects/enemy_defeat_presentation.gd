extends Node
## The dead actor is invalid immediately; a sibling owns the temporary visual.
@onready var actor: CharacterBody3D = get_parent()
var started := false
var effect: Node
signal defeat_started(visual: Node)

func start(source: Node) -> void:
	if started: return
	started = true
	var settings: Resource = actor.settings.defeat
	if settings == null or settings.mode == 0 or settings.scene == null or actor.settings.visual == null: return
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
