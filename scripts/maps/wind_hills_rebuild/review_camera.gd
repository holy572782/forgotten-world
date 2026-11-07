@tool
extends Camera3D
## Inspector transform/FOV/projection remain editable. Optional authored preset.
@export var apply_layout_preset := true
@export_enum("comparison", "overview") var preset := "comparison"

func _ready() -> void:
	if not apply_layout_preset: return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/wind_hills_rebuild/layout.json"))
	var cfg: Dictionary = layout[preset+"_camera"]
	var unit: float = layout.world_scale
	position = Vector3(cfg.position[0],cfg.position[1],cfg.position[2])*unit
	projection = int(cfg.projection)
	fov = float(cfg.fov)
	size = float(cfg.size)*unit
	near = float(cfg.near)
	far = float(cfg.far)
	if cfg.has("target"):
		look_at(Vector3(cfg.target[0],cfg.target[1],cfg.target[2])*unit)
	else:
		rotation_degrees = Vector3(cfg.rotation_degrees[0],cfg.rotation_degrees[1],cfg.rotation_degrees[2])
	make_current()
	if get_parent().has_node("PlayerScaleReference"):
		get_parent().get_node("PlayerScaleReference").position = Vector3(layout.spawn[0],layout.spawn[1],layout.spawn[2])*unit
