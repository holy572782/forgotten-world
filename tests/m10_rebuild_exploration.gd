extends "res://tests/m10_wind_hills.gd"
## Uses the same camera-relative Input actions and production Player as the legacy walk test.
const IMAGE_DIR := "res://docs/images/m10_rebuild/exploration/"
const CAPTURE_SIZE := Vector2i(1672,941)
var stations := {}
var walking := false
var contact_gaps: Array[Dictionary] = []
var walk_jumps := 0

func _steer(direction: Vector3) -> void:
	if walking and not player.is_on_floor() and contact_gaps.size()<64:
		contact_gaps.append({"leg":phase,"position":str(player.position),"velocity_y":player.velocity.y})
	super._steer(direction)

func _world_curve(route: Dictionary) -> Array:
	var points := []
	for p: Vector3 in route.curve:
		points.append(field.to_global(p))
	return points

func _ground(local: Vector3) -> Vector3:
	local.y = field.surface_height(local.x,local.z)
	return field.to_global(local)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	fast = "--fast" in args
	fps = 30 if "--30" in args else 60
	Engine.max_fps = 0 if fast else fps
	if not fast:
		root.unfocusable = true
		root.unresizable = true
		root.min_size = CAPTURE_SIZE
		root.max_size = CAPTURE_SIZE
	root.size = CAPTURE_SIZE
	var keyboard := {"move_up":KEY_W,"move_down":KEY_S,"move_left":KEY_A,"move_right":KEY_D,
		"jump":KEY_SPACE,"camera_left":KEY_Q,"camera_right":KEY_E,"guard":KEY_I}
	for action in keyboard:
		var bound := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode==keyboard[action]:
				bound = true
		_check(bound,"production key bound to "+action)
		# Only this autonomous test process owns these actions; desktop key activity
		# must not inject a real jump into the no-jump walking measurement.
		InputMap.action_erase_events(action)
		Input.action_release(action)
	scene = load("res://scenes/maps/wind_hills_rebuild/playground.tscn").instantiate()
	root.add_child(scene)
	field = scene.get_node("Field")
	player = scene.get_node("Player")
	player.jump_started.connect(func():
		if walking: walk_jumps += 1)
	rig = scene.get_node("CameraRig")
	await _ticks(70)
	results.environment = {"godot":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"fps_cap":Engine.max_fps,
		"physics_hz":Engine.physics_ticks_per_second,"resolution":[1672,941]}
	results.generation_ms = field.generation_ms
	results.terrain_shapes = field.get_node("Terrain").find_children("*","CollisionShape3D",true,false).size()
	results.architecture_shapes = field.get_node("ArchitectureProxies").find_children("*","CollisionShape3D",true,false).size()
	results.safe_points = scene.safe_points.size()
	_check(player.is_on_floor() and player.combat!=null,"production player at gate")
	_check(results.terrain_shapes==484 and results.architecture_shapes>0,"chunk and architecture collision")
	_check(not field.has_node("EntranceRehearsalFloor") and field.get_node("DistantCompositionProxies").find_children("*","CollisionShape3D",true,false).is_empty(),"no pad or background collision")
	_check(scene.safe_points.size()==7,"seven supported recovery anchors")
	_check_chunk_floors()
	var main := _world_curve(field.routes[0])
	var left := _world_curve(field.routes[1])
	var river := _world_curve(field.routes[2])
	stations = {"entrance":main[8],"middle":main[25],"lookout":left[24],"bridge":field.get_node("Landmarks/D_bridge").global_position,"summit":main.back()+Vector3(0,0,-4)}
	if not "--stations" in args:
		await _traverse(main,left,river)
		await _jump_and_camera(main)
		await _fall_and_solid()
	await _walk_off_map()
	if not fast:
		await _profile_stations()
	results.airborne_walk_samples = airborne_ticks
	results.walk_samples = route_ticks
	results.contact_gaps = contact_gaps
	results.jump_inputs_during_walk = walk_jumps
	results.checks = checks
	results.failures = failures
	var suffix := "fast" if fast else str(fps)
	if "--stations" in args: suffix += "_stations"
	var report := FileAccess.open("res://docs/measurements/m10_rebuild_exploration_"+suffix+".json",FileAccess.WRITE)
	report.store_string(JSON.stringify(results,"\t"))
	report.close()
	print("Stage 02: ",checks," checks; failures: ",failures)
	_release()
	InputMap.load_from_project_settings()
	scene.free()
	quit(0 if failures.is_empty() else 1)

