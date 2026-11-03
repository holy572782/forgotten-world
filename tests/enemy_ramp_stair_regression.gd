extends "res://tests/enemy_edge_attack.gd"
## Production AI versus the same mover alone; never narrow combat ranges.
var regression_rows: Array[Dictionary]=[]

func _motion_trial(label: String, kind: int, start: Vector3, goal: Vector3, unlimited: bool, walking_only: bool) -> void:
	await _edge_actor(kind,start,goal,unlimited)
	var initial: Vector3=ai.global_position
	var target: Vector3=player.global_position
	var measuring: bool="--performance" in OS.get_cmdline_user_args()
	if measuring:
		player.set_physics_process(true)
		main.get_node("CameraRig").snap_to_target()
		ai.performance_diagnostics=main.get_node("PracticeSelector").performance_diagnostics
		ai.performance_diagnostics.capture_timings=true
		ai.performance_diagnostics.reset()
	if walking_only: player.reset_motion(Vector3(12,0,12))
	else: ai.set_physics_process(true)
	var peak:=initial.y
	var low:=initial.y
	var samples: Array[Dictionary]=[]
	var completed:=false
	var unsafe_motion:=false
	var previous: Vector3=initial
	var previous_tick:=Engine.get_physics_frames()
	var began:=Time.get_ticks_usec()
	var first_frame:=Engine.get_process_frames()
	var physics_times: Array[float]=[]
	for tick in range(180 if measuring else 480):
		if walking_only:
			ai.walker.advance_cooldown(1.0/60.0)
			ai.walker.walk(target,1.0/60.0,ai.settings.chase_speed)
		await _ticks(1)
		if measuring: physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		var dt: float=float(maxi(1,Engine.get_physics_frames()-previous_tick))/60.0
		unsafe_motion=unsafe_motion or (ai.global_position-previous).length()>maxf(7.4,ai.settings.walk.climb_speed)*dt+0.03
		previous=ai.global_position; previous_tick=Engine.get_physics_frames()
		peak=maxf(peak,ai.global_position.y)
		low=minf(low,ai.global_position.y)
		if tick%60==0:
			samples.append({"tick":tick,"at":str(ai.global_position),"state":ai.State.keys()[ai.state],"mode":ai.walker.motion_mode,"move":ai.walker.blocked_reason,"route":ai._pursuit_route.reason,"position":ai._pursuit_route.position_reason,"ready":ai._current_readiness(),"land":ai.walker._can_land()})
		completed=(ai.walker.horizontal(ai.global_position,target)<0.15 and absf(ai.global_position.y-target.y)<0.1 and not ai.walker.busy()) if walking_only else (ai.attack_count>0 and ai.state==ai.State.RECOVERY and not ai.walker.busy())
		if completed and not measuring: break
	var row: Dictionary={"case":label,"kind":kind,"unlimited":unlimited,"walking_only":walking_only,"completed":completed,"start":str(initial),"target":str(target),"end":str(ai.global_position),"peak":peak,"lowest":low,"jumps":ai.walker.jump_count,"attacks":ai.attack_count,"hp":health.current_hp,"samples":samples}
	if measuring:
		physics_times.sort()
		row["seconds"]=float(Time.get_ticks_usec()-began)/1000000.0
		row["fps"]=(Engine.get_process_frames()-first_frame)/row.seconds
		row["physics_p95_ms"]=physics_times[int(physics_times.size()*0.95)]
		row["timings"]=ai.performance_diagnostics.timings.duplicate(true)
	regression_rows.append(row)
	print("RAMP STAIR ",JSON.stringify(row))
	if not completed and walking_only:
		var direction: Vector3=Vector3(target.x-ai.global_position.x,0,target.z-ai.global_position.z).normalized()
		var w=ai.walker
		var height: float=w.config.jump_height; var takeoff: float=w.config.jump_takeoff_speed; var speed: float=w.config.jump_horizontal_speed
		var hit: Dictionary=w.floor_hit(ai,ai.global_position+direction*0.6,height+0.05,0.05)
		if not hit.is_empty():
			var duration: float=w.Arc.flight_time(height,takeoff,hit.position.y-ai.global_position.y+0.003)
			var landing: Vector3=ai.global_position+direction*speed*duration
			landing.y=hit.position.y+0.003
			print("JUMP DETAIL ",JSON.stringify({"hit":str(hit.position),"landing":str(landing),"support":w._support(landing,true),"corridor":w._jump_corridor(landing),"arc0":w.Arc.clear(ai,ai.global_position,direction,speed,takeoff,w.Arc.gravity(height,takeoff),duration),"arc1":w.Arc.clear(ai,ai.global_position,direction,speed,takeoff,w.Arc.gravity(height,takeoff),duration,1)}))
	if not "--probe" in OS.get_cmdline_user_args() and not measuring:
		var unsafe_outward: bool=label=="ramp_edge_outward" and walking_only
		if unsafe_outward: _check(not completed and ai.global_position.y>1.2 and ai.walker.blocked and ai.velocity.is_zero_approx(),"Mover alone refuses an unsupported route off the ramp side")
		else: _check(completed,"Mover or production attack completes: "+label+str(kind)+str(unlimited)+str(walking_only))
		if label.begins_with("ramp"): _check(ai.walker.jump_count==0,"Walkable ramp never needs a jump")
		if walking_only: _check(not unsafe_motion,"Native walking/jump is time-based without a warp")
		_check(is_equal_approx(ai.active_attack.aim_lock_ratio,0.4 if kind==0 else 0.5),"User aim ratios remain unchanged")
	ai.set_physics_process(false)

