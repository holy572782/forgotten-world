extends "res://tests/elevation_dash.gd"
func _trial(a: Vector3, b: Vector3, soldier: bool, label: String) -> void:
	await _fresh_sword(4.5)
	combat.equipped_weapon=load("res://resources/weapons/one_handed_sword.tres").duplicate()
	ai.global_position=Elevation.landing(ai,a)
	ai.home=ai.global_position
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	ai.show_attack_diagnostics=true
	player.reset_motion(b+Vector3.UP*0.08)
	await _ticks(10)
	main.get_node("CameraRig").snap_to_target()
	player.set_physics_process(not soldier)
	var actor: CharacterBody3D=ai if soldier else player
	var anchor: Vector3=actor.global_position
	if soldier:
		_check(ai._attack_position_available(),"Recognition/planning: "+label)
		ai._start_windup()
		_check(ai.state==ai.State.WINDUP,"Warning begins: "+label)
		ai.set_physics_process(true)
	else: _check(combat.request_attack(ai.targetable),"Player shared plan: "+label)
	var hit:=false
	for tick in range(400):
		await _ticks(1)
		if soldier:
			hit=health.current_hp==90
			if ai.state==ai.State.RECOVERY: break
		else:
			hit=ai.health.current_hp==30
			if not combat.is_busy(): break
	_check(hit,"Actual single hit: "+label)
	if soldier: _check(ai.attack_hit_reason=="OK","Debug identifies confirmed hit independently: "+label)
	_check(actor.global_position.distance_to(anchor)<0.03,"Safe return: "+label)
	print("TERRAIN STRIKE ",label," hit=",hit," return=",actor.global_position.distance_to(anchor))
	player.set_physics_process(true)

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
	var arena: Node3D=main.get_node("TestArena")
	for pair in [[Vector3(5,0,2.6),Vector3(5,0.25,1)],[Vector3(5,0.25,1),Vector3(5,0.5,-1)],[Vector3(5,0.5,-1),Vector3(5,1,-3)]]:
		await _trial(arena.to_global(pair[0]),arena.to_global(pair[1]),true,"actual map stairs")
		await _trial(arena.to_global(pair[1]),arena.to_global(pair[0]),true,"actual map stairs reverse")
	for soldier in [true,false]:
		for pair in [[Vector3(-6,0,-2),Vector3(-6,0,-3.3)],[Vector3(-6,0,-1.5),Vector3(-6,0,-5)],[Vector3(-6.6,0,-3),Vector3(-5.4,0,-3)]]:
			var a:=Elevation.Blade.ground_at(player,arena.to_global(pair[0])+Vector3.UP*3,4.0)
			var b:=Elevation.Blade.ground_at(player,arena.to_global(pair[1])+Vector3.UP*3,4.0)
			await _trial(a,b,soldier,"ramp "+str(soldier)+str(pair))
			await _trial(b,a,soldier,"ramp reverse "+str(soldier)+str(pair))
	for h in [0.25,0.5,1.0]:
		var platform:=_block(Vector3(4.5,h*0.5,0),Vector3(3,h,3))
		for near in [true,false]:
			var low:=Vector3(2 if near else 0,0,0)
			var high:=Vector3(4 if near else 4.5,h,0)
			await _trial(low,high,true,"stairs up "+str(h)+str(near))
			await _trial(high,low,true,"stairs down "+str(h)+str(near))
		platform.free()
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("TERRAIN ATTACK ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
