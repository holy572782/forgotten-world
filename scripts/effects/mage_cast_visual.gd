extends Node3D
## Presentation only. Existing AI signals/clock own the warning and release.
const CircleShader = preload("res://assets/shaders/mage_circle.gdshader")
const Ground = preload("res://scripts/combat/dash_path.gd")
var mesh: MeshInstance3D
var material: ShaderMaterial
var emitter: EffekseerEmitter3D
var remaining := 0.0
var releasing := false
@onready var actor: CharacterBody3D = get_parent()

func _ready() -> void:
	mesh = MeshInstance3D.new()
	mesh.mesh = PlaneMesh.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = CircleShader
	mesh.material_override = material
	mesh.visible = false
	add_child(mesh)
	emitter = EffekseerEmitter3D.new()
	emitter.name = "EffekseerCircle"
	emitter.autoplay = false
	emitter.autofree = false
	# Native sprites are fixed in XY; put the effect on the world XZ floor.
	emitter.rotation.x = -PI * 0.5
	emitter.visible = false
	add_child(emitter)
	actor.attack_warning_started.connect(_begin)
	actor.attack_started.connect(_release)
	actor.health.depleted.connect(func(_source: Node): clear())

func _begin() -> void:
	clear()
	releasing = false
	remaining = 0.0
	_update(0.0)

func _release() -> void:
	if actor.active_attack.magic_visual == null: return
	releasing = true
	remaining = actor.active_attack.magic_visual.release_fade_seconds
	if remaining <= 0.0: clear()

func clear() -> void:
	releasing = false
	remaining = 0.0
	if is_instance_valid(mesh): mesh.visible = false
	if is_instance_valid(emitter):
		emitter.stop()
		emitter.visible = false

func is_presenting() -> bool:
	return is_visible_in_tree() and (mesh.visible or (emitter.visible and emitter.is_playing()))

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	var config: Resource = actor.active_attack.magic_visual
	if config == null or not config.circle_enabled or actor.state == actor.State.DEAD or not actor.is_visible_in_tree():
		clear()
		return
	var strength := 1.0
	if actor.state != actor.State.WINDUP:
		if not releasing or actor.state not in [actor.State.ATTACK,actor.State.RECOVERY]:
			clear()
			return
		remaining = maxf(0.0, remaining-delta)
		if remaining <= 0.0:
			clear()
			return
		strength = remaining / maxf(0.001,config.release_fade_seconds)
	var floor_point := Ground.ground_below(actor,actor.global_position,2.0)
	if not floor_point.is_finite():
		clear()
		return
	global_position = floor_point + Vector3.UP*config.ground_offset
	rotation.y += config.circle_rotation_speed * delta
	if config.circle_effect != null:
		mesh.visible = false
		if emitter.effect != config.circle_effect:
			emitter.stop()
			emitter.effect = config.circle_effect
		emitter.scale = Vector3.ONE * config.circle_diameter
		var progress := clampf(actor.elapsed/maxf(0.001,actor.active_attack.windup_seconds),0.0,1.0) if actor.state == actor.State.WINDUP else 1.0
		var tint: Color = config.circle_color
		tint.a *= strength * lerpf(0.65,1.0,progress)
		emitter.color = tint
		if not emitter.is_playing(): emitter.play()
		emitter.visible = true
		return
	emitter.stop()
	emitter.visible = false
	mesh.mesh.size = Vector2.ONE * config.circle_diameter
	material.set_shader_parameter("circle_color",config.circle_color)
	material.set_shader_parameter("intensity",strength)
	material.set_shader_parameter("warning_progress",clampf(actor.elapsed/maxf(0.001,actor.active_attack.windup_seconds),0.0,1.0) if actor.state == actor.State.WINDUP else 1.0)
	mesh.visible = true
