extends "res://tests/enemy_terrain.gd"
const Elevation=preload("res://scripts/combat/elevation_path.gd")
var air_samples:=0
func _setup(upward: bool, soldier: bool) -> StaticBody3D:
	await _fresh_sword(4.5)
	combat.equipped_weapon=load("res://resources/weapons/one_handed_sword.tres").duplicate()
	# Floor edge lies between both endpoints, with adequate landing footprints.
	var platform:=_block(Vector3(4.5,0.5,0),Vector3(3,1,3))
	var low:=Vector3.ZERO
	var high:=Vector3(4.5,1,0)
	ai.global_position=high if upward!=soldier else low
	ai.home=ai.global_position
	ai.walker=load("res://scripts/enemies/enemy_walk.gd").new(ai)
	player.reset_motion(low if upward!=soldier else high)
	await _ticks(8)
	main.get_node("CameraRig").snap_to_target()
	return platform

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
	for soldier in [false,true]:
		for upward in [true,false]:
			var platform:=await _setup(upward,soldier)
			var attacker: CharacterBody3D=ai if soldier else player
			var defender: CharacterBody3D=player if soldier else ai
			var weapon: WeaponData=ai.active_attack.weapon if soldier else combat.equipped_weapon
			var path: Resource=ai.settings.path if soldier else combat.settings
			var plan:=Elevation.attack(attacker,defender.global_position,weapon,path,1.1,weapon.motion)
			print("PLAN ",soldier," ",upward," ",plan)
			_check(not plan.is_empty() and not plan.in_place and plan.out.air and plan.back.air,"Bidirectional jump plan is safe")
			var anchor: Vector3=attacker.global_position
			if soldier:
				ai._start_windup()
				ai.set_physics_process(true)
			else: _check(combat.request_attack(ai.targetable),"Marker and attack agree on safe jump")
			var saw_air:=false
			var saw_attack:=false
			for tick in range(450):
				await _ticks(1)
				var flight: RefCounted=ai._flight if soldier else combat._flight
				if flight.active:
					air_samples+=1
					saw_air=true
					_check(attacker.velocity.length()<30.0,"Flight has bounded real movement")
				var attacking: bool=ai.state==ai.State.ATTACK if soldier else combat.state==combat.State.Attack
				if attacking:
					saw_attack=true
					_check(not flight.active and Elevation.supported(attacker,attacker.global_position),"Attack waits until supported landing")
				if saw_attack and (ai.state==ai.State.RECOVERY if soldier else not combat.is_busy()): break
			_check(saw_air and saw_attack and attacker.global_position.distance_to(anchor)<0.03,"Up/down jump attacks and returns to the original floor")
			_check(health.current_hp==90 if soldier else ai.health.current_hp==30,"Jump swing deals damage exactly once")
			platform.free()
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("ELEVATION DASH ","PASS" if failures.is_empty() else "FAIL",": ",assertions," air samples=",air_samples)
	quit(0 if failures.is_empty() else 1)
