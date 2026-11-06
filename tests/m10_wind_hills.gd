extends SceneTree
## Real production controller/physics, continuous route traversal and rendered evidence.
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var player: CharacterBody3D
var field: Node3D
var rig: Node3D
var frames: Array[float] = []
var physics_times: Array[float] = []
var measuring := false
var results: Dictionary = {}
var capture := false
var fps := 60
var fast := false
var previous_usec := 0
var route_ticks := 0
var airborne_ticks := 0
var overview: Camera3D
var smoke := false
var phase := "warmup"
var long_frames: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and previous_usec > 0:
		var elapsed := (now-previous_usec)/1000.0
		frames.append(elapsed)
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		if elapsed>50 and long_frames.size()<128:
			long_frames.append({"phase":phase,"frame_ms":elapsed,"position":str(player.global_position)})
	previous_usec = now
	return false

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _release() -> void:
	for action in ["move_left","move_right","move_up","move_down","jump","camera_left","camera_right","guard"]:
		Input.action_release(action)

func _steer(direction: Vector3) -> void:
	var right: Vector3 = rig.camera.global_basis.x
	right.y = 0
	right = right.normalized()
	var back: Vector3 = rig.camera.global_basis.z
	back.y = 0
	back = back.normalized()
	var x := direction.dot(right)
	var y := direction.dot(back)
	for entry in [["move_right",x],["move_left",-x],["move_down",y],["move_up",-y]]:
		if entry[1]>0.001: Input.action_press(entry[0],entry[1])
		else: Input.action_release(entry[0])

func _place(p: Vector3) -> void:
	_release()
	player.reset_motion(p+Vector3.UP*0.03)
	rig.snap_to_target()
	await _ticks(30)

func _walk(points: Array, label: String) -> void:
	phase = label
	var recovery_before: int = scene.recovery_count
	var start_ticks := Engine.get_physics_frames()
	var start_position := player.position
	var travelled := 0.0
	var last := player.position
	for target in points:
		var budget := ceili(player.position.distance_to(target)/5.0*60.0*2.0)+180
		var arrived := false
		for i in range(budget):
			var delta: Vector3 = target-player.global_position
			delta.y = 0
			if delta.length() < 0.36:
				arrived = true
				break
			_steer(delta.normalized())
			await _ticks(1)
			route_ticks += 1
			if not player.is_on_floor(): airborne_ticks += 1
			travelled += player.position.distance_to(last)
			last = player.position
			if scene.recovery_count != recovery_before: break
		_check(arrived,"%s reaches %s (actual %s)" % [label,target,player.position])
		if not arrived: break
	_release()
	await _ticks(20)
	_check(scene.recovery_count == recovery_before,label+" no unintended recovery")
	results[label] = {"seconds":(Engine.get_physics_frames()-start_ticks)/60.0,"travel_m":travelled,"start":str(start_position),"finish":str(player.position)}
	print("ROUTE ",label," ",results[label])

