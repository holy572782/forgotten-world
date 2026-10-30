extends SceneTree
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)
func _image() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _difference(a: Image, b: Image) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x,y) != b.get_pixel(x,y): result.append(Vector2i(x,y))
	return result
func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(800,600)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1,0.2,0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.25
	world.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(25,25)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.7,0.7,0.65)
	floor_mesh.material_override = floor_material
	world.add_child(floor_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	world.add_child(camera)
	camera.make_current()
	var actor := preload("res://scenes/enemies/training_enemy.tscn").instantiate()
	world.add_child(actor)
	actor.get_node("Body").hide()
	actor.get_node("Targetable/HealthLabel").hide()
	var target: Node3D = actor.get_node("Targetable")
	var marker: MeshInstance3D = target.get_node("Marker/Mesh")
	_check(marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Runtime target marker alone disables cast_shadow")
	var current_material:=marker.material_override
	# Reproduce the former shadow with its actual opaque material. The new late
	# overlay pass does not participate in the old opaque shadow rendering path.
	var legacy_material:=StandardMaterial3D.new()
	legacy_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	legacy_material.albedo_color=Color(1,0.72,0.12)
	legacy_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	legacy_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	for yaw in [0.0,90.0,180.0,270.0]:
		camera.position = Vector3(0,9,9).rotated(Vector3.UP,deg_to_rad(yaw))
		camera.look_at(Vector3.ZERO)
		target.set_available(true,true)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var corrected := await _image()
		marker.material_override=legacy_material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var old := await _image()
		_check(not _difference(corrected,old).is_empty(), "Old marker cast produces a real floor shadow at each camera yaw")
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.material_override=current_material
		target.set_available(false)
		var hidden := await _image()
		var visible_pixels := _difference(corrected,hidden)
		var center := camera.unproject_position(Vector3(0,2,0))
		var bounds := Rect2(center-Vector2(40,40),Vector2(80,80))
		_check(not visible_pixels.is_empty() and visible_pixels.all(func(pixel: Vector2i) -> bool: return bounds.has_point(pixel)), "Corrected marker remains visible and changes no floor pixels outside its disc")
		if yaw == 0.0:
			old.save_png("res://.godot/marker_shadow_before.png")
			corrected.save_png("res://.godot/marker_shadow_after.png")
	# A separate shaded object still casts a real shadow under the same light.
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position = Vector3(2,0.5,0)
	world.add_child(cube)
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cube_shadow := await _image()
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check(not _difference(cube_shadow,await _image()).is_empty() and light.shadow_enabled, "Other object shadows and the light shadow setting remain functional")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("TARGET MARKER SHADOW ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions")
	quit(0 if failures.is_empty() else 1)
