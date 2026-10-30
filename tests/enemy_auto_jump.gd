extends "res://tests/enemy_terrain.gd"
var jump_metrics: Array[Dictionary] = []

class FlightTrace extends Node:
	var actor: CharacterBody3D
	var peak := 0.0
	var rising := false
	var falling := false
	var error := 0.0
	var wrong_state := false
	var wrong_facing := false
	var land_tick := -1
	var landings: Array[int] = []
	var launches: Array[int] = []
	var seen := 0
	var was_air := false
	func _ready() -> void: process_physics_priority=120
	func _physics_process(_delta: float) -> void:
		var walker: RefCounted=actor.walker
		if walker.jump_count>seen:
			seen=walker.jump_count
			launches.append(Engine.get_physics_frames())
		if walker.motion_mode==walker.Motion.JUMP:
			var data: Dictionary=walker.jump_data
			peak=maxf(peak,actor.global_position.y-data.start.y)
			rising=rising or actor.velocity.y>0.1
			falling=falling or actor.velocity.y < -0.1
			var expected: Vector3=walker.Arc.position_at(data.start,data.direction,data.speed,data.takeoff,data.gravity,walker.jump_elapsed)
			error=maxf(error,expected.distance_to(actor.global_position))
			wrong_state=wrong_state or actor.state not in [actor.State.CHASE,actor.State.RECOVERY,actor.State.RETURN]
			var horizontal:=Vector3(actor.velocity.x,0,actor.velocity.z)
			wrong_facing=wrong_facing or (horizontal.length()>0.01 and actor.facing.dot(horizontal.normalized())<0.999)
		if was_air and not walker.airborne():
			land_tick=Engine.get_physics_frames()
			landings.append(land_tick)
		was_air=walker.airborne()

func _trace() -> FlightTrace:
	var trace:=FlightTrace.new()
	trace.actor=ai
	ai.add_child(trace)
	return trace

func _await_launch() -> bool:
	for tick in range(220):
		await _ticks(1)
		if ai.walker.airborne(): return true
	return false

