extends "res://tests/m10_rebuild_exploration.gd"
## Compare the same physical inputs on both revisions. Run the broad scan headless;
## the image pass visits the same locations using the actual production camera.
const OUT := "res://docs/images/m10_rebuild/02r/"
var baseline := false
var photos := false
var prefix := ""
var diagnostics := {}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	baseline = "--before" in args
	photos = "--photos" in args
	prefix = "before_" if baseline else "after_"
	root.unfocusable = true
	root.unresizable = true
	root.min_size = CAPTURE_SIZE
	root.max_size = CAPTURE_SIZE
	root.size = CAPTURE_SIZE
	for action in ["move_up","move_down","move_left","move_right","jump","guard","camera_left","camera_right"]:
		InputMap.action_erase_events(action)
	if "--startup" in args:
		await _startup_pairs()
		return
	scene = load("res://scenes/maps/wind_hills_rebuild/playground.tscn").instantiate()
	root.add_child(scene)
	field = scene.get_node("Field")
	player = scene.get_node("Player")
	rig = scene.get_node("CameraRig")
	if baseline and "framing_calls" in rig:
		push_error("The before capture requires the stage 02 production scene at 125cfc0.")
		scene.free()
		quit(1)
		return
	await _ticks(45)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--walking-photos" in args:
		photos = true
		await _walking_photos()
		print("Walking images: ",checks," checks; failures: ",failures)
		scene.free()
		quit(0 if failures.is_empty() else 1)
		return
	if "--supplement" in args:
		await _supplement()
		diagnostics.checks = checks
		diagnostics.failures = failures
		var extra := FileAccess.open("res://docs/measurements/m10_rebuild_02r_supplement.json",FileAccess.WRITE)
		extra.store_string(JSON.stringify(diagnostics,"\t"))
		print("02-R supplement: ",checks," checks; failures: ",failures)
		scene.free()
		quit(0 if failures.is_empty() else 1)
		return
	diagnostics.generation_ms = field.generation_ms
	_scan_roads()
	await _camera_trials()
	await _recovery_trials()
	await _road_trials()
	if not baseline:
		await _bridge_entries()
		await _cliff_walks()
	diagnostics.checks = checks
	diagnostics.failures = failures
	var suffix := "photos" if photos else "physics"
	var file := FileAccess.open("res://docs/measurements/m10_rebuild_02r_"+prefix+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(diagnostics,"\t"))
	print("02-R ",prefix,suffix," ",checks," checks; failures: ",failures)
	_release()
	scene.free()
	quit(0 if failures.is_empty() else 1)

func _startup_pairs() -> void:
	var old_script: Script = load("res://.godot/m10_02r_original_field.gd")
	if not old_script:
		quit(1)
		return
	var current: Script = load("res://scripts/maps/wind_hills_rebuild/field.gd")
	var data := {"before":[],"after":[],"renderer":RenderingServer.get_current_rendering_method(),"order":[]}
	for label in ["before","after","after","before","before","after"]:
		var terrain: Node3D = load("res://scenes/maps/wind_hills_rebuild/field.tscn").instantiate()
		terrain.set_script(old_script if label=="before" else current)
		terrain.exploration_physics = true
		root.add_child(terrain)
		data[label].append(terrain.generation_ms)
		data.order.append(label)
		_check(terrain.get_node("Terrain").get_child_count()==484,label+" full terrain")
		terrain.free()
		await process_frame
	data.upper_road_30fps = await _paired_upper_road(old_script)
	data.checks = checks
	data.failures = failures
	var file := FileAccess.open("res://docs/measurements/m10_rebuild_02r_startup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	print("Startup pairs: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)

