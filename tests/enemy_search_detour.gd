extends "res://tests/enemy_edge_attack.gd"
var search_rows: Array[Dictionary]=[]
class PerceptionEnemy:
	extends "res://scripts/enemies/practice_enemy.gd"
	var sight_override: int=-1
	func _work_has_sight() -> bool:
		return super._work_has_sight() if sight_override<0 else sight_override==1 and player_alive()

func _actor(kind: int, unlimited: bool, controlled: bool=false) -> void:
	if is_instance_valid(ai):
		ai.clear_shots(); ai.free()
	combat.cancel(); health.heal(1000)
	player.reset_motion(Vector3(4,0,8)); player.set_physics_process(false)
	ai=EnemyScene.instantiate()
	if controlled: ai.set_script(PerceptionEnemy)
	ai.settings=load("res://resources/enemies/melee_practice.tres" if kind==0 else "res://resources/enemies/ranged_practice.tres").duplicate(true)
	ai.player=player; ai.position=Vector3(0,0,8); ai.debug_unlimited_pursuit=unlimited
	main.add_child(ai); ai.set_physics_process(false)
	ai.global_position=_native_floor(ai,ai.global_position); ai.home=ai.global_position
	player.reset_motion(_native_floor(player,player.global_position))
	ai._set_state(ai.State.CHASE)
	_check(is_equal_approx(ai.engagement_range(),5.0 if kind==0 else 6.0) and is_equal_approx(ai.active_attack.aim_lock_ratio,0.4 if kind==0 else 0.5),"Official ranges and fixed-aim ratios")
	_check(ai.has_sight(),"Initial sighting is real, before an occluder is introduced")
	ai.last_seen_position=player.global_position; ai._last_seen_valid=true
	await _ticks(3)

func _detour(kind: int, unlimited: bool) -> void:
	await _actor(kind,unlimited)
	var wall:=_block(Vector3(2,1.5,8),Vector3(0.3,3,2))
	await _ticks(3); ai.set_physics_process(true)
	var lateral:=0.0; var unsafe:=false; var detoured:=false
	for tick in range(600):
		await _ticks(1)
		lateral=maxf(lateral,absf(ai.position.z-8.0))
		unsafe=unsafe or (absf(ai.position.x-2)<0.14 and absf(ai.position.z-8)<1.0)
		detoured=detoured or not ai._pursuit_route.waypoints.is_empty() or not ai._pursuit_route._search.is_empty()
		if health.current_hp<100: break
	var row: Dictionary={"case":"detour","kind":kind,"unlimited":unlimited,"position":str(ai.global_position),"state":ai.State.keys()[ai.state],"lateral":lateral,"unsafe":unsafe,"planned_detour":detoured,"attacks":ai.attack_count,"hp":health.current_hp}
	search_rows.append(row); print("SEARCH TRIAL ",JSON.stringify(row))
	if not "--probe" in OS.get_cmdline_user_args():
		_check(health.current_hp==90 and lateral>0.8 and detoured,"Real reacquisition and damage after bounded detour")
		_check(not unsafe,"Never move through the wall")
	ai.set_physics_process(false); wall.free()

func _reacquire(kind: int) -> void:
	await _actor(kind,false,true)
	ai.sight_override=0; ai.cooldown=1000.0
	var wall:=_block(Vector3(2,1.5,8),Vector3(0.3,3,2))
	player.reset_motion(Vector3(11,0,11))
	await _ticks(3); ai.set_physics_process(true)
	for tick in range(600):
		await _ticks(1)
		if ai._search_behavior.phase=="SEARCH_AREA": break
	_check(ai._search_behavior.phase=="SEARCH_AREA","Reacquisition fixture arrives and starts its own timer")
	var memory: Vector3=ai.last_seen_position
	for tick in range(30):
		player.reset_motion(Vector3(11,0,11+float(tick%2)))
		await _ticks(1)
		_check(ai.last_seen_position==memory and ai.attack_count==0,"Unseen movement never updates memory or starts attacks")
	player.reset_motion(_native_floor(player,ai.global_position+Vector3.RIGHT*1.2))
	ai.sight_override=-1; ai.cooldown=0.0
	for tick in range(240):
		await _ticks(1)
		if health.current_hp<100: break
	_check(ai._search_behavior.phase.is_empty() and health.current_hp==90,"Real sight reacquires the target and resumes production combat")
	search_rows.append({"case":"reacquire","kind":kind,"hp":health.current_hp,"phase":ai._search_behavior.phase})
	ai.set_physics_process(false); wall.free()

