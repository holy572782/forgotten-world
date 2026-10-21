extends "res://tests/m04_camera.gd"
## Real capsule contact, diagnostic wireframe, and four-sided/Yaw render fixtures.

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode = 0 # Isolate this legacy trial from the F5 enemy.
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	# Isolate the 3D pixel comparison from the live FPS/debug HUD.
	main.get_node("HUD").visible = false
	player = main.get_node("Player")
	rig = main.get_node("CameraRig")
	camera = rig.camera
	var wire := _capsule_wire()
	player.add_child(wire)
	var cases := [
		[Vector3(3, 0, -7.5), 0, Vector3(3, 0, -8.399), "front"],
		[Vector3(3, 0, -10.5), 180, Vector3(3, 0, -9.601), "back"],
		[Vector3(-2.5, 0, -9), 270, Vector3(-1.301, 0, -9), "left"],
		[Vector3(8.5, 0, -9), 90, Vector3(7.301, 0, -9), "right"],
	]
	for item in cases:
		await _reset(item[0], item[1])
		held.move_up = 1.0
		await _ticks(60)
		held.clear()
		await _ticks(10)
		print("CONTACT ", item[3], " ", player.global_position)
		_check(player.global_position.distance_to(item[2]) < 0.02, "Capsule blocked at " + item[3])
		wire.visible = true
		await _image("depth_capsule_" + item[3])
		wire.visible = false
		for yaw in [0, 90, 180, 270]:
			rig.rotation.y = deg_to_rad(float(yaw))
			rig.snap_to_target()
			await _ticks(30)
			await _image("depth_" + item[3] + "_" + str(yaw))
	await _reset(Vector3(-3.699, 0, -8), 90)
	await _image("depth_platform")
	if capture:
		# A fully opaque wall must still hide the sprite. Freeze fading only in this fixture.
		await _reset(Vector3(3, 0, -9.7), 0)
		rig.set_physics_process(false)
		rig.fader.restore_all()
		var sprite := player.get_node("AnimatedSprite3D")
		sprite.get_node("Shadow").visible = false
		await _ticks(3)
		await RenderingServer.frame_post_draw
		var hidden := root.get_texture().get_image()
		await _image("depth_opaque_behind")
		sprite.visible = false
		await _ticks(3)
		await RenderingServer.frame_post_draw
		var absent := root.get_texture().get_image()
		_check(hidden.get_data() == absent.get_data(), "Opaque wall fully occludes body: not always on top")
		sprite.visible = true
		sprite.get_node("Shadow").visible = true
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS wall depth: four capsule contacts; 16 views and opaque occlusion when --capture")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _capsule_wire() -> MeshInstance3D:
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Meridian outlines and horizontal rings use the actual collision dimensions.
	for yaw in range(0, 180, 30):
		for index in range(64):
			for step in [index, index + 1]:
				var angle: float = TAU * step / 64.0
				var y := sin(angle) * shape.radius + signf(sin(angle)) * (shape.height * 0.5 - shape.radius)
				mesh.surface_add_vertex(Vector3(cos(angle) * shape.radius, y, 0).rotated(Vector3.UP, deg_to_rad(float(yaw))))
	mesh.surface_end()
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.position = player.get_node("CollisionShape3D").position
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0, 1)
	display.material_override = material
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return display