func _paired_upper_road(old_field: Script) -> Array:
	var records := []
	Engine.max_fps = 30
	var old_recovery: Script = load("res://.godot/m10_02r_original_playground.gd")
	for label in ["before","after","after","before"]:
		scene = load("res://scenes/maps/wind_hills_rebuild/playground.tscn").instantiate()
		field=scene.get_node("Field")
		player=scene.get_node("Player")
		rig=scene.get_node("CameraRig")
		if label=="before":
			field.set_script(old_field)
			field.exploration_physics=true
			scene.set_script(old_recovery)
			rig.set_script(load("res://scripts/camera/camera_rig.gd"))
			rig.target=player
		root.add_child(scene)
		var road := _world_curve(field.routes[0]).slice(24)
		await _place(_ground(field.to_local(road.front())))
		await _ticks(45)
		previous_usec=0
		measuring=true
		await _walk(road,"middle_to_summit")
		measuring=false
		_stats(label)
		records.append({"revision":label,"performance":results[label]})
		scene.free()
		await process_frame
	return records

func _shot(label: String) -> void:
	if not photos: return
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	print("SHOT ",label," ",shot.get_size())
	_check(shot.get_size()==CAPTURE_SIZE and shot.save_png(OUT+prefix+label+".png")==OK,"capture "+label)

func _side(curve: Array, i: int) -> Vector3:
	var tangent: Vector3 = curve[mini(i+1,curve.size()-1)]-curve[maxi(i-1,0)]
	return Vector3(-tangent.z,0,tangent.x).normalized()

func _walking_photos() -> void:
	for fraction in [-0.92,0.0,0.92]:
		var lane := _lane(field.routes[0],fraction)
		var label := "left" if fraction<0 else ("right" if fraction>0 else "center")
		rig.rotation.y = deg_to_rad(-20)
		await _place(_ground(field.to_local(lane[43])))
		var direction: Vector3 = lane[44]-player.position
		direction.y = 0
		_steer(direction.normalized())
		await _ticks(12)
		_check(player.is_on_floor() and player.get_real_velocity().length()>1.0,label+" walking during capture")
		await _shot("walking_"+label)
		_release()

func _lane(route: Dictionary, fraction: float) -> Array:
	var points := []
	for i in range(route.curve.size()):
		var p: Vector3 = route.curve[i]+_side(route.curve,i)*route.width*0.5*fraction
		points.append(field.to_global(p))
	return points

func _normal(p: Vector3) -> Vector3:
	var cell := int(field.layout.terrain.step)
	var x := floori(p.x/cell)*cell
	var z := floori(p.z/cell)*cell
	var b: Vector3 = field.vertex(x+cell,z)
	var c: Vector3 = field.vertex(x,z+cell)
	if p.x-x+p.z-z <= cell:
		var a: Vector3 = field.vertex(x,z)
		return (c-a).cross(b-a).normalized()
	var d: Vector3 = field.vertex(x+cell,z+cell)
	return (c-b).cross(d-b).normalized()

func _scan_roads() -> void:
	var scans := {}
	for route in field.routes:
		var rows := []
		for fraction in [-1.0,-0.8,-0.5,0.0,0.5,0.8,1.0]:
			var lane := _lane(route,fraction)
			var worst := {}
			var peak := -1.0
			var steep := 0
			var total := 0
			for i in range(lane.size()-1):
				if route.id=="river" and i>=16 and i<20: continue
				var a: Vector3 = field.to_local(lane[i])
				var b: Vector3 = field.to_local(lane[i+1])
				var n := maxi(1,ceili(a.distance_to(b)/0.16))
				for j in range(n):
					var p := a.lerp(b,(j+0.5)/n)
					var normal := _normal(p)
					var angle := rad_to_deg(normal.angle_to(Vector3.UP))
					total += 1
					if angle>rad_to_deg(player.floor_max_angle): steep += 1
					if angle>peak:
						peak = angle
						worst = {"segment":i,"world":str(_ground(p)),"normal":str(normal),"angle":peak}
			rows.append({"lane":fraction,"over_limit":steep,"samples":total,"worst":worst})
			if not baseline: _check(steep==0,route.id+" road floor angle, lane "+str(fraction))
		scans[route.id]=rows
	diagnostics.roads=scans
	print("FLOOR ",JSON.stringify(scans.main))