func _plan_actor() -> void:
	await _terrain_actor(0,Vector3(2.1,0,0),Vector3(5,1,0))
	ai.set_physics_process(false)
	await _ticks(2)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		var saved: Resource=load("res://.godot/enemy_auto_jump_saved.tres")
		_check(saved.jump_enabled and is_equal_approx(saved.walking_step_height,0.28) and is_equal_approx(saved.jump_height,1.15),"Height/step tuning survives a new process")
		_check(is_equal_approx(saved.jump_takeoff_speed,7.0) and is_equal_approx(saved.jump_horizontal_speed,2.6) and is_equal_approx(saved.jump_cooldown_seconds,1.2),"Independent jump speeds/cooldown survive reload")
		for failure in failures: push_error(failure)
		print("ENEMY AUTO JUMP RELOAD ","PASS" if failures.is_empty() else "FAIL")
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
		for height in [0.25,0.5,1.0]:
			var platform:=_block(Vector3(4.5,height*0.5,0),Vector3(3,height,3))
			await _terrain_actor(kind,Vector3.ZERO,Vector3(5,height,0))
			var trace:=_trace()
			_check(await _travel_until(Vector3(5,height,0),7.0),"Both enemies reach a supported step: %s / %s" % [kind,height])
			_check(ai.walker.jump_count==(0 if height<0.3 else 1),"Low step walks; medium/high step jumps once")
			if height>0.3:
				_check(absf(trace.peak-1.1)<0.012 and trace.rising and trace.falling,"Physical arc rises to 1.1m then descends")
				_check(trace.error<0.003 and not trace.wrong_state and not trace.wrong_facing,"Arc, facing and ordinary movement state stay synchronized")
				_check(ai.attack_count==0 and ai.walker.jump_cooldown>0.0,"No attack during jump; landing begins cooldown")
			jump_metrics.append({"kind":kind,"step":height,"jumps":ai.walker.jump_count,"peak":trace.peak,"arc_error":trace.error})
			_check(await _go_home(),"Both enemies safely descend and return to home")
			platform.free()
		# Home is on the upper floor: return must jump upward, using the same route owner.
		var platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
		await _terrain_actor(kind,Vector3(5,1,0),Vector3.ZERO)
		_check(await _travel_until(Vector3.ZERO,7.0),"Enemy descends from its elevated home")
		_check(await _go_home() and ai.walker.jump_count==1,"Home return jumps up and skips passed breadcrumbs")
		platform.free()
		# Real map slope stays walking; real three-step stairs include a jump.
		var arena: Node3D=main.get_node("TestArena")
		await _terrain_actor(kind,arena.to_global(Vector3(-6,0,0.6)),arena.to_global(Vector3(-6,2,-7)))
		_check(await _travel_until(arena.to_global(Vector3(-6,2,-7))) and ai.walker.jump_count==0,"Actual ramp uses native walking without jumps")
		await _terrain_actor(kind,arena.to_global(Vector3(5,0,3)),arena.to_global(Vector3(5,1,-3.3)))
		_check(await _travel_until(arena.to_global(Vector3(5,1,-3.3))) and ai.walker.jump_count>=1,"Actual map stairs use low steps and a jump")
		_check(await _go_home(),"Actual map stair return completes")
	# Full capsule arc validation, floor corridor and home boundary.
	var platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _plan_actor()
	_check(not ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"Baseline 1m jump has a real supported landing")
	var ceiling:=_block(Vector3(2.8,2.3,0),Vector3(2.2,0.2,3))
	await _ticks(2)
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"Full-body arc rejects a low ceiling")
	ceiling.free()
	ai.settings.leash_radius=0.9
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"Landing beyond home range is rejected")
	ai.settings.leash_radius=9.0
	ai.settings.walk.jump_enabled=false
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"Jump can be disabled per enemy")
	ai.settings.walk.jump_enabled=true
	ai.global_position.y=0.4
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"No repeat takeoff while already airborne")
	ai.global_position.y=0.0
	var floor_body: StaticBody3D=main.get_node("TestArena/Terrain/FlatGround")
	floor_body.collision_layer=0
	var ledge:=_block(Vector3(1.6,-0.1,0),Vector3(1.8,0.2,3))
	await _ticks(2)
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"A real half-meter gap is not treated as a floor seam")
	ledge.free()
	floor_body.collision_layer=1
	platform.free()
	platform=_block(Vector3(4.5,0.65,0),Vector3(3,1.3,3))
	await _plan_actor()
	_check(ai.walker._jump_plan(Vector3.RIGHT).is_empty(),"Riser above maximum apex is rejected")
	platform.free()
	# Two successive 1m rises exercise cooldown without walking past the takeoff window.
	var first:=_block(Vector3(3.75,0.5,0),Vector3(1.5,1,3))
	var second:=_block(Vector3(6,1,0),Vector3(3,2,3))
	await _terrain_actor(0,Vector3.ZERO,Vector3(6.5,2,0))
	var trace:=_trace()
	_check(await _travel_until(Vector3(6.5,2,0),9.0),"Successive rises reach the upper platform")
	_check(trace.launches.size()==2 and ai.walker.jump_count==2,"Exactly one jump per high riser")
	if trace.launches.size()==2:
		_check(not trace.landings.is_empty() and float(trace.launches[1]-trace.landings[0])/60.0>=0.8-0.001,"Second launch waits for the full post-landing cooldown")
	first.free()
	second.free()
	# A real alternate profile changes the physical arc, not just serialized values.
	platform=_block(Vector3(4.5,0.25,0),Vector3(3,0.5,3))
	await _terrain_actor(1,Vector3.ZERO,Vector3(5,0.5,0))
	ai.settings.walk.jump_height=1.2
	ai.settings.walk.jump_takeoff_speed=7.2
	ai.settings.walk.jump_horizontal_speed=2.8
	trace=_trace()
	_check(await _travel_until(Vector3(5,0.5,0),7.0) and absf(trace.peak-1.2)<0.012,"Alternate enemy profile changes the apex to 1.2m")
	_check(is_equal_approx(ai.walker.jump_data.takeoff,7.2) and is_equal_approx(ai.walker.jump_data.speed,2.8) and trace.error<0.003,"Independent takeoff/horizontal speeds drive the same ballistic timeline")
	platform.free()
	# A reserved target waits on the floor, but an already airborne enemy must not hover.
	platform=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _terrain_actor(0,Vector3(2.1,0,0),Vector3(5,1,0))
	combat.state=combat.State.Guard
	combat.target=ai.targetable
	var held: Vector3=ai.global_position
	await _seconds(0.3)
	_check(ai.walker.jump_count==0 and ai.global_position.distance_to(held)<0.001,"Reserved enemy does not begin a jump from the floor")
	combat.cancel()
	_check(await _await_launch(),"Released enemy begins its safe jump")
	combat.state=combat.State.Guard
	combat.target=ai.targetable
	await _seconds(0.8)
	_check(not ai.walker.airborne() and ai.global_position.y>0.95 and ai.walker.jump_count==1,"Midair reservation does not suspend gravity or landing")
	combat.cancel()
	platform.free()
	# Moving/removing terrain after takeoff never warps or triggers an air jump.
	platform=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _terrain_actor(0,Vector3.ZERO,Vector3(5,1,0))
	_check(await _await_launch(),"Dynamic failure trial starts a real jump")
	var state_before: int=ai.state
	ai._start_windup()
	_check(ai.state==state_before,"Explicit windup request is refused while jumping")
	platform.free()
	await _seconds(1.5)
	_check(not ai.walker.busy() and ai.global_position.y<0.05 and ai.walker.jump_count==1,"Removed landing falls safely to existing ground, no repeated jump")
	platform=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	await _terrain_actor(1,Vector3.ZERO,Vector3(5,1,0))
	_check(await _await_launch(),"Missing-ground trial starts a mage jump")
	platform.free()
	floor_body.collision_layer=0
	await _seconds(3.0)
	_check(ai.walker.motion_mode==ai.walker.Motion.STRANDED and ai.velocity==Vector3.ZERO and ai.walker.jump_count==1 and ai.attack_count==0,"Missing all ground reaches a bounded safe stop, with no teleport or attack")
	floor_body.collision_layer=1
	# Cast state never runs the ordinary walk owner.
	await _fresh(1,Vector3(4.5,0,0))
	await _windup()
	await _seconds(0.3)
	_check(ai.state==ai.State.WINDUP and ai.walker.jump_count==0 and not ai.walker.busy(),"Mage casting remains stationary without ordinary jumping")
	var saved: Resource=ai.settings.walk.duplicate()
	saved.walking_step_height=0.28
	saved.jump_height=1.15
	saved.jump_takeoff_speed=7.0
	saved.jump_horizontal_speed=2.6
	saved.jump_cooldown_seconds=1.2
	_check(ResourceSaver.save(saved,"res://.godot/enemy_auto_jump_saved.tres")==OK,"Inspector jump tuning saves as a Resource")
	FileAccess.open("res://.godot/enemy_auto_jump_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(jump_metrics,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("ENEMY AUTO JUMP ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
