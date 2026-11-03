extends "res://tests/enemy_search_detour.gd"
const PolicyRoute=preload("res://scripts/enemies/enemy_pursuit_route.gd")
var policy_rows: Array[Dictionary]=[]

func _vision(kind: int) -> void:
	await _actor(kind,false)
	ai._set_state(ai.State.IDLE); ai.facing=Vector3.RIGHT
	var radius: float=5.0 if kind==0 else 12.0
	_check(ai.settings.detection_radius==radius,"Official acquisition radius differs from combat and home ranges")
	player.reset_motion(ai.position+Vector3.RIGHT*radius)
	_check(ai.has_sight(),"Front target at exact detection distance has an unobstructed view")
	_check(ai._can_acquire(true,radius)==(kind==0),"Mage 12m perception still respects the default 10m home")
	ai.settings.leash_radius=radius+1.0 # Isolate the detection boundary from home.
	_check(ai._can_acquire(ai.has_sight(),radius),"Exact 5m/12m front boundary can acquire with a valid home")
	_check(not ai._can_acquire(true,radius+0.01),"New acquisition rejects beyond configured radius")
	for degrees in [-60.0,60.0]:
		var at: Vector3=ai.position+Vector3.RIGHT.rotated(Vector3.UP,deg_to_rad(degrees))*3.0
		_check(ai._in_view_cone(at),"Horizontal half-FOV includes 60 degrees")
	for degrees in [-60.5,60.5,180.0]:
		var at: Vector3=ai.position+Vector3.RIGHT.rotated(Vector3.UP,deg_to_rad(degrees))*3.0
		_check(not ai._in_view_cone(at),"New acquisition excludes horizontal out-of-cone targets")
	for degrees in [-40.0,40.0,-40.5,40.5]:
		var at: Vector3=ai.position+Vector3(3.0,tan(deg_to_rad(degrees))*3.0,0.0)
		_check(ai._in_view_cone(at)==(absf(degrees)<=40.0),"Vertical FOV uses the independent plus/minus 40 degree boundary")
	player.reset_motion(ai.position+Vector3.RIGHT*4.0)
	var wall:=_block(ai.position+Vector3(2,1.5,0),Vector3(0.3,3,3))
	await _ticks(2)
	_check(not ai.has_sight(),"Opaque wall prevents initial recognition despite valid range/cone")
	wall.free(); await _ticks(2)
	ai.settings.leash_radius=9.0 if kind==0 else 10.0
	player.reset_motion(ai.position+Vector3.RIGHT*(5.5 if kind==0 else 7.0))
	ai._set_state(ai.State.CHASE); ai.cooldown=1000.0; ai.set_physics_process(true)
	await _ticks(6)
	_check(ai.state==ai.State.CHASE and ai._search_behavior.phase.is_empty(),"An acquired visible target stays tracked outside initial melee detection radius")
	ai.set_physics_process(false)
	player.reset_motion(ai.position+Vector3.RIGHT*1.2); ai.facing=Vector3.RIGHT
	ai._set_state(ai.State.RETURN); ai.set_physics_process(true); await _ticks(2)
	_check(ai.state==ai.State.CHASE and not ai.walker.returning,"RETURN reacquires only through the same range/cone/home conditions")
	ai.set_physics_process(false)
	policy_rows.append({"case":"vision","kind":kind,"radius":radius,"horizontal":120.0,"vertical":80.0})

func _compare_sides(kind: int, mirror: bool, blocked_shorter: bool=false) -> void:
	await _actor(kind,true)
	# main's rotated ramp touches (0, 0, 8). Compare both sides on genuinely
	# flat terrain; slope/corner behavior has a separate native-map regression.
	ai.global_position=_native_floor(ai,Vector3(5,0,8)); ai.home=ai.global_position
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	player.reset_motion(_native_floor(player,Vector3(9,0,8)))
	var wall:=_block(Vector3(7,1.5,8.75 if mirror else 7.25),Vector3(0.3,3,3.5))
	var extension: Node3D
	if blocked_shorter: extension=_block(Vector3(7,1.5,6.0 if mirror else 10.0),Vector3(0.3,3,2.0))
	await _ticks(2)
	# Use the same body stand-off as production goal(); the player's occupied
	# center is deliberately not a valid landing/graph endpoint.
	var destination: Vector3=ai.global_position+Vector3.RIGHT*3.15
	var route:=PolicyRoute.new(); route.target=destination
	route._begin_search(ai,destination)
	for tick in range(900):
		route._advance_search(ai)
		if route._search.is_empty(): break
		await _ticks(1)
	var side:=0.0
	for point in route.waypoints:
		if absf(point.z-8.0)>absf(side): side=point.z-8.0
	var expected: float=(-1.0 if mirror else 1.0)*(-1.0 if blocked_shorter else 1.0)
	_check(not route.waypoints.is_empty() and side*expected>0.5,"Shared A* compares both safe sides and avoids the extended obstructed side")
	_check(route.selected_cost>3.0 and route.selected_cost<10.0,"Selected cost is actual safe-edge length, not initial heading")
	policy_rows.append({"case":"shorter_side","kind":kind,"mirror":mirror,"blocked_shorter":blocked_shorter,"side":side,"cost":route.selected_cost,"points":str(route.waypoints)})
	if not route.waypoints.is_empty():
		var retained:=PolicyRoute.new(); retained.waypoints.assign(route.waypoints)
		var original: Vector3=player.global_position
		retained._position={"target":original,"phase":2,"goal":route.waypoints[-1],"travelling":false}
		player.reset_motion(original+Vector3.BACK*1.2)
		retained.combat_goal(ai,1.0/60.0)
		_check(not retained.waypoints.is_empty() and retained.waypoints[0]==route.waypoints[0],"A moving target does not discard an already safe positioning detour")
		player.reset_motion(original)
	ai._pursuit_route=route; ai.set_physics_process(true)
	for tick in range(600):
		await _ticks(1)
		if health.current_hp<100: break
	_check(health.current_hp==90,"Chosen asymmetric detour reaches real combat using the native capsule")
	ai.set_physics_process(false); wall.free()
	if is_instance_valid(extension): extension.free()