func _screenshot(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/images/m10_"+name+".png")

func _stats(label: String) -> void:
	if frames.is_empty(): return
	var sorted := frames.duplicate()
	sorted.sort()
	var physical := physics_times.duplicate()
	physical.sort()
	var total := 0.0
	for frame in frames: total += frame
	results[label] = {"samples":frames.size(),"fps":1000.0*frames.size()/total,"frame_p95_ms":sorted[int((sorted.size()-1)*0.95)],"frame_max_ms":sorted.back(),"physics_p95_ms":physical[int((physical.size()-1)*0.95)],"physics_max_ms":physical.back()}
	print("PERFORMANCE ",label," ",results[label])
	frames.clear()
	physics_times.clear()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	capture = "--capture" in args
	fast = "--fast" in args
	smoke = "--smoke" in args
	fps = 30 if "--30" in args else 60
	Engine.max_fps = 0 if fast else fps
	root.size = Vector2i(1152,720)
	var started := Time.get_ticks_msec()
	scene = load("res://scenes/maps/wind_hills/wind_hills_playground.tscn").instantiate()
	root.add_child(scene)
	player = scene.get_node("Player")
	field = scene.get_node("WindHills")
	rig = scene.get_node("CameraRig")
	print("BUILD milliseconds ",Time.get_ticks_msec()-started)
	await _ticks(90)
	_check(player.is_on_floor(),"spawn grounded")
	_check(player.combat != null and player.has_node("CombatFeedback"),"production combat connected")
	_check(rig.settings.pitch_angle == -45 and rig.settings.camera_distance == 10,"shared camera baseline")
	_check(field.get_node("Terrain").get_child_count()==195,"local occlusion chunks")
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	_check(is_equal_approx(shape.height,1.8) and is_equal_approx(shape.radius,0.3),"production capsule unchanged")
	results.environment = {"godot":Engine.get_version_info().string,"hash":Engine.get_version_info().hash,"os":OS.get_name(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":"1152x720","fps_cap":0 if fast else fps,"physics_hz":Engine.physics_ticks_per_second,"enemies":0,"fast":fast,"smoke":smoke}
	var main: Array = field.routes[0].points.duplicate()
	main.pop_front() # Start A, not the southern approach.
	var length := 0.0
	for i in range(main.size()-1):
		var a: Vector3 = main[i]
		var b: Vector3 = main[i+1]
		var prior := a
		for step in range(1,101):
			var p := a.lerp(b,step/100.0)
			p.y = field.height_at(p.x,p.z)
			length += prior.distance_to(p)
			prior = p
	results.main_design_length_m = length
	if smoke: main = main.slice(0,4)
	measuring = not fast
	await _walk(main,"main_up")
	main.reverse()
	await _walk(main,"main_down")
	if not smoke:
		var left: Array = field.routes[1].points
		await _place(left[0])
		await _walk(left,"left_loop")
		var river: Array = field.routes[2].points
		await _place(river[0])
		await _walk(river,"river_out")
		var reverse: Array = river.duplicate()
		reverse.reverse()
		await _walk(reverse,"river_back")
	measuring = false
	_stats("all_routes")
	# Held jump, active Guard, queued input and camera lock must be cleared by recovery.
	for p in [Vector3(0,-27,10),Vector3(95,-12,-65),Vector3(-10,-1,-80),Vector3(132,20,-100),Vector3(60,-17,-240)]:
		Input.action_press("guard")
		await _ticks(2)
		Input.action_press("jump")
		player.combat.queued = true
		rig.hold_follow()
		player.global_position = p
		var before: int = scene.recovery_count
		await _ticks(2)
		_check(scene.recovery_count>before,"map recovery from "+str(p))
		_check(not player.combat.queued and not rig.follow_locked,"recovery cancels queue and camera lock")
		_check(player.combat.state==player.combat.State.Idle,"recovery cancels Guard")
		_check(player.global_position.distance_to(field.get_node("PlayerSpawn").global_position)<0.2,"recovery returns to entrance")
		await _ticks(20)
		_check(player.position.y<0.1,"held jump suppressed after recovery")
		_release()
	# Actual jump/camera callbacks under the requested render cap.
	await _place(Vector3(0,0,8))
	Input.action_press("jump")
	await _ticks(1)
	Input.action_release("jump")
	var peak := player.position.y
	for i in range(70):
		await _ticks(1)
		peak = maxf(peak,player.position.y)
	_check(peak>1.0 and peak<1.4 and player.is_on_floor(),"normal jump and landing")
	results.jump_peak_m = peak
	for place in ["B","E","H","G","I","J"]:
		await _place(field.get_node(place).position)
		rig.rotation.y = 0
		rig.snap_to_target()
		await _ticks(60)
		await _screenshot(place.to_lower()+"_play")
		var original: Resource = rig.settings
		rig.settings = rig.settings.duplicate()
		rig.settings.pitch_angle = -24
		rig.settings.camera_distance = 12
		rig.arm.rotation.x = deg_to_rad(-24)
		rig.snap_to_target()
		await _ticks(30)
		await _screenshot(place.to_lower()+"_compare")
		rig.settings = original
		rig.arm.rotation.x = deg_to_rad(-45)
		for turn in range(4):
			Input.action_press("camera_right")
			await _ticks(54)
			Input.action_release("camera_right")
			_check(not rig.safety_failed and rig.camera.cull_mask!=0,"camera visible "+place+" turn "+str(turn))
		if not fast:
			phase = place
			frames.clear()
			physics_times.clear()
			measuring = true
			await _ticks(1800 if capture else 120)
			measuring = false
			_stats(place)
	if capture:
		await _place(Vector3.ZERO)
		overview = Camera3D.new()
		scene.add_child(overview)
		overview.position = Vector3(165,200,240)
		overview.look_at(Vector3(0,10,-115))
		overview.projection = Camera3D.PROJECTION_ORTHOGONAL
		overview.size = 280
		overview.far = 1800
		overview.make_current()
		rig.set_physics_process(false)
		rig.fader.restore_all()
		scene.get_node("HUD").visible = false
		scene.get_node("Guide").visible = false
		await _ticks(30)
		await _screenshot("overview")
	results.route_ticks = route_ticks
	results.airborne_ticks = airborne_ticks
	results.checks = checks
	results.failures = failures
	results.long_frames = long_frames
	var suffix := "fast" if fast else str(fps)
	var file := FileAccess.open("res://docs/measurements/m10_wind_hills_"+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("M10 ",checks," checks; failures ",failures.size())
	_release()
	quit(0 if failures.is_empty() else 1)
