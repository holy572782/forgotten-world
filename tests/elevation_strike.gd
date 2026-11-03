extends "res://tests/enemy_terrain.gd"
func _run() -> void:
	root.size=Vector2i(1152,720)
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	combat.equipped_weapon=load("res://resources/weapons/one_handed_sword.tres").duplicate()
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(5)
	for height in [1.0,1.8]:
		for upward in [true,false]:
			await _fresh_sword(2.0)
			var platform:=_block(origin+Vector3(2 if upward else -0.5,height*0.5,0),Vector3(2 if upward else 2.0,height,3))
			ai.position=origin+Vector3(2,height if upward else 0.0,0)
			player.reset_motion(origin+Vector3(0,0 if upward else height,0))
			await _ticks(8)
			main.get_node("CameraRig").snap_to_target()
			_check(combat.can_select(ai.targetable),"Player marker accepts reachable elevation")
			_check(combat.request_attack(ai.targetable) and combat.state==combat.State.Attack,"Player attacks in place across a step")
			for tick in range(150):
				await _ticks(1)
				if not combat.is_busy(): break
			_check(ai.health.current_hp==30 and player.global_position.distance_to(combat.return_anchor)<0.02,"Player deals one hit without moving")
			combat.cancel()
			health.heal(100)
			ai._start_windup()
			await _planned_warning()
			_check(ai.state==ai.State.WINDUP and ai._in_place,"Soldier can begin an opposite-elevation swing in place")
			# At 1.8m, this particular upper-platform lip intersects the direct
			# hand-to-target segment. Height permission cannot bypass that solid lip.
			var clear_blade: bool=not (upward and height==1.8)
			_check(ai.melee_hits()==clear_blade,"Opposite-elevation damage follows the real segment, not the body-floor footprint")
			ai.set_physics_process(true)
			await _finish_strike()
			_check(health.current_hp==(90 if clear_blade else 100),"Height-aware hit respects the intervening upper-platform lip")
			platform.free()
	await _fresh_sword(2.0)
	var arena: Node3D=main.get_node("TestArena")
	var start: Dictionary=ai.walker.floor_hit(ai,arena.to_global(Vector3(-6,0,-2)),3.0,1.0)
	var finish: Dictionary=ai.walker.floor_hit(ai,arena.to_global(Vector3(-6,0,-4)),3.0,1.0)
	ai.global_position=finish.position+Vector3.UP*0.001
	player.reset_motion(start.position+Vector3.UP*0.001)
	await _ticks(8)
	main.get_node("CameraRig").snap_to_target()
	_check(combat.can_select(ai.targetable) and combat.request_attack(ai.targetable),"Player's actual slope marker and attack agree")
	for tick in range(160):
		await _ticks(1)
		if not combat.is_busy(): break
	_check(ai.health.current_hp==30,"Native slope support remains valid during the strike")
	await _fresh_sword(2.0)
	var wall:=_block(origin+Vector3(1,1.5,0),Vector3(0.2,3,3))
	await _ticks(3)
	_check(not combat.can_select(ai.targetable) and not ai.melee_hits(),"A full wall blocks both swords")
	wall.free()
	var weapon: WeaponData=combat.equipped_weapon
	var sweep=load("res://scripts/combat/melee_sweep.gd")
	_check(sweep.contains(Vector3.ZERO,Vector3.RIGHT,Vector3(1,1.8,0),weapon) and not sweep.contains(Vector3.ZERO,Vector3.RIGHT,Vector3(1,1.801,0),weapon),"Upward blade height boundary is 1.8m")
	_check(sweep.contains(Vector3.ZERO,Vector3.RIGHT,Vector3(1,-1.8,0),weapon) and not sweep.contains(Vector3.ZERO,Vector3.RIGHT,Vector3(1,-1.801,0),weapon),"Downward blade height boundary is 1.8m")
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("ELEVATION STRIKE ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
