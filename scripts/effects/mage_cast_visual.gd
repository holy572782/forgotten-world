extends Node3D
## Presentation only. Existing AI signals/clock own the warning and release.
const CircleShader = preload("res://assets/shaders/mage_circle.gdshader")
const Ground = preload("res://scripts/enemies/enemy_walk.gd")
var mesh: MeshInstance3D
var material: ShaderMaterial
var emitter: EffekseerEmitter3D
var native_view: SubViewport
var floor_projection: MeshInstance3D
var remaining := 0.0
var releasing := false
var floor_angle := 0.0
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
	# Render the native circle in its own transparent view, then place that
	# image on the actual floor. Native particle sorting cannot paint the body.
	native_view = SubViewport.new()
	native_view.name = "CircleViewport"
	native_view.size = Vector2i(256,256)
	native_view.transparent_bg = true
	native_view.own_world_3d = true
	native_view.gui_disable_input = true
	native_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(native_view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.05
	camera.position = Vector3(0,3,0)
	camera.rotation.x = -PI*0.5
	camera.current = true
	native_view.add_child(camera)
	floor_projection = MeshInstance3D.new()
	floor_projection.name = "FloorProjection"
	floor_projection.mesh = PlaneMesh.new()
	floor_projection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var projection_material := StandardMaterial3D.new()
	projection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	projection_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	projection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	projection_material.render_priority = -10
	projection_material.albedo_texture = native_view.get_texture()
	floor_projection.material_override = projection_material
	floor_projection.visible = false
	add_child(floor_projection)
	emitter = EffekseerEmitter3D.new()
	emitter.name = "EffekseerCircle"
	emitter.autoplay = false
	emitter.autofree = false
	emitter.base_render_priority = -10
	# Native sprites are fixed in XY; put the effect on the world XZ floor.
	emitter.rotation.x = -PI * 0.5
	emitter.visible = false
	native_view.add_child(emitter)
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
	if is_instance_valid(floor_projection): floor_projection.visible = false
	if is_instance_valid(native_view): native_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(emitter):
		emitter.stop()
		emitter.visible = false

func is_presenting() -> bool:
	return is_visible_in_tree() and (mesh.visible or (floor_projection.visible and emitter.visible and emitter.is_playing()))

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
	var floor_hit := Ground.floor_hit(actor,actor.global_position,0.25,2.0,actor.settings.walk.max_slope_degrees)
	if floor_hit.is_empty():
		clear()
		return
	global_position = floor_hit.position + floor_hit.normal*config.ground_offset
	floor_angle += config.circle_rotation_speed * delta
	global_basis = Basis(Quaternion(Vector3.UP,floor_hit.normal)) * Basis(Vector3.UP,floor_angle)
	if config.circle_effect != null:
		mesh.visible = false
		emitter.rotation.x = 0.0 if config.circle_effect_is_floor else -PI * 0.5
		if emitter.effect != config.circle_effect:
			emitter.stop()
			emitter.effect = config.circle_effect
		emitter.scale = Vector3.ONE
		floor_projection.mesh.size = Vector2.ONE * config.circle_diameter
		floor_projection.visible = true
		native_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var progress := clampf(actor.elapsed/maxf(0.001,actor.active_attack.windup_seconds),0.0,1.0) if actor.state == actor.State.WINDUP else 1.0
		var tint: Color = config.circle_color
		tint.a *= strength * lerpf(0.65,1.0,progress)
		emitter.color = tint
		if not emitter.is_playing(): emitter.play()
		emitter.visible = true
		return
	emitter.stop()
	emitter.visible = false
	floor_projection.visible = false
	native_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mesh.mesh.size = Vector2.ONE * config.circle_diameter
	material.set_shader_parameter("circle_color",config.circle_color)
	material.set_shader_parameter("intensity",strength)
	material.set_shader_parameter("warning_progress",clampf(actor.elapsed/maxf(0.001,actor.active_attack.windup_seconds),0.0,1.0) if actor.state == actor.State.WINDUP else 1.0)
	mesh.visible = true
