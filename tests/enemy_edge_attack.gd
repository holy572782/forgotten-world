extends "res://tests/enemy_descent.gd"
var edge_rows: Array[Dictionary]=[]

func _position_performance() -> void:
	var rows: Array[Dictionary]=[]
	var config: Resource=main.get_node("PracticeSelector").performance_diagnostics
	main.get_node("PracticeSelector").set_process(false)
	for kind in [0,1]:
		for enclosed in [false,true]:
			await _edge_actor(kind,Vector3(0,0,8),Vector3(4,0,8))
			player.set_physics_process(true) # Include the real player/target preview workload.
			ai.performance_diagnostics=config
			config.capture_timings=true
			var walls: Array[Node]=[]
			if enclosed:
				for entry in [[Vector3(1,1.5,8),Vector3(0.2,3,4)],[Vector3(-1,1.5,8),Vector3(0.2,3,4)],[Vector3(0,1.5,6),Vector3(2,3,0.2)],[Vector3(0,1.5,10),Vector3(2,3,0.2)]]: walls.append(_block(entry[0],entry[1]))
			else: walls.append(_block(Vector3(2,0.7,8),Vector3(0.35,1.4,1.6)))
			main.get_node("CameraRig").snap_to_target()
			await _ticks(3)
			ai.set_physics_process(true)
			config.reset()
			var started:=Time.get_ticks_usec()
			var previous:=started
			var frames: Array[float]=[]
			var physics: Array[float]=[]
			var states: Dictionary={}
			while Time.get_ticks_usec()-started<3000000:
				await process_frame
				var now:=Time.get_ticks_usec()
				frames.append(float(now-previous)/1000.0)
				physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
				states[ai.state]=states.get(ai.state,0)+1
				previous=now
			var seconds:=float(Time.get_ticks_usec()-started)/1000000.0
			frames.sort(); physics.sort()
			var row: Dictionary={"kind":kind,"enclosed":enclosed,"seconds":seconds,"fps":frames.size()/seconds,"frame_max_ms":frames[-1],"physics_p95_ms":physics[int(physics.size()*0.95)],"states":states,"attacks":ai.attack_count,"position":str(ai.global_position),"position_reason":ai._pursuit_route.position_reason,"timings":config.timings.duplicate(true)}
			rows.append(row)
			print("POSITION PERF ",JSON.stringify(row))
			ai.set_physics_process(false)
			for wall in walls: wall.free()
	FileAccess.open("res://.godot/edge_position_performance.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	await _finish_edge()

func _edge_actor(kind: int, at: Vector3, goal: Vector3, unlimited: bool=true) -> void:
	await _descent_actor(kind,at,goal,unlimited,false)
	ai.set_physics_process(false)
	ai.show_attack_diagnostics=true
	ai.global_position=_native_floor(ai,at)
	ai.home=ai.global_position
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	player.reset_motion(_native_floor(player,goal))
	await _ticks(2)

func _native_floor(body: CharacterBody3D, at: Vector3) -> Vector3:
	var above:=at+Vector3.UP*3.0
	var hit:=KinematicCollision3D.new()
	_check(body.test_move(Transform3D(body.global_basis,above),Vector3.DOWN*6.0,hit,body.safe_margin),"Native fixture has a floor")
	return above+hit.get_travel()

func _record_edge(label: String) -> void:
	if not ai.aim_locked: ai.facing=ai._horizontal_direction(player.global_position)
	var row: Dictionary={"case":label,"position":str(ai.global_position),"target":str(player.global_position),"sight":ai.has_sight(),"available":ai._attack_position_available(),"hit":ai.melee_hits() if ai.active_attack.weapon!=null else ai._projectile_path_clear(player.global_position),"start":ai.attack_start_reason,"abort":ai.attack_abort_reason,"position_reason":ai._pursuit_route.position_reason if "position_reason" in ai._pursuit_route else "legacy","attacks":ai.attack_count,"hp":health.current_hp,"state":ai.State.keys()[ai.state]}
	edge_rows.append(row)
	print("EDGE ATTACK ",JSON.stringify(row))

func _strike(label: String, expected_hit: bool) -> void:
	_check(ai._attack_position_available(),"In-place start ignores body corridor: "+label)
	ai._start_windup()
	ai.set_physics_process(true)
	await _state(ai.State.RECOVERY,240)
	_check(ai.attack_count==1,"One completed attack: "+label)
	_check(health.current_hp==(90.0 if expected_hit else 100.0),"Actual segment-based damage: "+label)
	_record_edge(label)

func _terrain_cases() -> void:
	var arena: Node3D=main.get_node("TestArena")
	var pairs: Array=[
		["flat",Vector3(-4,0,4),Vector3(-4,0,5.7)],
		["ramp_bottom",Vector3(-6,0,-0.5),Vector3(-6,0,-2)],
		["ramp_middle",Vector3(-6,0,-2.4),Vector3(-6,0,-4)],
		["ramp_top",Vector3(-6,0,-5.4),Vector3(-6,2,-7)],
		["stair_top_down",Vector3(5,1,-3.3),Vector3(5,0.5,-1.2)],
		["stair_top_up",Vector3(5,0.5,-1.2),Vector3(5,1,-3.3)],
		["stair_side_up",Vector3(7.5,0,-3),Vector3(6.3,1,-3)],
		["stair_side_down",Vector3(6.3,1,-3),Vector3(7.5,0,-3)]]
	for kind in [0,1]:
		for unlimited in [false,true]:
			for pair in pairs:
				var label: String=pair[0]+" / "+str(kind)+" / "+str(unlimited)
				await _edge_actor(kind,arena.to_global(pair[1]),arena.to_global(pair[2]),unlimited)
				_check(is_equal_approx(ai.engagement_range(),5.0 if kind==0 else 6.0),"Production range: "+label)
				_check(is_equal_approx(ai.active_attack.aim_lock_ratio,0.4 if kind==0 else 0.5),"Production aim ratio: "+label)
				if kind==0: await _strike(label,true)
				else:
					_check(ai.has_sight() and ai._projectile_path_clear(player.global_position),"Mage actual sphere path: "+label)
					ai.set_physics_process(true)
					await _state(ai.State.RECOVERY,200)
					await _ticks(45)
					_check(ai.attack_count==1 and health.current_hp==90,"One real MAGIC hit: "+label)
					_record_edge(label)

func _unsafe_and_debug() -> void:
	for kind in [0,1]:
		await _edge_actor(kind,Vector3(0,0,8),Vector3(2,0,8))
		var walls: Array[Node]=[]
		for entry in [[Vector3(1,1.5,8),Vector3(0.2,3,4)],[Vector3(-1,1.5,8),Vector3(0.2,3,4)],[Vector3(0,1.5,6),Vector3(2,3,0.2)],[Vector3(0,1.5,10),Vector3(2,3,0.2)]]:
			walls.append(_block(entry[0],entry[1]))
		await _ticks(2)
		_check(not ai.has_sight() and not ai._attack_position_available(),"Full wall denies recognition/entry")
		ai.set_physics_process(true)
		await _ticks(240)
		_check(ai.attack_count==0 and absf(ai.position.x)<0.5 and absf(ai.position.z-8)<1.5,"Impossible route stops inside enclosure")
		_check(ai.velocity.length()<0.01,"Failed route does not run forever")
		_record_edge("C blocked enclosure / "+str(kind))
		for wall in walls: wall.free()
	await _edge_actor(0,Vector3(0,0,8),Vector3(4,0,8))
	ai._availability_origin=ai.global_position
	ai._availability_target=player.global_position
	ai._eligibility_job={"started":Time.get_ticks_usec()-3000000}
	ai._update_attack_debug()
	_check(ai.debug_label.text.contains("PLANNING_STALLED") and ai.debug_label.text.contains("ABORT(last)"),"Pending age/history are explicit")
	ai._eligibility_job.clear()
	player.reset_motion(Vector3(10,0,8))
	ai._update_attack_debug()
	_check(ai.debug_label.text.contains("OUT_OF_RANGE") and not ai.debug_label.text.contains("PLANNING_STALLED"),"Current readiness never keeps an old pending label")

func _run() -> void:
	Engine.max_fps=30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size=Vector2i(1152,720)
	main=load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode=0
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(4)
	var probe: bool="--probe" in OS.get_cmdline_user_args()
	if "--position-perf" in OS.get_cmdline_user_args():
		await _position_performance()
		return
	if "--terrain-only" in OS.get_cmdline_user_args():
		await _terrain_cases()
		await _finish_edge()
		return
	await _edge_actor(0,Vector3(0,0.001,8),Vector3(2,0.001,8))
	var behind:=_block(Vector3(2.45,0.6,8),Vector3(0.2,1.2,2))
	await _ticks(2)
	if probe: _record_edge("wall behind target")
	else: await _strike("wall behind target",true)
	behind.free()
	await _edge_actor(0,Vector3(0,0.001,8),Vector3(2,0.001,8))
	var blocker:=_block(Vector3(1,0.6,8),Vector3(0.2,1.2,2))
	await _ticks(2)
	if probe: _record_edge("hand blocked, head visible")
	else: await _strike("hand blocked, head visible",false)
	blocker.free()
	await _edge_actor(1,Vector3(0,0.001,8),Vector3(4,0.001,8))
	var graze:=_block(Vector3(2,0.9,8.22),Vector3(0.2,0.4,0.1))
	await _ticks(2)
	if probe: _record_edge("projectile radius graze")
	else:
		_check(ai.has_sight() and not ai._projectile_path_clear(player.global_position),"Projectile radius blocks a clear centre ray")
		_record_edge("projectile radius graze")
	graze.free()
	if not probe:
		for kind in [0,1]:
			await _edge_actor(kind,Vector3(0,0.001,8),Vector3(4,0.001,8))
			var wall:=_block(Vector3(2,0.7,8),Vector3(0.35,1.4,1.6))
			await _ticks(2)
			ai.set_physics_process(true)
			var side_travel:=0.0
			for tick in range(800):
				await _ticks(1)
				side_travel=maxf(side_travel,absf(ai.global_position.z-8.0))
				if health.current_hp<100: break
			_check(health.current_hp==90 and side_travel>0.4,"Safe lateral approach and actual hit: "+str(kind))
			_record_edge("detour "+str(kind))
			wall.free()
		await _unsafe_and_debug()
		if not "--quick" in OS.get_cmdline_user_args(): await _terrain_cases()
	await _finish_edge()

func _finish_edge() -> void:
	var probe: bool="--probe" in OS.get_cmdline_user_args()
	var args:=OS.get_cmdline_user_args()
	var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/edge_attack_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(edge_rows,"  "))
	for failure in failures: push_error(failure)
	print("EDGE ATTACK ","PROBE" if probe else ("PASS" if failures.is_empty() else "FAIL")," ",assertions)
	ai.clear_shots()
	main.queue_free()
	await _ticks(3)
	for node in get_nodes_in_group("combat_one_shot_audio"): node.queue_free()
	await _ticks(2)
	quit(0 if failures.is_empty() else 1)
