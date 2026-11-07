extends SceneTree
## Stage 01 smoke, image capture and composition measurements. Not route acceptance.
var failures: Array[String] = []
var checks := 0
var result := {"stage":"01", "full_route_traversal":"not implemented / stage 02", "views":{}}
var capture := true

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func ticks(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func save_image(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://docs/images/m10_rebuild/"+label+".png")==OK,"save "+label)

func _run() -> void:
	root.size = Vector2i(1672,941)
	Engine.max_fps = 60
	capture = not "--headless-check" in OS.get_cmdline_user_args()
	if "--baseline-only" in OS.get_cmdline_user_args():
		var previous: Node3D = load("res://scenes/maps/wind_hills/wind_hills_playground.tscn").instantiate()
		root.add_child(previous)
		await ticks(90)
		check(previous.get_node("Player").is_on_floor(),"stage 00 existing map entrance")
		await save_image("stage00_existing")
		previous.queue_free()
		await ticks(3)
		print("M10 rebuild stage00: ",checks," checks; failures: ",failures)
		quit(0 if failures.is_empty() else 1)
		return
	for label in ["comparison","overview"]:
		var scene: Node3D = load("res://scenes/maps/wind_hills_rebuild/"+label+".tscn").instantiate()
		root.add_child(scene)
		await ticks(60)
		var field: Node3D = scene.get_node("Field")
		var camera: Camera3D = scene.get_node("ReviewCamera")
		check(camera.is_current(),label+" independent camera current")
		check(field.get_node("Terrain").get_child_count()==484,"484 terrain blocks")
		check(field.get_node("EntranceRehearsalFloor").get_child_count()==1,"local rehearsal collider only")
		var landmarks := {}
		for marker in field.get_node("Landmarks").get_children():
			var uv := camera.unproject_position(marker.global_position)/Vector2(root.size)
			landmarks[marker.name] = [uv.x,uv.y]
			check(not camera.is_position_behind(marker.global_position),label+" landmark in front: "+str(marker.name))
		var view := {"landmarks":landmarks,"camera_position":str(camera.position),"rotation_degrees":str(camera.rotation_degrees),"projection":camera.projection,"fov":camera.fov,"size":camera.size,"generation_ms":field.generation_ms}
		if label=="comparison":
			var expected := {"A_gate":Vector2(0.40,0.85),"C_overlook":Vector2(0.14,0.34),"D_bridge":Vector2(0.80,0.71),"E_summit":Vector2(0.60,0.15)}
			for key in expected:
				var p: Array = landmarks[key]
				check(Vector2(p[0],p[1]).distance_to(expected[key])<0.04,"composition anchor "+key)
			view["summit_arch_top"] = str(camera.unproject_position(field.to_global(Vector3(53.1,83.7,-243)))/Vector2(root.size))
			var feet: Vector3 = scene.get_node("PlayerScaleReference").position
			view["player_height_px"] = camera.unproject_position(feet+Vector3.UP*1.8).distance_to(camera.unproject_position(feet))
		result.views[label] = view
		await save_image(label)
		scene.queue_free()
		await ticks(3)
	var play: Node3D = load("res://scenes/maps/wind_hills_rebuild/playground.tscn").instantiate()
	root.add_child(play)
	await ticks(90)
	var player: CharacterBody3D = play.get_node("Player")
	var rig: Node3D = play.get_node("CameraRig")
	check(player.is_on_floor(),"player rests on entrance floor")
	check(player.scale==Vector3.ONE,"player scale unchanged")
	check(is_equal_approx(rig.settings.pitch_angle,-45),"production pitch -45")
	check(is_equal_approx(rig.settings.camera_distance,10),"production distance 10")
	var start: Vector3 = player.position
	Input.action_press("move_right")
	await ticks(45)
	Input.action_release("move_right")
	await ticks(15)
	check(player.position.x>start.x+2,"production movement on entrance")
	Input.action_press("jump")
	await ticks(12)
	Input.action_release("jump")
	check(player.position.y>0.8,"production jump")
	await ticks(65)
	check(player.is_on_floor(),"production landing")
	player.reset_motion(start)
	rig.snap_to_target()
	await ticks(30)
	await save_image("entrance_play")
	# Operate actual camera actions; no shared settings mutation.
	var yaw: float = rig.rotation.y
	Input.action_press("camera_right")
	await ticks(30)
	Input.action_release("camera_right")
	await ticks(30)
	check(absf(rig.rotation.y-yaw)>0.1,"camera rotation action")
	player.reset_motion(Vector3(60,-3,30))
	await ticks(3)
	check(player.position.distance_to(start)<0.2,"rehearsal boundary returns to entrance")
	result["checks"] = checks
	result["failures"] = failures
	result["engine"] = Engine.get_version_info().string
	result["resolution"] = [root.size.x,root.size.y]
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["gpu"] = RenderingServer.get_video_adapter_name()
	var report_name := "m10_rebuild_stage01.json" if capture else "m10_rebuild_stage01_headless.json"
	var file := FileAccess.open("res://docs/measurements/"+report_name,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	play.queue_free()
	await ticks(3)
	print("M10 rebuild stage01: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