func _stall(kind: int) -> void:
	await _actor(kind,true)
	var route: RefCounted=ai._pursuit_route
	var from: Vector3=ai.global_position
	var goal: Vector3=from+Vector3.RIGHT*0.75
	route.waypoints.assign([goal])
	ai.walker.blocked=true; ai.walker.blocked_reason="STEP_OR_JUMP_UNSAFE"
	for tick in range(3):
		route.observe_move(ai,goal,from,0.4)
		await _ticks(24)
	_check(route.stall_count==1 and route.waypoints.is_empty(),"Repeated rejected real-motion reports invalidate a stalled waypoint")
	_check(route._rejected_edge(from,goal) and not route._rejected_edge(from,from+Vector3.BACK),"Failed approach is temporarily rejected while safe side directions stay available")
	var count: int=route.stall_count
	ai.walker.blocked_reason="JUMP_COOLDOWN"
	for tick in range(4): route.observe_move(ai,goal,from,0.5)
	_check(route.stall_count==count,"Normal jump cooldown never counts as stalled motion")
	route.pause_progress(); ai.walker.blocked_reason="STEP_OR_JUMP_UNSAFE"
	route.observe_move(ai,goal,from,0.016)
	_check(route.stall_count==count,"Planning/combat pause clears the progress window")
	# A budget pause must not repeatedly erase the same failed real attempt.
	var pending:=PolicyRoute.new()
	ai.walker.retry=0.5
	for tick in range(3):
		pending.planning_wait()
		pending.observe_move(ai,goal,from,0.016)
	_check(pending.stall_count==1,"Budget waits exclude their time but retain actual mover rejection history")
	ai.walker.retry=0.0
	# Real safe planner must route around the temporarily rejected forward edge.
	route._begin_search(ai,from+Vector3.RIGHT*3.0)
	for tick in range(600):
		route._advance_search(ai)
		if route._search.is_empty(): break
		await _ticks(1)
	_check(not route.waypoints.is_empty() and absf(route.waypoints[0].z-from.z)>0.5,"Replanning takes an alternative safe first edge instead of repeating the failed approach")
	ai.walker.blocked=false; ai.walker.blocked_reason=""
	policy_rows.append({"case":"stall","kind":kind,"count":route.stall_count,"reason":route.last_stall_reason,"alternative":str(route.waypoints)})

func _deadline(kind: int) -> void:
	await _actor(kind,false,true)
	ai.sight_override=0; ai.cooldown=1000.0
	# Old exported values must not create competing deadlines in saved resources.
	ai.settings.sight_loss_seconds=0.5; ai.settings.search_duration_seconds=0.0; ai.settings.search_travel_timeout_seconds=20.0
	var known: Vector3=ai.last_seen_position
	player.reset_motion(Vector3(11,0,11)); ai.set_physics_process(true)
	var returned_at:=-1.0
	for tick in range(420):
		await _ticks(1)
		_check(ai.last_seen_position==known,"Search never updates its goal from the hidden player")
		if ai.state==ai.State.RETURN:
			returned_at=ai.sight_lost; break
	_check(returned_at>=5.0 and returned_at<5.04 and ai.attack_count==0,"SEARCH ends five seconds after last sight, regardless of arrival/legacy fields")
	await _ticks(240)
	_check(ai.state==ai.State.IDLE,"Safe breadcrumb return finishes at home")
	ai.set_physics_process(false)
	policy_rows.append({"case":"deadline","kind":kind,"return_at":returned_at,"state":ai.State.keys()[ai.state]})

func _run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1152,720)
	main=load("res://scenes/main.tscn").instantiate(); main.get_node("PracticeSelector").initial_mode=0; root.add_child(main)
	player=main.get_node("Player"); combat=player.combat; sprite=player.get_node("AnimatedSprite3D"); health=player.get_node("HealthComponent")
	for node in main.get_children():
		if node is StaticBody3D and node.has_node("Targetable"): node.free()
	await _ticks(4)
	for kind in [0,1]:
		await _vision(kind)
		for mirror in [false,true]:
			for obstructed in [false,true]: await _compare_sides(kind,mirror,obstructed)
		await _stall(kind)
		await _deadline(kind)
	var settings=load("res://scripts/enemies/enemy_settings.gd").new()
	settings.detection_radius=11.3; settings.horizontal_field_of_view_degrees=110.0; settings.vertical_field_of_view_degrees=70.0
	settings.lost_target_timeout_seconds=7.5; settings.search_radius=1.4
	_check(ResourceSaver.save(settings,"res://.godot/ai_policy_settings.tres")==OK,"Per-enemy perception/search settings serialize into the existing Resource")
	var saved: Resource=ResourceLoader.load("res://.godot/ai_policy_settings.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	_check(is_equal_approx(saved.detection_radius,11.3) and saved.horizontal_field_of_view_degrees==110.0 and saved.vertical_field_of_view_degrees==70.0 and saved.lost_target_timeout_seconds==7.5 and is_equal_approx(saved.search_radius,1.4),"Independent perception and deadline settings survive a fresh Resource load")
	var data:=FileAccess.open("res://.godot/enemy_ai_policy.json",FileAccess.WRITE)
	data.store_string(JSON.stringify(policy_rows,"  "))
	await _finish_edge()