func _camera_trials() -> void:
	var summit: Vector3 = field.get_node("Landmarks/E_summit").global_position
	var cases := {"pillar":summit+Vector3(0,0,-4),"rear":summit+Vector3(-12,0,-14),
		"cliff":field.get_node("Landmarks/C_overlook").global_position,"open":_ground(Vector3(-13,0,-26))}
	var obs := {}
	for label in cases:
		rig.rotation.y=0
		await _place(cases[label])
		obs[label]=await _orbit(label,"camera_left" if label=="pillar" else "camera_right",216)
	# A falling body going past the actual summit cliff. Start in the air after leaving the rim.
	var foot := _ground(Vector3(114,0,-239))
	player.reset_motion(foot+Vector3.UP*20)
	rig.snap_to_target()
	obs.fall=await _orbit("fall","camera_right",75)
	diagnostics.camera=obs
	print("CAMERA ",JSON.stringify(obs))

func _orbit(label: String, action: String, count: int) -> Dictionary:
	var max_error := -1.0
	var worst := {}
	var held := 0
	var faded := 0
	var out_of_frame := 0
	var step_angle := 0.0
	var previous: Basis = rig.camera.global_basis
	var max_offset := 0.0
	var pose_tick := 44
	if label=="fall": pose_tick=57
	if photos and FileAccess.file_exists("res://docs/measurements/m10_rebuild_02r_before_physics.json"):
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/measurements/m10_rebuild_02r_before_physics.json"))
		if original.camera.has(label): pose_tick=int(original.camera[label].worst.tick)
	Input.action_press(action)
	for i in range(count):
		await _ticks(1)
		var center: Vector3 = player.position+rig.settings.target_offset
		var uv: Vector2 = rig.camera.unproject_position(center)/Vector2(root.size)
		var error := uv.distance_to(Vector2(0.5,0.5))
		var desired: Vector3 = rig.arm.global_position+rig.arm.global_basis.z*rig.settings.camera_distance
		max_offset=maxf(max_offset,desired.distance_to(rig.camera.global_position))
		if rig.safety.holding: held+=1
		if not rig.fader.entries.is_empty(): faded+=1
		if rig.camera.is_position_behind(center) or not Rect2(0,0,1,1).has_point(uv) or rig.safety_failed: out_of_frame+=1
		if i>1: step_angle=maxf(step_angle,rad_to_deg(previous.get_rotation_quaternion().angle_to(rig.camera.global_basis.get_rotation_quaternion())))
		previous=rig.camera.global_basis
		if error>max_error:
			max_error=error
			worst={"tick":i,"uv":str(uv),"eye":str(rig.camera.position),"desired":str(desired),"offset_m":desired.distance_to(rig.camera.position),"pivot_error_m":center.distance_to(rig.global_position),"locked":rig.follow_locked}
		if i==pose_tick and label in ["pillar","rear","fall"]: await _shot(label)
	Input.action_release(action)
	if not baseline: _check(out_of_frame==0 and max_error<0.13,label+" actual projection")
	return {"error":max_error,"outside":out_of_frame,"held":held,"faded":faded,"max_step_deg":step_angle,"max_eye_offset_m":max_offset,"worst":worst}

