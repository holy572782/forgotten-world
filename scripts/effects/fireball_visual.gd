extends Node3D
## Low-resolution procedural billboards. No physics, light, plugin or image file.
const FireShader = preload("res://assets/shaders/fireball.gdshader")
var core: MeshInstance3D
var trail: Array[MeshInstance3D] = []
@onready var shot: CharacterBody3D = get_parent()

func _quad(diameter: float, opacity: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE*diameter
	visual.mesh = quad
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = FireShader
	material.set_shader_parameter("opacity",opacity)
	material.set_shader_parameter("pixel_grid",shot.settings.magic_visual.pixel_grid)
	visual.material_override = material
	add_child(visual)
	return visual

func _ready() -> void:
	var config: Resource = shot.settings.magic_visual
	core = _quad(config.fireball_diameter,1.0)
	for index in range(clampi(config.trail_count,0,10)):
		trail.append(_quad(config.fireball_diameter*lerpf(0.3,0.07,float(index)/maxf(1,config.trail_count)),0.85))

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var config: Resource = shot.settings.magic_visual
	core.global_basis = camera.global_basis.orthonormalized()
	core.material_override.set_shader_parameter("clock",shot.age)
	for index in range(trail.size()):
		var phase := fposmod(shot.age*2.8+float(index)/maxi(1,trail.size()),1.0)
		var offset: Vector3 = -shot.direction * config.trail_length*(0.35+phase)
		offset += camera.global_basis.x*sin(float(index)*2.4+shot.age*7.0)*0.12*phase
		offset += camera.global_basis.y*0.15*phase
		trail[index].global_position = shot.global_position+offset
		trail[index].global_basis = core.global_basis
		trail[index].material_override.set_shader_parameter("clock",shot.age+index*0.13)