func _unreachable(kind: int, unlimited: bool) -> void:
	await _actor(kind,unlimited,true)
	ai.sight_override=0; ai.settings.search_travel_timeout_seconds=2.5
	var walls: Array[Node]=[]
	for item in [[Vector3(1,1.5,8),Vector3(0.2,3,4)],[Vector3(-1,1.5,8),Vector3(0.2,3,4)],[Vector3(0,1.5,6),Vector3(2,3,0.2)],[Vector3(0,1.5,10),Vector3(2,3,0.2)]]: walls.append(_block(item[0],item[1]))
	await _ticks(3); ai.set_physics_process(true)
	var bound:=0.0
	for tick in range(240):
		await _ticks(1); bound=maxf(bound,ai.position.distance_to(ai.home))
	_check(bound<1.7 and ai.attack_count==0,"Closed geometry never allows wall passage or hidden attacks")
	_check(ai.state==ai.State.CHASE if unlimited else ai.state==ai.State.IDLE,"Unlimited safely waits; normal search deadline returns home")
	search_rows.append({"case":"unreachable","kind":kind,"unlimited":unlimited,"state":ai.State.keys()[ai.state],"bound":bound})
	# Switching modes preserves the body and its safe collision owner.
	var before: Vector3=ai.global_position
	ai.debug_unlimited_pursuit=not unlimited
	await _ticks(2)
	_check(ai.global_position.distance_to(before)<0.1,"Mode toggle never teleports the body")
	ai.set_physics_process(false)
	for wall in walls: wall.free()

func _after_attack(kind: int) -> void:
	await _actor(kind,false)
	player.reset_motion(Vector3(1.3,0.001,8))
	ai.set_physics_process(true)
	await _state(ai.State.RECOVERY,360)
	for tick in range(60):
		if health.current_hp<100: break
		await _ticks(1) # A released projectile can hit after RECOVERY begins.
	_check(ai.attack_count==1 and health.current_hp==90,"Post-attack fixture starts after a real hit and return")
	var recovered_at:=Engine.get_physics_frames()
	player.reset_motion(Vector3(4,0.001,8))
	await _ticks(2) # Real sight confirms this position before the wall appears.
	var wall:=_block(Vector3(2,1.5,8),Vector3(0.3,3,2))
	for tick in range(900):
		await _ticks(1)
		if health.current_hp<=80: break
	_check(health.current_hp==80 and ai.attack_count==2,"Both enemies resume detour and attack after recovery")
	_check(float(Engine.get_physics_frames()-recovered_at)/60.0>=ai.active_attack.recovery_seconds,"Search/reacquisition never shortens recovery")
	search_rows.append({"case":"post_attack","kind":kind,"hp":health.current_hp,"attacks":ai.attack_count})
	ai.set_physics_process(false); wall.free()

func _bounds(kind: int) -> void:
	await _actor(kind,false)
	player.reset_motion(Vector3(ai.settings.leash_radius+1.0,0.001,8))
	ai.set_physics_process(true)
	await _ticks(4)
	_check(ai.state in [ai.State.RETURN,ai.State.IDLE] and ai.attack_count==0,"A visible target outside the formal home radius ends pursuit")
	ai.debug_unlimited_pursuit=true
	await _ticks(60)
	_check(ai.position.x>1.0 and ai.state==ai.State.CHASE,"Unlimited mode follows beyond the formal detection range")
	ai.set_physics_process(false)

func _air_toggle(kind: int) -> void:
	await _actor(kind,true,true)
	var platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	ai.global_position=Vector3(2.1,0.001,0); ai.home=ai.global_position
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	player.reset_motion(Vector3(5,1.001,0)); ai.last_seen_position=player.global_position
	ai.sight_override=0
	await _ticks(3)
	ai.walker.walk(player.global_position,1.0/60.0,ai.settings.chase_speed)
	_check(ai.walker.airborne(),"Toggle fixture starts an ordinary validated jump")
	ai.set_physics_process(true); await _ticks(4)
	ai.debug_unlimited_pursuit=false
	var before: Vector3=ai.global_position
	await _ticks(1)
	_check(ai.global_position.distance_to(before)<0.2,"Disabling debug during flight never warps the body")
	await _ticks(75)
	_check(not ai.walker.busy() and ai.global_position.y>0.9 and ai.walker._can_land(),"Search transition completes the existing jump and lands normally")
	ai.set_physics_process(false); platform.free()