func _traverse(main: Array, left: Array, river: Array) -> void:
	# No reset_motion or teleport between these legs. Both forks join the main road.
	measuring = not fast
	walking = true
	await _walk(main.slice(8,25),"gate_to_middle")
	var stopped := player.position
	await _ticks(15)
	_check(player.position.distance_to(stopped)<0.08,"stop on middle road")
	await _walk(main.slice(25),"middle_to_summit")
	_check(player.is_on_floor() and absf(player.position.y-45)<0.25,"summit elevation")
	var down := main.slice(8)
	down.reverse()
	await _walk(down,"summit_to_gate")
	await _walk(main.slice(8,17),"gate_to_left_fork")
	await _walk(left.slice(0,25),"left_climb")
	_check(player.is_on_floor() and player.position.distance_to(stations.lookout)<0.85,"reach lookout on foot")
	var explore := [stations.lookout+Vector3(0,0,-2),stations.lookout+Vector3(1.5,0,-2),stations.lookout]
	await _walk(explore,"lookout_walk")
	await _walk(left.slice(25),"left_rejoin")
	var between := main.slice(24,33)
	between.reverse()
	await _walk(between,"main_to_river_fork")
	await _walk(river,"cross_to_far_bank")
	var back := river.duplicate()
	back.reverse()
	await _walk(back,"cross_back_to_main")
	_check(airborne_ticks==0,"continuous walking contact on all routes")
	measuring = false
	walking = false
	_stats("routes_performance")
	results.long_frames = long_frames

func _check_chunk_floors() -> void:
	var cfg: Dictionary = field.layout.terrain
	var space := field.get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	var terrain := field.get_node("Terrain")
	var checked := 0
	var cliff_samples := 0
	var misses := 0
	var max_error := 0.0
	# Cast inside a triangle rather than directly onto a grid seam or vertex.
	for x in range(cfg.min_x,cfg.max_x,cfg.chunk):
		for z in range(cfg.min_z,cfg.max_z,cfg.chunk):
			var point := _ground(Vector3(x+4.7,0,z+4.5))
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.20,point-Vector3.UP*0.20,1)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty() and not terrain.is_ancestor_of(hit.collider):
				ray.exclude = [hit.rid]
				hit = space.intersect_ray(ray)
			checked += 1
			if hit.is_empty() or not terrain.is_ancestor_of(hit.collider):
				misses += 1
				continue
			max_error = maxf(max_error,absf(hit.position.y-point.y))
			if hit.normal.y < cos(player.floor_max_angle): cliff_samples += 1
	results.chunk_floor_probes = {"samples":checked,"misses":misses,"max_error_m":max_error,"over_floor_angle":cliff_samples}
	_check(checked==484 and misses==0 and max_error<0.025 and cliff_samples>0,"static collision follows grass and steep cliff triangles across all chunks")

func _jump_and_camera(main: Array) -> void:
	for entry in [["flat",main[8]],["slope",main[26]],["stairs",main[38]],["terrace_edge",_ground(field.vec(field.layout.road_lookout)+Vector3(5,0,2))]]:
		await _place(entry[1])
		var start := player.position
		var count: int = scene.recovery_count
		Input.action_press("jump")
		await _ticks(2)
		Input.action_release("jump")
		var peak := player.position.y
		for i in range(55):
			await _ticks(1)
			peak = maxf(peak,player.position.y)
		_check(peak-start.y>1.0 and player.is_on_floor() and scene.recovery_count==count,str(entry[0])+" jump and landing")
		Input.action_press("move_right")
		await _ticks(12)
		_release()
		_check(player.position.distance_to(start)>0.35,str(entry[0])+" moves after landing")
	await _place(stations.entrance+Vector3(0,0,-2))
	for action in ["camera_left","camera_right"]:
		Input.action_press(action)
		var turn := 0.0
		var previous_yaw := rig.rotation.y
		var visible := true
		var faded := false
		for step in range(216):
			await physics_frame
			turn += wrapf(rig.rotation.y-previous_yaw,-PI,PI)
			previous_yaw = rig.rotation.y
			visible = visible and not rig.safety_failed and rig.camera.cull_mask!=0
			faded = faded or not rig.fader.entries.is_empty()
		Input.action_release(action)
		_check(absf(absf(turn)-TAU)<0.07 and visible,action+" full orbit maintains view")
		_check(faded,action+" gate occludes and fades during orbit")
	Input.action_press("camera_right")
	await _ticks(23)
	Input.action_release("camera_right")
	var direction: Vector3 = player.horizontal_forward(rig.camera.global_basis)
	var from := player.position
	Input.action_press("move_up")
	await _ticks(20)
	_release()
	_check((player.position-from).normalized().dot(direction)>0.95,"forward follows rotated camera")

