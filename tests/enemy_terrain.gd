extends "res://tests/enemy_tactics.gd"
var terrain_metrics: Array[Dictionary] = []
var max_tick_distance := 0.0
var max_tick_height := 0.0

func _terrain_actor(kind: int, at: Vector3, goal: Vector3) -> void:
	if kind==0: await _fresh_sword(4.0)
	else: await _fresh(1,Vector3(4,0,0))
	if kind==0:
		ai.settings=load("res://resources/enemies/melee_practice.tres").duplicate(true)
		ai.settings.attack=ai.settings.attack.duplicate(true)
		ai.settings.attack.weapon=ai.settings.attack.weapon.duplicate()
		ai.settings.attack.weapon.attack_range=0.2
	else:
		ai.settings=ai.settings.duplicate(true)
		ai.settings.attack_start_distance=0.2
	ai.active_attack=ai.settings.attack.snapshot()
	ai.settings.detection_radius=20.0
	ai.settings.walk=ai.settings.walk.duplicate()
	ai.global_position=at
	ai.home=at
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	player.reset_motion(goal)
	player.set_physics_process(false)
	ai.cooldown=1000.0
	ai._set_state(ai.State.CHASE)
	ai.set_physics_process(true)
	max_tick_distance=0.0
	max_tick_height=0.0

func _travel_until(goal: Vector3, limit_seconds: float = 10.0) -> bool:
	var start:=Engine.get_physics_frames()
	var previous: Vector3=ai.global_position
	var previous_frame:=Engine.get_physics_frames()
	while float(Engine.get_physics_frames()-start)/60.0<limit_seconds:
		await _ticks(1)
		var seconds:=float(Engine.get_physics_frames()-previous_frame)/60.0
		var change: Vector3=ai.global_position-previous
		max_tick_distance=maxf(max_tick_distance,change.length()/maxf(0.0001,seconds))
		max_tick_height=maxf(max_tick_height,absf(change.y)/maxf(0.0001,seconds))
		var maximum_speed:=maxf(maxf(4.0,ai.settings.walk.climb_speed),Vector2(ai.settings.walk.jump_takeoff_speed,ai.settings.walk.jump_horizontal_speed).length())
		_check(change.length()<=maximum_speed*seconds+0.02,"Walk/jump is time based, no instant warp")
		_check(ai.inside_home(ai.global_position),"All ordinary movement stays in horizontal home radius")
		previous=ai.global_position
		previous_frame=Engine.get_physics_frames()
		if ai.velocity.length_squared()>0.0001:
			ai.get_node("AnimatedSprite3D")._process(0.0)
			_check(String(ai.get_node("AnimatedSprite3D").animation).begins_with("walk_"),"Actual terrain movement uses Walk frames")
		if ai.global_position.y>goal.y-0.07 and Vector2(ai.position.x-goal.x,ai.position.z-goal.z).length()<1.15 and not ai.walker.busy():
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.godot/terrain_goal_%s_%s.png" % [ai.active_attack.kind,goal.y])
			return true
	return false

