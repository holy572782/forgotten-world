extends Node3D
## Tiny, opaque camera-facing quads. World depth stays enabled; no glow or texture.
var settings: Resource
var elapsed := 0.0
var particles: Array[MeshInstance3D] = []
var first_draw := true
const COLORS := [Color(0.96,0.94,0.84), Color(0.85,0.76,0.48), Color(0.71,0.53,0.34)]

func configure(value: Resource) -> void:
	settings = value.snapshot()

func _ready() -> void:
	top_level = true
	add_to_group("combat_hit_sparks")
	if settings == null:
		queue_free()
		return
	for index in range(settings.spark_count):
		var particle := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * settings.pixel_size * settings.spark_size_pixels
		particle.mesh = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_color = COLORS[index % COLORS.size()]
		particle.material_override = material
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particle)
		particles.append(particle)
	_place()

func _place() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var phase := clampf(elapsed/settings.spark_duration,0.0,1.0)
	for index in range(particles.size()):
		var angle := TAU * float(index)/maxi(1,particles.size()) + 0.35
		var radius: float = settings.spark_spread * (0.4+0.6*phase)
		var point := Vector2(cos(angle),sin(angle))*radius
		point = point.snapped(Vector2.ONE*settings.pixel_size)
		particles[index].position = camera.global_basis.x*point.x + camera.global_basis.y*point.y

func _process(delta: float) -> void:
	if settings == null: return
	# The birth frame's delta predates this impact; render once before aging it.
	if first_draw:
		first_draw = false
		_place()
		return
	elapsed += delta
	if elapsed >= settings.spark_duration:
		queue_free()
	else:
		_place()