func _memory(kind: int, zero: bool=false) -> void:
	await _actor(kind,false,true)
	ai.sight_override=0; ai.cooldown=1000.0
	if zero: ai.settings.search_duration_seconds=0.0
	var anchor: Vector3=ai.last_seen_position
	var wall:=_block(Vector3(2,1.5,8),Vector3(0.3,3,2))
	await _ticks(3); ai.set_physics_process(true)
	var furthest:=0.0; var searched:=false; var returned:=false; var wrong_memory:=false
	var area_time:=-1.0; var first_return:=-1.0
	var start:=Engine.get_physics_frames()
	for tick in range(780):
		if tick==30: player.reset_motion(Vector3(11,0,11)) # Hidden and beyond leash; must not reveal this position.
		await _ticks(1)
		furthest=maxf(furthest,ai.position.x)
		wrong_memory=wrong_memory or ai.last_seen_position!=anchor
		if "_search_behavior" in ai and ai._search_behavior.phase=="SEARCH_AREA":
			searched=true
			if area_time<0: area_time=float(Engine.get_physics_frames()-start)/60.0
		if ai.state==ai.State.RETURN and first_return<0: first_return=float(Engine.get_physics_frames()-start)/60.0
		if ai.state==ai.State.IDLE and first_return>=0:
			returned=true; break
	var row: Dictionary={"case":"memory_zero" if zero else "memory","kind":kind,"furthest":furthest,"searched":searched,"area_time":area_time,"return_time":first_return,"returned":returned,"wrong_memory":wrong_memory,"attacks":ai.attack_count,"position":str(ai.global_position)}
	search_rows.append(row); print("SEARCH TRIAL ",JSON.stringify(row))
	if not "--probe" in OS.get_cmdline_user_args():
		_check(furthest>(3.0 if zero else 3.4) and searched==(not zero) and returned,"Reach last seen location, search if enabled, then return")
		_check(first_return>=ai.settings.sight_loss_seconds if zero else first_return-area_time>=1.99,"Zero skips area exploration; positive timer starts on arrival")
		_check(not wrong_memory and ai.attack_count==0,"Hidden movement neither updates memory nor authorizes attacks")
	ai.set_physics_process(false); wall.free()

func _run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1152,720)
	main=load("res://scenes/main.tscn").instantiate(); main.get_node("PracticeSelector").initial_mode=0
	root.add_child(main)
	player=main.get_node("Player"); combat=player.combat; sprite=player.get_node("AnimatedSprite3D"); health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.free()
	await _ticks(4)
	for kind in [0,1]:
		if "--zero" in OS.get_cmdline_user_args():
			await _memory(kind,true)
			continue
		for unlimited in [false,true]: await _detour(kind,unlimited)
		await _memory(kind)
		if not "--probe" in OS.get_cmdline_user_args():
			await _reacquire(kind)
			for unlimited in [false,true]: await _unreachable(kind,unlimited)
			await _after_attack(kind)
			await _bounds(kind)
			await _air_toggle(kind)
	if not "--probe" in OS.get_cmdline_user_args():
		var settings=load("res://scripts/enemies/enemy_settings.gd").new()
		settings.search_duration_seconds=1.4; settings.search_radius=1.3; settings.search_travel_timeout_seconds=6.5
		_check(ResourceSaver.save(settings,"res://.godot/search_settings_saved.tres")==OK,"Search tuning is saved as an existing EnemySettings Resource")
		var saved: Resource=ResourceLoader.load("res://.godot/search_settings_saved.tres","",ResourceLoader.CACHE_MODE_IGNORE)
		_check(is_equal_approx(saved.search_duration_seconds,1.4) and is_equal_approx(saved.search_radius,1.3) and is_equal_approx(saved.search_travel_timeout_seconds,6.5),"Search tuning survives a fresh resource load")
	var args:=OS.get_cmdline_user_args()
	var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/search_detour_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(search_rows,"  "))
	await _finish_edge()
