extends "res://tests/terrain_attack.gd"
func _native_contact(body: CharacterBody3D, local_point: Vector3) -> Vector3:
	var at: Vector3=main.get_node("TestArena").to_global(local_point)
	var above:=at+Vector3.UP*3
	var collision:=KinematicCollision3D.new()
	_check(body.test_move(Transform3D(body.global_basis,above),Vector3.DOWN*4,collision,body.safe_margin),"Native body has real floor contact")
	return above+collision.get_travel()

func _contact_fight(z: float, target_z: float) -> void:
	await _fresh_sword(4.5)
	ai.show_attack_diagnostics=true
	ai.global_position=_native_contact(ai,Vector3(-6,0,z))
	ai.home=ai.global_position
	player.set_physics_process(false)
	player.global_position=_native_contact(player,Vector3(-6,0,target_z))
	var anchor: Vector3=ai.global_position
	ai._start_windup()
	_check(ai.state==ai.State.WINDUP,"Contact starts a real windup")
	ai.set_physics_process(true)
	await _finish_strike()
	_check(ai.attack_count==1 and health.current_hp==90,"Contact windup finishes in one real hit")
	_check(ai.position.distance_to(anchor)<0.03,"Contact strike returns safely")
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
	for z in [0.2,0.1,0.0,-0.05,-0.1,-0.15,-0.2,-0.3,-3.0,-5.5,-5.6,-5.7,-5.75,-5.8,-5.85,-5.9,-5.95,-6.0,-6.05,-6.2]:
		for offset in [-1.8,1.8,-3.8,3.8]:
			await _fresh_sword(4.5)
			ai.show_attack_diagnostics=true
			ai.global_position=_native_contact(ai,Vector3(-6,0,z))
			ai.home=ai.global_position
			player.set_physics_process(false)
			player.global_position=_native_contact(player,Vector3(-6,0,maxf(-9.2,z+offset)))
			var available: bool=ai._attack_position_available()
			print("RAMP CONTACT z=",z," offset=",offset," at=",ai.global_position," support=",Elevation.supported(ai,ai.global_position)," available=",available," reason=",ai.attack_start_reason)
			_check(available,"Native contact permits safe ramp strike "+str(z)+"/"+str(offset))
			player.set_physics_process(true)
	for pair in [[0.0,-1.8],[-0.1,-3.8],[-3.0,-6.8],[-5.9,-9.0],[-6.0,-2.2],[-4.2,-5.9],[-5.9,-4.1]]:
		await _contact_fight(pair[0],pair[1])
	# A one-frame blocker must not use a stale plan or replay the warning sound.
	await _fresh_sword(2.0)
	ai.show_attack_diagnostics=true
	cue_count=0
	ai.attack_warning_started.connect(_cue)
	await _windup()
	var wall:=_block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.3,2,4))
	await _ticks(2)
	_check(ai.state==ai.State.WINDUP and ai.attack_count==0,"Transient unsafe plan waits without attacking")
	wall.free()
	await _finish_strike()
	_check(health.current_hp==90 and ai.attack_count==1 and cue_count==1,"Revalidated plan attacks once; warning is not replayed")
	await _fresh_sword(2.0)
	ai.show_attack_diagnostics=true
	await _windup()
	wall=_block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.3,2,4))
	await _ticks(20)
	_check(ai.attack_count==0 and health.current_hp==100 and ai.state!=ai.State.WINDUP,"Persistent obstruction cancels without a hit")
	_check(ai.attack_abort_reason.contains("BLADE") or ai.attack_abort_reason.contains("PATH"),"Cancellation names the actual failed safety check")
	wall.free()
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("RAMP CONTACT ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
