extends "res://tests/enemy_terrain.gd"
## Production ranges are never narrowed. Movement-only trials disable AI instead.
var descent_rows: Array[Dictionary] = []

func _descent_actor(kind: int, at: Vector3, goal: Vector3, unlimited: bool, walking_only: bool) -> void:
	if is_instance_valid(ai):
		ai.clear_shots()
		ai.free()
	combat.cancel()
	health.heal(1000)
	player.reset_motion(goal if not walking_only else Vector3(-11,0,11))
	player.set_physics_process(false)
	ai = EnemyScene.instantiate()
	ai.settings = load("res://resources/enemies/melee_practice.tres" if kind == 0 else "res://resources/enemies/ranged_practice.tres").duplicate(true)
	ai.player = player
	ai.position = at
	ai.debug_unlimited_pursuit = unlimited
	main.add_child(ai)
	ai.set_physics_process(false)
	ai._set_state(ai.State.CHASE)
	await _ticks(3)
	ai.set_physics_process(not walking_only)

func _descent_trial(label: String, kind: int, at: Vector3, goal: Vector3, unlimited: bool, walking_only: bool, seconds: float = 5.0) -> Dictionary:
	await _descent_actor(kind,at,goal,unlimited,walking_only)
	var start := Engine.get_physics_frames()
	var lowest: float = at.y
	var reached := false
	var max_drop := 0.0
	var floating_warning := false
	var astar_frames := 0
	var previous: Vector3 = ai.global_position
	var previous_frame := Engine.get_physics_frames()
	for tick in range(int(seconds*60)):
		if walking_only:
			ai.walker.advance_cooldown(1.0/60.0)
			ai.walker.walk(goal,1.0/60.0,ai.settings.chase_speed)
		await _ticks(1)
		lowest = minf(lowest,ai.global_position.y)
		var steps := maxi(1,Engine.get_physics_frames()-previous_frame)
		max_drop = maxf(max_drop,(previous.y-ai.global_position.y)/steps)
		previous = ai.global_position
		previous_frame = Engine.get_physics_frames()
		if ai.state == ai.State.WINDUP and not ai.is_on_floor() and not ai.walker._can_land(): floating_warning = true
		if not ai._pursuit_route._search.is_empty(): astar_frames += 1
		var arrived: bool = absf(ai.global_position.y-goal.y)<0.08 and ai.walker.horizontal(ai.global_position,goal)<0.1
		var attacked: bool = ai.attack_count>0 and ai.state==ai.State.RECOVERY
		if (arrived if walking_only else attacked) and not ai.walker.busy():
			reached = true
			break
	var row: Dictionary = {"case":label,"kind":kind,"unlimited":unlimited,"walking_only":walking_only,"reached":reached,"position":str(ai.global_position),"lowest":lowest,"max_tick_drop":max_drop,"floating_warning":floating_warning,"astar_frames":astar_frames,"state":ai.State.keys()[ai.state],"motion":ai.walker.motion_mode,"move":ai.walker.blocked_reason,"route":ai._pursuit_route.reason,"attack":ai.attack_start_reason,"attacks":ai.attack_count,"ticks":Engine.get_physics_frames()-start,"reach":ai.engagement_range()}
	descent_rows.append(row)
	print("DESCENT ",JSON.stringify(row))
	return row

func _accept(row: Dictionary) -> void:
	_check(row.reached,"Movement or real attack completes: "+str(row))
	_check(not row.floating_warning,"No warning freezes an ordinary descent")
	_check(is_equal_approx(ai.engagement_range(),5.0 if row.kind==0 else 6.0),"Production engagement range is unchanged")
	_check(is_equal_approx(ai.active_attack.aim_lock_ratio,0.4 if row.kind==0 else 0.5),"Aim commitment is unchanged")
	if row.case=="map_stairs" and row.unlimited and not row.walking_only:
		_check(row.astar_frames==0,"Directly walkable descending stairs do not start A*")
	if String(row.case).begins_with("air_boundary"):
		_check(row.lowest<0.08,"Ordinary descent lands before a range-boundary attack")
	if row.walking_only:
		_check(ai.walker.jump_count==0,"Descending uses native walking/gravity, never an upward jump")
		_check(row.max_tick_drop<0.08,"Descending does not snap/warp down a high step")

func _return_trial() -> void:
	ai.debug_unlimited_pursuit=false
	ai.set_physics_process(true)
	_check(await _go_home(),"Formal home return retraces the descent and climbs safely")

func _recovery_trial(kind: int, unlimited: bool) -> void:
	var platform := _block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _descent_actor(kind,Vector3(5,1.001,0),Vector3(4,1.001,0),unlimited,false)
	await _state(ai.State.RECOVERY,240)
	_check(ai.attack_count==1,"Recovery test begins after a real, production-timed attack")
	var goal := Vector3(-3.8 if kind==0 else -4.8,0,0)
	player.reset_motion(goal)
	var before: int = ai.attack_count
	var down := false
	for tick in range(1200):
		await _ticks(1)
		down = down or ai.global_position.y<0.08
		if down and ai.attack_count>before: break
	_check(down and ai.attack_count>before,"Post-attack recovery resumes descent and a new attack: "+str(kind)+" / "+str(unlimited))
	platform.free()