func _fall_and_solid() -> void:
	var space := player.get_world_3d().direct_space_state
	var bridge: Vector3 = stations.bridge
	for ray in [[bridge-Vector3.UP*2,bridge+Vector3.UP],[bridge+Vector3(0,-0.35,3.5),bridge+Vector3(0,-0.35,0)]]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ray[0],ray[1],1))
		_check(not hit.is_empty() and field.get_node("ArchitectureProxies").is_ancestor_of(hit.collider),"bridge solid side or underside")
	var gate: Vector3 = stations.entrance
	await _place(gate+Vector3(3,0,2))
	_steer(Vector3.FORWARD)
	await _ticks(45)
	_release()
	_check(player.position.z>gate.z+0.6 and player.position.z<gate.z+1.5,"gate pier blocks player")
	# Step off the gate's low wall and keep playing on supported grass.
	await _place(gate+Vector3(6.75,1.65,0))
	var before: int = scene.recovery_count
	var was_airborne := false
	_steer(Vector3.BACK)
	for i in range(55):
		await _ticks(1)
		was_airborne = was_airborne or not player.is_on_floor()
	_release()
	_check(was_airborne and player.is_on_floor() and absf(player.position.y)<0.2 and scene.recovery_count==before,"ordinary ledge fall lands on grass")
	# Start from a previously reached safe bank, then actually jump off the bridge.
	await _place(field.to_global(field.routes[2].points[3]))
	var bank: Vector3 = scene.last_safe
	await _place(bridge)
	before = scene.recovery_count
	Input.action_press("jump")
	_steer(Vector3.BACK)
	for i in range(180):
		await _ticks(1)
		if i==3: Input.action_release("jump")
		if scene.recovery_count>before: break
	_release()
	_check(scene.last_recovery=="river" and scene.recovery_count==before+1 and player.position.distance_to(bank)<0.25,"bridge fall returns to visited bank")
	await _ticks(20)
	Input.action_press("guard")
	await _ticks(3)
	Input.action_press("jump")
	player.combat.queued = true
	rig.hold_follow()
	# Inject the boundary crossing only; use the standard recovery and controller thereafter.
	player.global_position = field.to_global(Vector3(field.layout.terrain.max_x+4,-40,0))
	await _ticks(4)
	_check(scene.last_recovery=="boundary" and player.position.distance_to(bank)<0.3,"outer boundary returns to bank")
	_check(not rig.follow_locked and not player.combat.queued and player.combat.state==player.combat.State.Idle,"recovery clears combat, reserved input and camera")
	_release()
	await _ticks(20)
	var start := player.position
	Input.action_press("jump")
	Input.action_press("move_right")
	await _ticks(12)
	_release()
	_check(player.position.y>start.y+0.65 and player.position.distance_to(start)>0.8,"jump and move after recovery")
	await _ticks(65)
	_check(player.is_on_floor(),"post-recovery landing")

func _profile_stations() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IMAGE_DIR))
	for label in stations:
		await _place(stations[label])
		var headings := {"lookout":-72.0,"bridge":90.0}
		rig.rotation.y = deg_to_rad(headings.get(label,0.0))
		rig.snap_to_target()
		await _ticks(45)
		_check(player.is_on_floor() and not rig.safety_failed,label+" playable view")
		if fps==60:
			await _save_station(label)
		# Encoding the PNG can span the next process interval. Discard it before sampling.
		await process_frame
		await process_frame
		frames.clear()
		physics_times.clear()
		phase = label
		previous_usec = 0
		measuring = true
		for i in range(fps*6): await process_frame
		measuring = false
		_stats(label)
		results[label]["viewport"] = [root.size.x,root.size.y]
		_check(root.size==CAPTURE_SIZE,label+" measurement at fixed resolution")
	if fps==60:
		root.remove_child(scene)
		var fixed: Node3D = load("res://scenes/maps/wind_hills_rebuild/comparison.tscn").instantiate()
		root.add_child(fixed)
		fixed.get_node("ReviewCamera").make_current()
		await _ticks(30)
		await _save_station("comparison")
		fixed.free()

func _save_station(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.get_size()==CAPTURE_SIZE and image.save_png(IMAGE_DIR+label+".png")==OK,label+" full resolution screenshot")

func _walk_off_map() -> void:
	# From the southern grass edge, leave the solid terrain under ordinary input.
	var edge: Vector3 = _ground(Vector3(-15,0,field.layout.terrain.max_z-2))
	var anchor: Vector3 = scene.last_safe
	await _place(edge)
	var count: int = scene.recovery_count
	var left_floor := false
	_steer(Vector3.BACK)
	for i in range(100):
		await _ticks(1)
		left_floor = left_floor or not player.is_on_floor()
		if scene.recovery_count>count: break
	_release()
	await _ticks(20)
	_check(left_floor and scene.last_recovery=="boundary" and scene.recovery_count==count+1,"walk off map edge under gravity")
	_check(player.is_on_floor() and player.position.distance_to(anchor)<0.3,"boundary fall lands at supported anchor")