func _supplement() -> void:
	var summit: Vector3 = field.get_node("Landmarks/E_summit").global_position
	var positions := {"front":summit+Vector3(0,0,-4),"back":summit+Vector3(-12,0,-14),"bend":_ground(field.routes[0].curve[44])}
	for location in positions:
		for action in ["camera_left","camera_right"]:
			rig.rotation.y = 0
			await _place(positions[location])
			diagnostics[location+"_"+action]=await _orbit(location,action,216)
	var shore := _ground(field.river_points[20]+Vector3(-10,0,0))
	await _place(shore)
	var before: int = scene.recovery_count
	scene.measure_cost = true
	_steer(Vector3.RIGHT)
	for i in range(220):
		var queries: int = scene.safety_queries
		var usec: int = scene.recovery_usec
		await _ticks(1)
		if scene.recovery_count>before:
			diagnostics.recovery_event={"reason":scene.last_recovery,"queries":scene.safety_queries-queries,"usec":scene.recovery_usec-usec}
			break
	_release()
	_check(diagnostics.has("recovery_event") and scene.last_recovery=="river","profile actual river recovery")
	# A temporary training target exercises the new scene's real camera binding.
	var meadow := _ground(Vector3(-15,0,13))
	await _place(meadow)
	var dummy: Node3D = load("res://scenes/enemies/training_enemy.tscn").instantiate()
	dummy.position = meadow+Vector3(2.8,0,0)
	scene.add_child(dummy)
	await _ticks(12)
	var combat: Node = player.combat
	var target: Node3D = dummy.get_node("Targetable")
	var anchor := player.position
	var pivot := rig.global_position
	_check(combat.request_attack(target),"attack with rebuild camera")
	var locked_ticks := 0
	var failed_lock := 0
	var queued := false
	var returning := false
	for i in range(360):
		await _ticks(1)
		if not combat.is_busy(): break
		locked_ticks+=1
		if not rig.follow_locked or rig.global_position.distance_to(pivot)>0.002: failed_lock+=1
		if not queued and combat.state==combat.State.Attack: queued=combat.request_followup(target)
		if combat.state==combat.State.Return: returning=true
	_check(queued and combat.combo_hits>=2 and returning and locked_ticks>0 and failed_lock==0,"combo and return hold original follow anchor")
	_check(not rig.follow_locked and player.position.distance_to(anchor)<0.05,"attack returns and unlocks")
	diagnostics.combat={"held_ticks":locked_ticks,"violations":failed_lock,"hits":combat.combo_hits,"return_error_m":player.position.distance_to(anchor)}
	dummy.free()
	await _ticks(12)
	Input.action_press("guard")
	await _ticks(6)
	var guard_angle := rad_to_deg(rig.camera.global_basis.get_rotation_quaternion().angle_to(rig.arm.global_basis.get_rotation_quaternion()))
	diagnostics.guard={"state":combat.state,"floor":player.is_on_floor(),"lens_error_deg":guard_angle,"result":combat.last_result}
	_check(combat.state==combat.State.Guard and guard_angle<0.05,"guard uses shared camera "+str(diagnostics.guard))
	_release()

func _recovery_trials() -> void:
	var records := []
	var bank: Vector3 = field.river_points[4*5]
	var start := _ground(bank+Vector3(-10,0,0))
	for j in range(2):
		await _place(start)
		var old_count: int=scene.recovery_count
		_steer(Vector3.RIGHT)
		for k in range(220):
			await _ticks(1)
			if scene.recovery_count>old_count: break
		_release()
		var dest := player.position
		records.append({"reason":scene.last_recovery,"from":str(start),"to":str(dest),"distance":start.distance_to(dest)})
		if not baseline: _check(scene.recovery_count==old_count+1 and scene.last_recovery=="river" and start.distance_to(dest)<10,"near shore after fall "+str(j))
		await _ticks(8)
		await _shot("shore" if j==0 else "shore_after_boundary")
		if j==0:
			var edge := _ground(Vector3(-15,0,field.layout.terrain.max_z-6))
			await _place(edge)
			old_count=scene.recovery_count
			_steer(Vector3.BACK)
			for k in range(150):
				await _ticks(1)
				if scene.recovery_count>old_count: break
			_release()
			records.append({"reason":scene.last_recovery,"from":str(edge),"to":str(player.position),"distance":edge.distance_to(player.position)})
			if not baseline: _check(scene.last_recovery=="boundary" and edge.distance_to(player.position)<8,"local boundary recovery")
	diagnostics.recoveries=records
	print("RECOVER ",JSON.stringify(records))

func _road_trials() -> void:
	var route: Dictionary=field.routes[0]
	for fraction in [-0.92,0.0,0.92]:
		var lane:=_lane(route,fraction)
		var section:=lane.slice(39)
		var label: String = "left" if fraction<0 else ("right" if fraction>0 else "center")
		rig.rotation.y=deg_to_rad(-20)
		await _place(_ground(field.to_local(section[0])))
		var air_before:=airborne_ticks
		var failed_before:=failures.size()
		await _walk(section.slice(0,5),label+"_approach")
		await _shot("road_"+label)
		await _walk(section.slice(4),label+"_up")
		section.reverse()
		Input.action_press("camera_right")
		await _ticks(24)
		Input.action_release("camera_right")
		await _walk(section,label+"_down")
		diagnostics[label]={"airborne":airborne_ticks-air_before,"failed":failures.size()-failed_before}
		if baseline:
			for failure in failures.duplicate():
				if failure.begins_with(label+"_"): failures.erase(failure)
		if not baseline: _check(airborne_ticks==air_before,label+" stays grounded")
		if not baseline and not photos:
			var entire := lane.slice(8)
			await _place(_ground(field.to_local(entire.front())))
			air_before = airborne_ticks
			await _walk(entire,label+"_gate_to_summit")
			entire.reverse()
			await _walk(entire,label+"_summit_to_gate")
			_check(airborne_ticks==air_before,label+" all-road ground contact")
			diagnostics[label].whole_road_airborne = airborne_ticks-air_before