func _safety_trials() -> void:
	for kind in [0,1]:
		var platform := _block(Vector3(4.5,0.5,0),Vector3(3,1,3))
		await _descent_actor(kind,Vector3(5,1.001,0),Vector3.ZERO,true,true)
		ai.settings.walk.maximum_step_down=0.4
		for tick in range(160):
			ai.walker.walk(Vector3.ZERO,1.0/60.0,2.0)
			await _ticks(1)
		_check(ai.position.x>3.2 and ai.position.y>0.98 and ai.walker.blocked,"A drop exceeding the per-enemy maximum is refused")
		ai.settings.walk.maximum_step_down=1.05
		ai.settings.walk.maximum_step_up=0.3
		_check(ai.walker.can_reach(Vector3(2,0,0)),"Descending height is independent of the smaller step-up limit")
		ai.settings.walk.maximum_step_up=1.05
		var floor_body: StaticBody3D=main.get_node("TestArena/Terrain/FlatGround")
		floor_body.collision_layer=0
		await _ticks(2)
		_check(not ai.walker.can_reach(Vector3(1,0,0)),"No route over a missing lower landing")
		for tick in range(100):
			ai.walker.walk(Vector3.ZERO,1.0/60.0,2.0)
			await _ticks(1)
		_check(ai.position.x>3.2 and ai.position.y>0.98,"No walk off a hole even in unlimited mode")
		floor_body.collision_layer=1
		platform.free()
		await _descent_actor(kind,Vector3(2.8,1.001,5),Vector3(-4,0,5),true,true)
		# Real upper stair to next tread, with an added solid wall in the route.
		var wall := _block(Vector3(-0.2,1.5,5),Vector3(0.2,3,3))
		await _ticks(2)
		_check(not ai.walker.can_reach(Vector3(-2,0.25,5)),"Downward floor contact never authorizes a wall crossing")
		wall.free()
	# The recognition ray at +0.8m passes below this small obstacle; the
	# actual firing line at +0.9m is blocked. Being inside 6m must not park AI.
	await _descent_actor(1,Vector3(-5,0,8),Vector3(-1,0,8),true,true)
	player.reset_motion(Vector3(-1,0,8))
	var beam := _block(Vector3(-3,0.9,8),Vector3(0.1,0.04,0.5))
	await _ticks(2)
	_check(ai.has_sight() and not ai._attack_position_available(),"Sight and actual projectile firing clearance are distinct")
	ai._ranged_chase_step(1.0/60.0,4.0,true,true)
	_check(ai.state==ai.State.CHASE and ai._ranged_pursuit_active,"Blocked firing path pursues instead of entering warning/parking inside range")
	beam.free()

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode = 0
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(5)
	if "--boundary-only" in OS.get_cmdline_user_args():
		await _air_boundaries()
		_save_descent()
		return
	if "--safety-only" in OS.get_cmdline_user_args():
		await _safety_trials()
		_save_descent()
		return
	var probe := "--probe" in OS.get_cmdline_user_args()
	var arena: Node3D = main.get_node("TestArena")
	for kind in [0,1]:
		for walking_only in [true,false]:
			for unlimited in [false,true]:
				var row := await _descent_trial("map_stairs",kind,arena.to_global(Vector3(5,1.001,-3.3)),arena.to_global(Vector3(5,0,5.5)),unlimited,walking_only,8.0)
				if not probe: _accept(row)
		for local_start in [Vector3(5,0.501,-1),Vector3(-6,2.001,-7)]:
			var ramp: bool = local_start.x<0.0
			var goal := arena.to_global(Vector3(-6,0,0.5) if ramp else Vector3(5,0,3))
			var row := await _descent_trial("map_ramp" if ramp else "mid_stairs",kind,arena.to_global(local_start),goal,true,true,6.0)
			if not probe: _accept(row)
	if "--map-only" in OS.get_cmdline_user_args():
		_save_descent()
		return
	for kind in [0,1]:
		for height in ([1.0] if probe else [0.25,0.5,1.0]):
			var platform := _block(Vector3(4.5,height*0.5,0),Vector3(3,height,3))
			for walking_only in [true,false]:
				for unlimited in [false,true]:
					var row := await _descent_trial("single_"+str(height),kind,Vector3(5,height+0.001,0),Vector3.ZERO,unlimited,walking_only)
					if not probe: _accept(row)
					if walking_only and not unlimited and not probe: await _return_trial()
			platform.free()
	if not probe:
		await _air_boundaries()
		for kind in [0,1]:
			for unlimited in [false,true]: await _recovery_trial(kind,unlimited)
		await _safety_trials()
	_save_descent()

func _air_boundaries() -> void:
	var platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	for kind in [0,1]:
		for unlimited in [false,true]:
			for offset in [-0.2,-0.1,0.0,0.1,0.2]:
				var goal:=Vector3((-2.4 if kind==0 else -3.4)-offset,0,0)
				var row:=await _descent_trial("air_boundary_"+str(offset),kind,Vector3(5,1.001,0),goal,unlimited,false,6.0)
				_accept(row)
	platform.free()

func _save_descent() -> void:
	var args := OS.get_cmdline_user_args()
	var label: String = args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/descent_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(descent_rows,"  "))
	for failure in failures: push_error(failure)
	print("ENEMY DESCENT ","PASS" if failures.is_empty() else "FAIL"," ",assertions)
	main.free()
	quit(0 if failures.is_empty() else 1)
