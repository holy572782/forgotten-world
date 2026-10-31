extends "res://tests/enemy_terrain.gd"
const Probe=preload("res://tests/fixtures/pursuit_query_probe.gd")
var perf_measurements: Array[Dictionary]=[]
func _wall_seconds(seconds: float) -> void:
	var start:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-start<seconds*1000000.0: await process_frame
func _measure(label: String) -> void:
	await _wall_seconds(0.8)
	Probe.reset()
	Probe.enabled=true
	var native_profile:=OS.get_cmdline_user_args().has("--native-profile") and EngineDebugger.has_profiler("scripts")
	if native_profile:
		print("PROFILE CASE BEGIN ",label)
		EngineDebugger.profiler_enable("scripts",true)
	var start:=Time.get_ticks_usec()
	var last:=start
	var frames: Array[float]=[]
	var physics: Array[float]=[]
	while Time.get_ticks_usec()-start<3000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		frames.append(float(now-last)/1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		last=now
	Probe.enabled=false
	if native_profile:
		print("PROFILE CASE END ",label)
		EngineDebugger.profiler_enable("scripts",false)
	frames.sort()
	physics.sort()
	var seconds:=float(Time.get_ticks_usec()-start)/1000000.0
	var queries:=0.0
	for key in ["ray","shape","cast","contacts","motion"]: queries+=Probe.counts.get(key,0.0)
	var row: Dictionary={"case":label,"seconds":seconds,"fps":frames.size()/seconds,"frame_p95_ms":frames[int(frames.size()*0.95)],"frame_max_ms":frames[-1],"physics_p95_ms":physics[int(physics.size()*0.95)],"queries_per_second":queries/seconds,"counters":Probe.counts.duplicate(),"state":ai.State.keys()[ai.state] if is_instance_valid(ai) else "NONE","reason":ai._pursuit_route.reason if is_instance_valid(ai) else ""}
	perf_measurements.append(row)
	print("PURSUIT PERF ",JSON.stringify(row))
func _run() -> void:
	if EngineDebugger.is_profiling("scripts"): EngineDebugger.profiler_enable("scripts",false)
	Engine.max_fps=60
	root.size=Vector2i(1152,720)
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.hide(); child.collision_layer=0
	await _ticks(5)
	player.reset_motion(Vector3(-6,0,0))
	player.set_physics_process(false)
	main.get_node("CameraRig").snap_to_target()
	main.get_node("CameraRig").set_physics_process(false)
	await _measure("flat_no_enemy")
	for unlimited in [false,true]:
		await _fresh_sword(4.5)
		ai.global_position=Vector3(-2.7,0,5)
		ai.home=ai.global_position
		player.global_position=Vector3(3.3,1,5)
		ai.debug_unlimited_pursuit=unlimited
		ai.show_attack_diagnostics=true
		main.get_node("CameraRig").snap_to_target()
		ai.set_physics_process(true)
		await _measure("stairs_on" if unlimited else "stairs_off")
	await _fresh_sword(4.5)
	ai.global_position=Vector3(0.9,0.5,5)
	ai.home=ai.global_position
	player.global_position=Vector3(3.3,1,5)
	ai.debug_unlimited_pursuit=true
	ai.show_attack_diagnostics=true
	var wall:=_block(Vector3(1.6,1.2,5),Vector3(0.25,1.4,20))
	main.get_node("CameraRig").snap_to_target()
	ai.set_physics_process(true)
	await _measure("blocked_stairs")
	wall.free()
	await _fresh_sword(4.5)
	var arena: Node3D=main.get_node("TestArena")
	ai.global_position=arena.to_global(Vector3(-6,0,0.1))
	ai.home=ai.global_position
	player.global_position=arena.to_global(Vector3(-6,2,-7))
	ai.debug_unlimited_pursuit=true
	main.get_node("CameraRig").snap_to_target()
	ai.set_physics_process(true)
	await _measure("ramp_on")
	var args:=OS.get_cmdline_user_args()
	var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/pursuit_perf_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(perf_measurements,"  "))
	main.queue_free()
	await _ticks(3)
	quit()

