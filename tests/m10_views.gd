extends SceneTree
## Fast visual iteration. Full traversal/performance is m10_wind_hills.gd.
var scene: Node3D
func _initialize() -> void:
	call_deferred("_run")
func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/images/m10_"+name+".png")
func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 0 if "--fast" in OS.get_cmdline_user_args() else 60
	scene = load("res://scenes/maps/wind_hills/wind_hills_playground.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var rig: Node3D = scene.get_node("CameraRig")
	await _ticks(30)
	for place in ["B","E","H","G","I","J"]:
		player.reset_motion(scene.get_node("WindHills/"+place).position+Vector3.UP*0.03)
		rig.rotation.y = 0
		rig.snap_to_target()
		await _ticks(60)
		await _save(place.to_lower()+"_play")
		var original: Resource = rig.settings
		rig.settings = original.duplicate()
		rig.settings.pitch_angle = -24
		rig.settings.camera_distance = 12
		rig.arm.rotation.x = deg_to_rad(-24)
		rig.snap_to_target()
		await _ticks(30)
		await _save(place.to_lower()+"_compare")
		rig.settings = original
		rig.arm.rotation.x = deg_to_rad(-45)
		if place in ["H","G"]:
			rig.rotation.y = PI
			rig.snap_to_target()
			await _ticks(30)
			await _save(place.to_lower()+"_look_back")
	player.reset_motion(Vector3(0,0.02,0))
	rig.set_physics_process(false)
	rig.fader.restore_all()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(9,7,16)
	camera.look_at(Vector3(0,3.5,0))
	camera.far = 1800
	camera.make_current()
	await _ticks(30)
	await _save("gate_scale")
	camera.position = Vector3(165,200,240)
	camera.look_at(Vector3(0,10,-115))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 280
	camera.far = 1800
	camera.make_current()
	scene.get_node("HUD").visible = false
	scene.get_node("Guide").visible = false
	await _ticks(30)
	await _save("overview")
	quit()
