extends Node
## Receiver-owned flash; never touches HP, AI poses, material_override or markers.
const Defaults = preload("res://resources/combat_feedback.tres")
const FlashShader = preload("res://assets/shaders/enemy_hit_flash.gdshader")
const Settings = preload("res://scripts/combat/combat_feedback_settings.gd")
@export var override_settings: Settings
@export var visual_paths: Array[NodePath] = [NodePath("../Body")]
@export var impact_offset := Vector3(0,0.75,0)
@export_range(0.0, 2.0) var surface_radius := 0.42
var remaining := 0.0
var first_draw := false
var originals: Dictionary = {}
var flashes: Dictionary = {}
@onready var health: HealthComponent = get_parent().get_node("HealthComponent")

func _ready() -> void:
	health.damage_applied.connect(_damaged)
	health.hp_changed.connect(_hp_changed)
	set_process(false)

func _damaged(_amount: float, source: Node) -> void:
	var feedback: Node = source.get_node_or_null("CombatFeedback") if is_instance_valid(source) else null
	var config: Resource = override_settings
	if config == null and feedback != null: config = feedback.current_settings()
	if config == null: config = Defaults
	config = config.snapshot()
	_begin_flash(config)
	if feedback != null: feedback.confirmed_hit(self,config)

func impact_position() -> Vector3:
	var centre: Vector3 = get_parent().to_global(impact_offset)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# A sloped camera ray reaches a capsule farther away than its horizontal
		# radius. Use the actual visible collision surface, not an embedded point.
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,centre,5)
		var contact: Dictionary = get_parent().get_world_3d().direct_space_state.intersect_ray(query)
		if not contact.is_empty():
			if contact.collider == get_parent() or get_parent().is_ancestor_of(contact.collider):
				return contact.position + centre.direction_to(camera.global_position)*0.03
			return centre # A wall/other actor in front must still occlude the burst.
		centre += centre.direction_to(camera.global_position)*surface_radius
	return centre

func _begin_flash(config: Resource) -> void:
	for path in visual_paths:
		var visual := get_node_or_null(path) as GeometryInstance3D
		if visual == null: continue
		if not originals.has(visual):
			originals[visual] = visual.material_overlay
			var flash := ShaderMaterial.new()
			flash.shader = FlashShader
			flashes[visual] = flash
			var overlay: Material = visual.material_overlay
			if overlay == null:
				visual.material_overlay = flash
			else:
				# Preserve an existing overlay and its passes without editing shared data.
				var stack := overlay.duplicate(true) as Material
				var tail := stack
				while tail.next_pass != null: tail = tail.next_pass
				tail.next_pass = flash
				visual.material_overlay = stack
		var flash: ShaderMaterial = flashes[visual]
		flash.set_shader_parameter("flash_color",config.flash_color)
		flash.set_shader_parameter("flash_strength",config.flash_strength)
	remaining = config.flash_duration
	first_draw = true
	set_process(true)
	_update_masks()

func _update_masks() -> void:
	for visual in flashes:
		if not is_instance_valid(visual): continue
		var texture: Texture2D
		if visual is Sprite3D: texture = visual.texture
		elif visual is AnimatedSprite3D and visual.sprite_frames != null:
			texture = visual.sprite_frames.get_frame_texture(visual.animation,visual.frame)
		var flash: ShaderMaterial = flashes[visual]
		flash.set_shader_parameter("use_texture_alpha",texture != null)
		if texture != null: flash.set_shader_parameter("source_texture",texture)

func _hp_changed(current: float, _maximum: float) -> void:
	# Reset clears immediately. A visible corpse may finish its short flash;
	# death signals/AI are never delayed, and hiding/freeing clears the overlay.
	if current >= health.max_hp: clear_flash()

func clear_flash() -> void:
	for visual in originals:
		if is_instance_valid(visual): visual.material_overlay = originals[visual]
	originals.clear()
	flashes.clear()
	remaining = 0.0
	set_process(false)

func _process(delta: float) -> void:
	if not get_parent().is_visible_in_tree():
		clear_flash()
		return
	if first_draw:
		first_draw = false
		_update_masks()
		return
	remaining -= delta
	if remaining <= 0.0: clear_flash()
	else: _update_masks()

func _exit_tree() -> void:
	clear_flash()
