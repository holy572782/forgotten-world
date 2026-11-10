extends "res://tests/m10_rebuild_02r.gd"

const DIR := "res://docs/images/m10_rebuild/03a/"
var summit: Node3D

func _run() -> void:
	root.min_size = CAPTURE_SIZE
	root.max_size = CAPTURE_SIZE
	root.size = CAPTURE_SIZE
	root.unfocusable = true
	for action in ["move_up","move_down","move_left","move_right","jump","camera_left","camera_right"]:
		InputMap.action_erase_events(action)
	var headless := "--physics" in OS.get_cmdline_user_args()
	var prior := "--prior" in OS.get_cmdline_user_args()
	var profiling := "--profile" in OS.get_cmdline_user_args() or prior
	var cap := 30 if "--30" in OS.get_cmdline_user_args() else 60
	Engine.max_fps = 0 if headless else cap
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	scene=load("res://scenes/maps/wind_hills_rebuild/playground.tscn").instantiate()
	if prior:
		var original: Script = load("res://.godot/m10_03a_original_field.gd")
		if original==null:
			quit(1)
			return
		scene.get_node("Field").set_script(original)
		scene.get_node("Field").exploration_physics=true
	root.add_child(scene)
	field=scene.get_node("Field")
	player=scene.get_node("Player")
	rig=scene.get_node("CameraRig")
	summit=field.get_node("ArchitectureProxies/Summit")
	await _ticks(45)
	var bounds := AABB()
	var first := true
	for visual: MeshInstance3D in summit.find_children("*","MeshInstance3D",true,false):
		if visual.name=="PlazaSurface": continue
		var box := visual.global_transform*visual.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	results.dimensions_m=str(bounds.size)
	results.generation_ms=field.generation_ms
	results.meshes=field.find_children("*","MeshInstance3D",true,false).size()
	results.summit_meshes=summit.find_children("*","MeshInstance3D",true,false).size()
	results.shapes=field.find_children("*","CollisionShape3D",true,false).size()
	results.summit_shapes=summit.find_children("*","CollisionShape3D",true,false).size()
	var route := [Vector2(1,1),Vector2(4,-4),Vector2(4,-12),Vector2(21,-12),Vector2(21,-18),Vector2(0,-18),Vector2(-23,-14),Vector2(0,-12),Vector2(4,-4),Vector2(1,1)]
	var path := []
	for p: Vector2 in route: path.append(summit.to_global(Vector3(p.x,0,p.y)))
	if not profiling:
		await _place(path[0])
		await _walk(path,"plaza_loop")
		_check(airborne_ticks==0,"plaza grounded")
	var space := player.get_world_3d().direct_space_state
	for member: StaticBody3D in summit.find_children("*","StaticBody3D",true,false):
		if prior or member.name=="Vault": continue
		var pos := member.global_position+Vector3.UP*.35
		var axis := member.global_basis.z.normalized()
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(pos+axis*2.3,pos-axis*2.3,1))
		_check(hit.get("collider")==member,"solid "+str(member.get_path()))
	if headless:
		for member: StaticBody3D in summit.find_children("*","StaticBody3D",true,false):
			if member.name=="Vault": continue
			var foot := field.to_local(member.global_position)
			_check(absf(field.surface_height(foot.x,foot.z)-foot.y)<0.05,"supported "+str(member.get_path()))
		await _walk_into(summit.get_node("Bay00/East"))
		await _walk_into(summit.get_node("Wall00"))
		_scan_roads()
		await _camera_trials()
		await _recovery_trials()
		await _road_trials()
		await _bridge_entries()
		await _cliff_walks()
		await _supplement()
		results.regression=diagnostics
	else:
		var sites := {"stairs":[_ground(field.routes[0].curve[46]),-20],"entrance":[path.front(),0],
			"under":[summit.to_global(Vector3(4,0,-3)),35],"aisle":[summit.to_global(Vector3(-12,0,-15)),-65],
			"reverse":[summit.to_global(Vector3(0,0,-29)),180],"across":[summit.to_global(Vector3(31,0,-11)),75]}
		for label in sites:
			if profiling: break
			rig.rotation.y=deg_to_rad(sites[label][1])
			await _place(sites[label][0])
			if cap==60 and not profiling: await _capture(label)
		rig.rotation.y=deg_to_rad(75)
		await _place(summit.to_global(Vector3(0,0,-5)))
		frames.clear()
		physics_times.clear()
		previous_usec=0
		measuring=true
		Input.action_press("camera_left")
		var faded:=0
		var outside:=0
		var peak_calls:=0
		var calls_total:=0
		for i in range(cap*7):
			await process_frame
			if not rig.fader.entries.is_empty(): faded+=1
			var subject: Array[Vector3]=[player.position+rig.settings.target_offset]
			if not rig.frames_points(subject,.04): outside+=1
			var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			peak_calls=maxi(peak_calls,calls)
			calls_total+=calls
		measuring=false
		_release()
		_stats("summit_orbit")
		results.orbit={"fade_frames":faded,"outside":outside,"peak_draw_calls":peak_calls,"mean_draw_calls":float(calls_total)/(cap*7)}
		_check(faded>0 and outside==0,"visible through occlusion")
		await _place(path.front()+Vector3.BACK*14)
		await _ticks(40)
		_check(rig.fader.entries.is_empty(),"occlusion restored")
		if cap==60 and not profiling:
			scene.get_node("HUD").hide()
			scene.get_node("Guide").hide()
			var view:=Camera3D.new()
			scene.add_child(view)
			view.fov=46
			view.make_current()
			for label in {"front":0,"oblique":1,"masonry":2}:
				var eye:Vector3={"front":Vector3(2,12,64),"oblique":Vector3(-47,20,37),"masonry":Vector3(-20,5,5)}[label]
				var focus:=Vector3(-24,5,-7) if label=="masonry" else Vector3(0,7,-14)
				view.position=summit.to_global(eye)
				view.look_at(summit.to_global(focus))
				await _ticks(4)
				await _capture(label)
			root.remove_child(scene)
			var fixed:Node3D=load("res://scenes/maps/wind_hills_rebuild/comparison.tscn").instantiate()
			root.add_child(fixed)
			await _ticks(12)
			await _capture("fixed")
			fixed.free()
	results.checks=checks
	results.failures=failures
	var label := "physics" if headless else str(cap)
	if profiling: label=("prior_" if prior else "profile_")+label
	var file:=FileAccess.open("res://docs/measurements/m10_rebuild_03a_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("03-A ",label," ",checks," checks; failures: ",failures)
	scene.free()
	quit(0 if failures.is_empty() else 1)

func _capture(label:String) -> void:
	await RenderingServer.frame_post_draw
	var shot:=root.get_texture().get_image()
	_check(shot.get_size()==CAPTURE_SIZE and shot.save_png(DIR+label+".png")==OK,"capture "+label)

func _walk_into(member: StaticBody3D) -> void:
	var outward := member.global_basis.z.normalized()
	await _place(member.global_position+outward*2.8)
	var contacted := false
	for i in 55:
		_steer(-outward)
		await _ticks(1)
		for j in player.get_slide_collision_count():
			if player.get_slide_collision(j).get_collider()==member: contacted=true
	_release()
	_check(contacted and (player.position-member.global_position).dot(outward)>0.4,"player blocked by "+str(member.name))