func _bridge_entries() -> void:
	var route: Dictionary = field.routes[2]
	var bridge: Vector3 = field.get_node("Landmarks/D_bridge").global_position
	var records := []
	for east: bool in [false,true]:
		var approach := _world_curve(route).slice(18,25) if east else _world_curve(route).slice(12,19)
		if east: approach.reverse()
		await _place(_ground(field.to_local(approach.front())))
		await _walk(approach,"east bridge entry" if east else "west bridge entry")
		var entry: Vector3 = scene.bridge_entry
		var before: int = scene.recovery_count
		Input.action_press("jump")
		_steer(Vector3.BACK)
		for k in range(180):
			await _ticks(1)
			if k==3: Input.action_release("jump")
			if scene.recovery_count>before: break
		_release()
		var dest := player.position
		_check(scene.recovery_count==before+1 and scene.last_recovery=="river","bridge jump reaches water")
		_check(entry.is_finite() and dest.distance_to(entry)<0.35 and (dest.x>bridge.x)==east,"return to bridge entry side")
		await _ticks(30)
		var camera_result := await _orbit("post_recovery","camera_left" if east else "camera_right",216)
		Input.action_press("jump")
		Input.action_press("move_up")
		await _ticks(12)
		_release()
		_check(player.position.y>dest.y+0.65,"jump after bridge recovery")
		await _ticks(65)
		_check(scene.recovery_count==before+1 and player.is_on_floor(),"stable landing after bridge recovery")
		records.append({"east":east,"recorded_entry":str(entry),"destination":str(dest),"reason":scene.last_recovery,"camera":camera_result})
	diagnostics.bridge_entries = records

func _cliff_walks() -> void:
	var records := {}
	for label in ["E_summit","C_overlook"]:
		var center: Vector3 = field.vec(field.layout.landmarks[label])
		var best_drop := 0.0
		var start := Vector3.ZERO
		var walk := Vector3.ZERO
		# Find a supported rim descending away from each landmark.
		for angle in range(0,360,15):
			var outward := Vector3.RIGHT.rotated(Vector3.UP,deg_to_rad(angle))
			for radius in range(12,74,2):
				var local := center+outward*radius
				if _normal(local).y<cos(deg_to_rad(25.0)): continue
				var top := _ground(local)
				var bottom := _ground(local+outward*10.0)
				if top.y-bottom.y>best_drop:
					best_drop=top.y-bottom.y
					start=top
					walk=outward
		await _place(start)
		var before: int = scene.recovery_count
		var lowest := player.position.y
		var air := 0
		var outside := 0
		var shot := false
		Input.action_press("camera_left")
		for k in range(160):
			_steer(walk)
			await _ticks(1)
			if not player.is_on_floor(): air+=1
			var subject: Array[Vector3] = [player.position+rig.settings.target_offset]
			if not rig.frames_points(subject,0.05): outside+=1
			lowest=minf(player.position.y,lowest)
			if photos and label=="E_summit" and not shot and air>=8:
				await _shot("summit_cliff")
				shot=true
		_release()
		await _ticks(130)
		_check(air>0 and start.y-lowest>3.0 and player.is_on_floor(),label+" walk off cliff and land")
		_check(outside==0 and scene.recovery_count==before,label+" visible throughout ordinary fall")
		records[label]={"start":str(start),"end":str(player.position),"drop_m":start.y-lowest,"air_ticks":air,"outside":outside,"recoveries":scene.recovery_count-before}
	diagnostics.cliff_walks = records
