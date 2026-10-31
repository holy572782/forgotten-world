extends "res://tests/enemy_auto_jump.gd"

func _travel_until(goal: Vector3, limit_seconds: float=10.0) -> bool:
	var reached: bool=await super._travel_until(goal,limit_seconds)
	print("DEBUG PURSUIT goal=",goal," reached=",reached," at=",ai.position," jump=",ai.walker.jump_count," route=",ai._pursuit_route.reason," blocked=",ai.walker.blocked_reason)
	return reached

func _debug_actor(kind: int, at: Vector3, goal: Vector3) -> void:
	await _terrain_actor(kind,at,goal)
	ai.debug_unlimited_pursuit=true
	ai.show_attack_diagnostics=true
	ai.settings.detection_radius=7.0 if kind==0 else 8.0

func _run() -> void:
	Engine.max_fps=60
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
	var raw: Node=EnemyScene.instantiate()
	_check(not raw.debug_unlimited_pursuit,"Ordinary enemy defaults to bounded pursuit")
	raw.free()
	var raw_main: Node=load("res://scenes/main.tscn").instantiate()
	_check(raw_main.get_node("PracticeSelector").debug_unlimited_pursuit,"F5 map alone enables unlimited pursuit")
	raw_main.free()
	var floor_body:=_block(Vector3(0,-0.25,8),Vector3(100,0.5,100))
	for kind in [0,1]:
		await _debug_actor(kind,Vector3(-12,0,8),Vector3(12,0,8))
		ai._set_state(ai.State.IDLE)
		await _seconds(7.0)
		_check(ai.walker.horizontal(ai.home,ai.position)>ai.settings.leash_radius+1 and ai.state==ai.State.CHASE,"Both enemies chase beyond real detection and 9m/10m leash: "+str(kind))
		ai.debug_unlimited_pursuit=false
		_check(await _go_home(),"Turning debug off outside the radius returns safely home: "+str(kind))
		var platform:=_block(Vector3(4.5,0.5,8),Vector3(3,1,3))
		await _debug_actor(kind,Vector3(-9,0,8),Vector3(5,1,8))
		_check(await _travel_until(Vector3(5,1,8),12.0),"Pursuit climbs a step beyond the original leash: "+str(kind))
		_check(ai.walker.jump_count>0 and ai.walker.horizontal(ai.home,ai.position)>ai.settings.leash_radius,"Jump corridor also bypasses leash only in debug")
		platform.free()
	floor_body.free()
	for kind in [0,1]:
		var arena: Node3D=main.get_node("TestArena")
		await _debug_actor(kind,arena.to_global(Vector3(-6,0,0.6)),arena.to_global(Vector3(-6,2,-7)))
		ai.settings.leash_radius=0.4 # Only this clone; force each walk/jump bounds check.
		_check(await _travel_until(arena.to_global(Vector3(-6,2,-7))),"Debug follows actual ramp: "+str(kind))
		await _debug_actor(kind,arena.to_global(Vector3(5,0,3)),arena.to_global(Vector3(5,1,-3.3)))
		ai.settings.leash_radius=0.4
		_check(await _travel_until(arena.to_global(Vector3(5,1,-3.3))),"Debug follows actual stairs: "+str(kind))
	floor_body=_block(Vector3(0,-0.25,8),Vector3(100,0.5,100))
	var wall:=_block(Vector3(0,1.5,8),Vector3(0.4,3,3))
	await _debug_actor(0,Vector3(-4,0,8),Vector3(4,0,8))
	_check(await _travel_until(Vector3(4,0,8),14.0),"Safe local route walks around a wall without direct sight")
	wall.free()
	wall=_block(Vector3(0,1.5,8),Vector3(0.4,3,50))
	await _debug_actor(0,Vector3(-1,0,8),Vector3(1,0,8))
	await _seconds(2.0)
	print("SEALED STOP at=",ai.position," route=",ai._pursuit_route.reason," move=",ai.walker.blocked_reason)
	_check(ai.position.x < -0.59 and ai.attack_count==0 and ai.state!=ai.State.RETURN,"An unreachable target does not permit wall passage or attack")
	_check(ai.debug_label.text.contains("NO_SAFE_LOCAL_ROUTE"),"Blocked pursuit displays a concrete safe-route failure")
	wall.free()
	floor_body.free()
	var ledge:=_block(Vector3(40,-0.25,0),Vector3(4,0.5,4))
	var goal_ledge:=_block(Vector3(48,-0.25,0),Vector3(4,0.5,4))
	await _debug_actor(0,Vector3(40,0,0),Vector3(48,0,0))
	await _seconds(2.0)
	print("CLIFF STOP at=",ai.position," support=",ai.walker._support(ai.position)," route=",ai._pursuit_route.reason)
	_check(ai.position.x<=42.0-ai.get_node("CollisionShape3D").shape.radius*0.95+0.01 and ai.walker._support(ai.position) and absf(ai.position.y)<0.05 and ai.walker.jump_count==0 and not ai.walker.airborne(),"Unlimited pursuit cannot bridge a large floorless gap")
	ledge.free()
	goal_ledge.free()
	await _fresh_sword(4.5)
	ai.debug_unlimited_pursuit=true
	await _windup()
	await _finish_strike()
	_check(ai.attack_count==1 and health.current_hp==90 and ai.position.distance_to(ai.attack_anchor)<0.03,"Debug soldier keeps strike and attack-anchor return")
	await _fresh(1,Vector3(4,0,0))
	ai.debug_unlimited_pursuit=true
	var anchor: Vector3=ai.position
	await _windup()
	for tick in range(150):
		await _ticks(1)
		if ai.attack_count==1: break
	_check(ai.attack_count==1 and ai.shots.size()==1 and ai.position.distance_to(anchor)<0.01,"Debug mage stops in range and actually casts a fireball")
	health.damage(1000,ai)
	await _ticks(3)
	_check(ai.state==ai.State.RETURN or ai.state==ai.State.IDLE,"Player death overrides unlimited chase")
	ai.health.damage(1000,player)
	_check(ai.state==ai.State.DEAD and ai.collision_layer==0,"Enemy death still disables AI and collision")
	_check(load("res://resources/enemies/melee_practice.tres").leash_radius==9.0 and load("res://resources/enemies/ranged_practice.tres").leash_radius==10.0,"Formal enemy Resource radii remain 9m/10m")
	ai.free()
	ai=null
	var selector: Node=main.get_node("PracticeSelector")
	selector.debug_unlimited_pursuit=true
	selector.show_enemy_diagnostics=true
	for mode in [1,2]:
		selector.select_mode(mode)
		await _ticks(3)
		_check(selector.active_enemy.debug_unlimited_pursuit and selector.active_enemy.show_attack_diagnostics,"M09 map forwards debug switches to both enemy kinds")
	selector.select_mode(0)
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("UNLIMITED PURSUIT ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