func _go_home() -> bool:
	player.global_position=ai.home+Vector3(0,3,20)
	var start:=Engine.get_physics_frames()
	for tick in range(700):
		await _ticks(1)
		if ai.state==ai.State.IDLE and ai.global_position.distance_to(ai.home)<0.045: return true
		if float(Engine.get_physics_frames()-start)/60.0>11.0: break
	return false

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		var saved: Resource=load("res://.godot/enemy_terrain_saved.tres")
		_check(is_equal_approx(saved.leash_radius,8.5) and is_equal_approx(saved.sight_loss_seconds,2.0) and is_equal_approx(saved.leash_reentry_margin,0.4),"Home/sight tuning persists after reload")
		_check(is_equal_approx(saved.walk.maximum_step_up,1.0) and is_equal_approx(saved.walk.gravity,25.0) and is_equal_approx(saved.walk.floor_seam_tolerance,0.1),"Enemy walk Resource persists separately from DashPath")
		for failure in failures: push_error(failure)
		print("ENEMY TERRAIN RELOAD ","PASS" if failures.is_empty() else "FAIL")
		quit(0 if failures.is_empty() else 1)
		return
	Engine.max_fps=30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size=Vector2i(1152,720)
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(5)
	for kind in [0,1]:
		# Real F5 test map: 18.4 degree ramp and 2m landing, then home by the same terrain.
		await _terrain_actor(kind,main.get_node("TestArena").to_global(Vector3(-6,0,0.6)),main.get_node("TestArena").to_global(Vector3(-6,2,-7.0)))
		var reached:=await _travel_until(main.get_node("TestArena").to_global(Vector3(-6,2,-7.0)))
		print("TERRAIN OBSERVE ",kind," ",ai.global_position," reached=",reached)
		terrain_metrics.append({"kind":kind,"terrain":"map_ramp","reached":reached,"position":str(ai.global_position)})
		_check(reached,"Both enemies climb the real test-map slope: "+str(kind))
		_check(await _go_home(),"Both enemies descend the ramp and reach home: "+str(kind))
		# Actual 0.25 / 0.5 / 1.0m-height map stairs.
		await _terrain_actor(kind,main.get_node("TestArena").to_global(Vector3(5,0,3)),main.get_node("TestArena").to_global(Vector3(5,1,-3.3)))
		reached=await _travel_until(main.get_node("TestArena").to_global(Vector3(5,1,-3.3)))
		print("TERRAIN OBSERVE ",kind," ",ai.global_position," reached=",reached)
		terrain_metrics.append({"kind":kind,"terrain":"map_stairs","reached":reached,"position":str(ai.global_position)})
		_check(reached,"Both enemies climb all three actual map steps: "+str(kind))
		_check(await _go_home(),"Both enemies descend map stairs and return home: "+str(kind))
		for height in [0.25,0.5,1.0]:
			var platform:=_block(Vector3(4.5,height*0.5,0),Vector3(3,height,3))
			await _terrain_actor(kind,Vector3(0,0,0),Vector3(5,height,0))
			reached=await _travel_until(Vector3(5,height,0),7.0)
			terrain_metrics.append({"kind":kind,"terrain":"single_step","height":height,"reached":reached,"position":str(ai.global_position)})
			print("TERRAIN STEP ",kind," / ",height," ",ai.global_position," reached=",reached)
			_check(reached,"Both enemies safely climb single riser "+str(height)+" / "+str(kind))
			_check(await _go_home(),"Single-riser descent returns to home without falling: "+str(height))
			platform.free()
	# Sword permission on a real slope must not require a horizontal dash floor.
	await _fresh_sword(2.0)
	player.set_physics_process(false)
	var ramp_start: Vector3=main.get_node("TestArena").to_global(Vector3(-6,0,-2))
	var ramp_goal: Vector3=main.get_node("TestArena").to_global(Vector3(-6,0,-4))
	var start_floor: Dictionary=ai.walker.floor_hit(ai,ramp_start,3.0,1.0)
	var goal_floor: Dictionary=ai.walker.floor_hit(ai,ramp_goal,3.0,1.0)
	_check(not start_floor.is_empty() and not goal_floor.is_empty(),"Real slope provides both actor floors")
	ai.global_position=start_floor.position+Vector3.UP*0.001
	ai.home=ai.global_position
	player.global_position=goal_floor.position+Vector3.UP*0.001
	ai._start_windup()
	_check(ai.state==ai.State.WINDUP and ai._in_place and ai.melee_hits(),"Sword can reach a target on a slope without relaxing DashPath")
	player.set_physics_process(true)
	await _terrain_actor(1,start_floor.position+Vector3.UP*0.001,goal_floor.position+Vector3.UP*0.001)
	ai.set_physics_process(false)
	ai._start_windup()
	await _ticks(3)
	var circle: Node3D=ai.get_node("CastingCircle")
	_check(circle.is_presenting() and circle.global_basis.y.dot(start_floor.normal)>0.999,"Mage's existing native circle follows the actual slope floor, without disappearing or burial")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/terrain_mage_slope_circle.png")
	var raised_platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _terrain_actor(0,Vector3.ZERO,Vector3(5,1,0))
	ai.settings.attack.weapon.attack_range=5.0
	ai.active_attack=ai.settings.attack.snapshot()
	ai.attack_count=1
	ai.cooldown=0.0
	await _state(ai.State.WINDUP,300)
	_check(ai.global_position.x>0.8 and ai._in_place,"After an earlier attack, soldier closes past preferred distance if terrain prevents a dash")
	raised_platform.free()
	# A reachable 1m step is a sword hit, not permission to dash through the riser.
	await _fresh_sword(2.0)
	player.set_physics_process(false)
	var step:=_block(origin+Vector3(0,0.5,0),Vector3(1.6,1.0,1.6))
	player.global_position.y=1.0
	await _ticks(3)
	ai._start_windup()
	_check(ai.state==ai.State.WINDUP and ai._in_place and ai.dash_destination==ai.attack_anchor,"Sword reaches 1m step target in place without an unsafe dash")
	ai.set_physics_process(true)
	await _finish_strike()
	_check(health.current_hp==90 and ai.global_position.distance_to(ai.attack_anchor)<0.01,"1m elevated target takes one normal hit, no travel")
	step.free()
	player.set_physics_process(true)
	await _fresh_sword(2.0)
	var wall:=_block(origin+Vector3(1,1,0),Vector3(0.2,2,2))
	await _ticks(3)
	_check(not ai._attack_position_available() and not ai.melee_hits(),"Full wall rejects planning and actual sword hit")
	wall.free()
	await _fresh_sword(2.0)
	wall=_block(origin+Vector3(1,0.125,0),Vector3(0.2,0.25,2))
	await _ticks(3)
	_check(not ai._attack_position_available() and not ai.melee_hits(),"Low obstruction between equal floors is not a height-difference attack")
	wall.free()
	for kind in [0,1]:
		await _terrain_actor(kind,Vector3(0,0,13),Vector3(0,0,20))
		await _ticks(70)
		_check(ai.global_position.z<13.7 and ai.global_position.y>-0.05,"Unsupported cliff edge stops both enemies")
		await _terrain_actor(kind,origin+Vector3(4,0,0),origin)
		ai.home=origin
		ai.walker.reset_home()
		ai.settings.sight_loss_seconds=1.75
		ai.settings.attack_start_distance=0.2
		await _ticks(4)
		var last_seen: Vector3=ai.last_seen_position
		wall=_block(origin+Vector3(2,1,0),Vector3(0.2,2,4))
		await _ticks(35)
		_check(ai.state==ai.State.CHASE and ai.last_seen_position==last_seen and ai.attack_count==0,"Transient sight loss retains last seen goal without wall attack")
		await _ticks(90)
		_check(ai.state in [ai.State.RETURN,ai.State.IDLE],"Long sight loss returns home after the configured grace")
		wall.free()
		await _terrain_actor(kind,origin+Vector3(8,0,0),origin-Vector3(2,0,0))
		ai.home=origin
		ai.walker.reset_home()
		await _ticks(8)
		_check(ai.state==ai.State.CHASE,"Home range permits enemy/player separation greater than the leash when both remain inside home radius")
		await _terrain_actor(kind,origin,origin+Vector3(6,0,0))
		ai.settings.leash_radius=9.0 if kind==0 else 10.0
		_check(ai.inside_home(origin+Vector3(0,40,0)),"Home range ignores vertical height")
		player.global_position=origin+Vector3(ai.settings.leash_radius+0.2,0,0)
		await _ticks(3)
		_check(ai.state in [ai.State.RETURN,ai.State.IDLE],"Player outside home radius stops chase even when close to the enemy")
		for distance in [ai.settings.leash_radius+0.05,ai.settings.leash_radius-0.05]:
			player.global_position=origin+Vector3(distance,0,0)
			await _ticks(4)
			_check(ai.state==ai.State.IDLE,"Boundary reentry margin prevents repeated reacquisition")
	# Blocked actor waits with zero walk velocity and retries at a bounded interval.
	await _terrain_actor(0,origin+Vector3(4,0,0),origin)
	wall=_block(origin+Vector3(3.4,1,0),Vector3(0.2,2,2))
	ai.set_physics_process(false)
	await _ticks(3)
	for tick in range(20): ai._walk_towards(origin,1.0/60.0)
	_check(ai.walker.blocked and ai.velocity==Vector3.ZERO and ai.walker.retry>0,"A blocked actor stops its Walk animation and backs off")
	wall.free()
	var saved: Resource=ai.settings.duplicate(true)
	saved.leash_radius=8.5
	saved.sight_loss_seconds=2.0
	saved.leash_reentry_margin=0.4
	saved.walk=saved.walk.duplicate()
	saved.walk.maximum_step_up=1.0
	saved.walk.gravity=25.0
	saved.walk.floor_seam_tolerance=0.1
	_check(ResourceSaver.save(saved,"res://.godot/enemy_terrain_saved.tres")==OK,"Enemy-specific walking and range settings save")
	FileAccess.open("res://.godot/enemy_terrain_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(terrain_metrics,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("ENEMY TERRAIN ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