func _run() -> void:
	Engine.max_fps=30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size=Vector2i(1152,720)
	main=load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode=0
	root.add_child(main)
	player=main.get_node("Player"); combat=player.combat; sprite=player.get_node("AnimatedSprite3D"); health=player.get_node("HealthComponent")
	main.get_node("HUD").hide()
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(4)
	var arena: Node3D=main.get_node("TestArena")
	var cases=[
		["stairs_up",Vector3(5,0,3),Vector3(5,1,-3.3)],
		["stairs_down",Vector3(5,1,-3.3),Vector3(5,0,3)],
		["ramp_up",Vector3(-6,0,0.5),Vector3(-6,2,-7)],
		["ramp_down",Vector3(-6,2,-7),Vector3(-6,0,2)]
	]
	if not "--edges" in OS.get_cmdline_user_args() and not "--diagonal" in OS.get_cmdline_user_args():
		cases.append(["stairs_tight",Vector3(5,0,-1.55),Vector3(5,1,-3.3)])
		cases.append(["stairs_tight_diagonal",Vector3(5,0,-1.55),Vector3(6.7,1,-3.7)])
		cases.append(["ramp_edge_inward",Vector3(-7.9,0,-4.5),Vector3(-6,0,3)])
		cases.append(["ramp_edge_outward",Vector3(-7.5,0,-4.5),Vector3(-9,0,3)])
	if "--edges" in OS.get_cmdline_user_args():
		cases=[]
		for z in [0.7,-0.3,-1.3,-1.55,-1.7]: cases.append(["stairs_close_"+str(z),Vector3(5,0,z),Vector3(5,1,-3.3)])
		for x in [3.2,6.8,7.4]: cases.append(["stairs_side_"+str(x),Vector3(x,0,1),Vector3(5,1,-3.3)])
		for z in [-5.5,-4.0,-2.0,-0.2]: cases.append(["ramp_mid_down_"+str(z),Vector3(-6,0,z),Vector3(-6,0,3)])
	if "--diagonal" in OS.get_cmdline_user_args():
		cases=[]
		for x in [-7.9,-7.5,-6.0,-4.5,-4.1]:
			for target_x in [-9.0,-6.0,-3.0]: cases.append(["ramp_diagonal_"+str(x)+"_"+str(target_x),Vector3(x,0,-4.5),Vector3(target_x,0,3)])
	for kind in [0,1]:
		if "--diagonal" in OS.get_cmdline_user_args() and kind==0: continue
		for entry in cases:
			if "--central" in OS.get_cmdline_user_args() and entry[0] not in ["stairs_up","stairs_down","ramp_up","ramp_down"]: continue
			if "--performance" in OS.get_cmdline_user_args() and entry[0] not in ["stairs_tight_diagonal","ramp_edge_outward"]: continue
			if "--focus" in OS.get_cmdline_user_args() and entry[0] in ["stairs_up","stairs_down","ramp_up","ramp_down"]: continue
			if "--edges" in OS.get_cmdline_user_args() and ((kind==0 and String(entry[0]).begins_with("ramp")) or (kind==1 and String(entry[0]).begins_with("stairs"))): continue
			if not "--performance" in OS.get_cmdline_user_args(): await _motion_trial(entry[0],kind,arena.to_global(entry[1]),arena.to_global(entry[2]),true,true)
			for unlimited in [false,true]:
				await _motion_trial(entry[0],kind,arena.to_global(entry[1]),arena.to_global(entry[2]),unlimited,false)
	var args:=OS.get_cmdline_user_args()
	var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/ramp_stair_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(regression_rows,"  "))
	print("RAMP STAIR RESULT ","PROBE" if "--probe" in args else ("PASS" if failures.is_empty() else "FAIL")," ",assertions)
	await _finish_edge()
