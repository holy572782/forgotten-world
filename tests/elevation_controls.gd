extends "res://tests/elevation_dash.gd"
func _idle() -> void:
	for tick in range(400):
		await _ticks(1)
		if not combat.is_busy(): return
	_check(false,"Elevated sequence exits its state")

func _run() -> void:
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
	for yaw in [0.0,90.0,180.0,270.0]:
		var platform:=await _setup(true,false)
		main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
		main.get_node("CameraRig").snap_to_target()
		_check(combat.request_attack(ai.targetable),"Jump starts in every camera quadrant")
		await _ticks(4)
		var before: Vector3=player.global_position
		_press("guard",true)
		await _ticks(3)
		_check(combat.state==combat.State.Guard and combat._flight.active and player.global_position.distance_to(before)>0.02,"Midair guard keeps actual flight moving")
		health.damage(10,ai)
		_check(health.current_hp==95,"Existing physical guard reduction works in flight")
		_press("guard",false)
		await _ticks(1)
		_check(combat.state!=combat.State.Guard and combat._flight.active,"Releasing guard removes protection immediately while flight continues")
		await _idle()
		_check(combat.return_error<0.03 and not main.get_node("CameraRig").follow_locked,"Guard release lands then returns and unlocks camera")
		platform.free()
	# Manual return during a jump finishes that safe leg, then takes the checked reverse path.
	var platform:=await _setup(true,false)
	var anchor: Vector3=player.global_position
	_check(combat.request_attack(ai.targetable),"Manual-return trial starts")
	await _ticks(5)
	var destination: Vector3=combat._flight.data.finish
	_press("move_left",true)
	await _ticks(2)
	_press("move_left",false)
	_check(combat._flight.active and combat._flight.data.finish==destination and not combat._air_return_reason.is_empty(),"Direction input defers reversal until safe landing")
	await _idle()
	_check(player.global_position.distance_to(anchor)<0.03 and ai.health.current_hp==40,"Manual return never swings or warps in midair")
	platform.free()
	# Three real strikes alternate between high and low targets, preserving one anchor.
	platform=await _setup(true,false)
	var second: CharacterBody3D=EnemyScene.instantiate()
	second.position=Vector3(0,0,1)
	second.player=player
	main.add_child(second)
	second.set_physics_process(false)
	await _ticks(2)
	anchor=player.global_position
	_check(combat.request_attack(ai.targetable),"Mixed-height combo starts")
	var saw_second:=false
	var saw_third:=false
	for tick in range(650):
		if combat.state==combat.State.Attack and not combat.queued and combat._sequence_slots<3:
			var next: Node3D=second.targetable if combat._sequence_slots==1 else ai.targetable
			if combat.can_combo_select(next):
				var accepted: bool=combat.request_followup(next)
				if combat._sequence_slots==1: saw_second=accepted
				else: saw_third=accepted
		await _ticks(1)
		_check(combat.return_anchor==anchor,"Combo anchor never follows a different floor")
		if not combat.is_busy(): break
	_check(saw_second and saw_third and combat.combo_hits==3 and ai.health.current_hp==20 and second.health.current_hp==30,"High-low-high targets receive exactly three real strikes")
	_check(not combat.is_busy() and combat.return_error<0.03,"Mixed combo retraces safe legs to the initial floor")
	second.free()
	platform.free()
	# A blocked reverse route must stop without a warp through the new wall.
	platform=await _setup(true,false)
	_check(combat.request_attack(ai.targetable),"Dynamic return obstruction trial starts")
	await _phase(combat.State.Attack)
	var wall:=_block(Vector3(1.5,1.5,0),Vector3(0.3,3,3))
	await _idle()
	_check(player.global_position.x>3.0 and combat.return_error>1.0 and Elevation.supported(player,player.global_position),"Blocked return exits on a supported safe floor")
	wall.free()
	platform.free()
	# Distinct height limits, landing occupancy, ceiling and genuine unsupported gaps.
	platform=await _setup(true,false)
	var ceiling:=_block(Vector3(2.0,2.2,0),Vector3(6,0.2,3))
	await _ticks(2)
	_check(Elevation.attack(player,ai.global_position,combat.equipped_weapon,combat.settings,1.1,combat.equipped_weapon.motion).is_empty(),"Full capsule cannot jump through a ceiling")
	ceiling.free()
	var small:=_block(Vector3(1.5,0.1,0),Vector3(0.3,0.2,0.3))
	small.collision_layer=4
	await _ticks(2)
	_check(Elevation.attack(player,ai.global_position,combat.equipped_weapon,combat.settings,1.1,combat.equipped_weapon.motion).is_empty(),"A small enemy cannot be jumped over")
	small.free()
	var occupied:=_block(Vector3(2.8,1.8,0),Vector3(2.2,1.6,2)) # Cover lower-floor candidates too.
	occupied.collision_layer=4
	await _ticks(2)
	_check(Elevation.attack(player,ai.global_position,combat.equipped_weapon,combat.settings,1.1,combat.equipped_weapon.motion).is_empty(),"Occupied landing rejects the attack")
	occupied.free()
	var floor_body: StaticBody3D=main.get_node("TestArena/Terrain/FlatGround")
	floor_body.collision_layer=0
	var ledge:=_block(Vector3(0,-0.1,0),Vector3(2,0.2,3))
	await _ticks(2)
	_check(Elevation.attack(player,ai.global_position,combat.equipped_weapon,combat.settings,1.1,combat.equipped_weapon.motion).is_empty(),"A wide unsupported gap is never an attack route")
	ledge.free()
	floor_body.collision_layer=1
	combat.equipped_weapon.elevation_travel=combat.equipped_weapon.elevation_travel.duplicate()
	combat.equipped_weapon.elevation_travel.maximum_ascent=0.5
	_check(Elevation.plan(player,player.global_position,Vector3(3.4,1,0),combat.settings,combat.equipped_weapon.elevation_travel,combat.equipped_weapon.motion).is_empty(),"Ascent limit is independent of blade height")
	platform.free()
	platform=await _setup(false,false)
	combat.equipped_weapon.elevation_travel=combat.equipped_weapon.elevation_travel.duplicate()
	combat.equipped_weapon.elevation_travel.maximum_descent=0.5
	_check(Elevation.attack(player,ai.global_position,combat.equipped_weapon,combat.settings,1.1,combat.equipped_weapon.motion).is_empty(),"Descent limit is independently configurable")
	platform.free()
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("ELEVATION CONTROLS ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
