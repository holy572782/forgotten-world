extends SceneTree
## Original shadow geometry must survive visual fading, without owning collision.
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	var arena = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(arena)
	var camera: Camera3D = arena.get_node("Preview/Camera3D")
	camera.size = 13
	camera.position = Vector3(13, 10, 10)
	camera.look_at(Vector3(5, 0, -1))
	arena.get_node("Preview/Instructions").hide()
	var fader = load("res://scripts/camera/occlusion_fader.gd").new()
	await _image("opaque")
	for item in ["StepLow", "StepMiddle", "StepHigh", "Wall", "Ramp", "Landing"]:
		var mesh: MeshInstance3D = arena.get_node("Terrain/" + item + "/Mesh")
		var original := mesh.get_active_material(0)
		fader._begin(mesh)
		var proxy: MeshInstance3D = mesh.get_node("OcclusionShadow")
		_check(proxy.mesh == mesh.mesh and proxy.get_active_material(0) == original, "Original geometry/material: " + item)
		_check(proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Shadow-only helper")
		_check(proxy.global_transform.is_equal_approx(mesh.global_transform), "World transform including ramp rotation")
		var found: Dictionary = {}
		fader._collect_meshes(mesh, found)
		_check(found.size() == 1, "No recursively fading shadow helper")
		mesh.get_active_material(0).albedo_color.a = 0.3
		_check(is_equal_approx(original.albedo_color.a, 1), "Original opacity unchanged")
	await _image("preserved")
	# Reference image of the previous implementation: the same faded surfaces, no shadow caster.
	for entry in fader.entries.values(): entry.shadow_proxy.hide()
	await _image("old_missing")
	fader.restore_all()
	for item in ["StepLow", "StepMiddle", "StepHigh", "Wall", "Ramp", "Landing"]:
		var mesh: MeshInstance3D = arena.get_node("Terrain/" + item + "/Mesh")
		_check(not mesh.has_node("OcclusionShadow") and mesh.get_surface_override_material(0) == null, "Exact cleanup: " + item)
	await _image("restored")
	var middle: MeshInstance3D = arena.get_node("Terrain/StepMiddle/Mesh")
	fader._begin(middle)
	middle.get_active_material(0).albedo_color.a = 0.3
	await _image("partial_steps")
	fader.restore_all()
	var wall: MeshInstance3D = arena.get_node("Terrain/Wall/Mesh")
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fader._begin(wall)
	_check(not wall.has_node("OcclusionShadow"), "Originally disabled shadow stays disabled")
	fader.restore_all()
	_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "OFF restored")
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	fader._begin(wall)
	_check(wall.get_node("OcclusionShadow").get_active_material(0).cull_mode == BaseMaterial3D.CULL_DISABLED, "Double-sided shadow preserved")
	fader.restore_all()
	_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Double-sided restored")
	fader._begin(wall)
	var proxy: MeshInstance3D = wall.get_node("OcclusionShadow")
	wall.free()
	fader.restore_all()
	_check(not is_instance_valid(proxy), "Deleted occluder leaves no helper")
	arena.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M04 shadows: geometry/material ownership, transformed terrain, collection exclusion, restoration, OFF/double-sided, deletion")
	quit(0 if failures.is_empty() else 1)

func _image(label: String) -> void:
	if not capture: return
	for frame in range(3): await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/m04_shadow_" + label + ".png") == OK, "Save " + label)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
