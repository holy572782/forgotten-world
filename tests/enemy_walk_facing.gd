extends "res://tests/enemy_tactics.gd"
var aligned_samples := 0

class TinyGoalStep extends Node:
	var actor: CharacterBody3D
	var direction: Vector3
	var goal := Vector3.ZERO
	var completed := false
	func _physics_process(delta: float) -> void:
		goal=actor.global_position+direction*actor.settings.chase_speed*delta
		actor._walk_towards(goal,delta)
		completed=true
		set_physics_process(false)

func _after_attack(kind: int) -> void:
	player.set_physics_process(true)
	if kind==0:
		await _fresh_sword(4.5)
		await _windup()
		await _finish_strike()
	else:
		await _fresh(1,Vector3(4.5,0,0))
		await _windup()
		await _state(ai.State.RECOVERY)
		ai.clear_shots()
	ai.set_physics_process(false)
	_check(ai.attack_count==1 and ai.state==ai.State.RECOVERY,"Facing trial begins after one actual attack and its existing return/recovery")

func _aligned(label: String) -> void:
	var motion:=Vector3(ai.velocity.x,0,ai.velocity.z)
	if motion.length_squared()<=0.0001: return
	aligned_samples+=1
	_check(ai.facing.dot(motion.normalized())>0.999,"Facing follows real horizontal movement: "+label)
	var body: AnimatedSprite3D=ai.get_node("AnimatedSprite3D")
	body._process(0.0)
	var side: String=body.SIDES[Controller.direction_sector(motion,main.get_node("CameraRig").camera.global_basis,4)]
	_check(body.animation==StringName("walk_"+side),"Actual four-direction Walk row matches travel and camera: "+label)

func _done() -> void:
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("ENEMY WALK FACING ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; samples=",aligned_samples,"; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)

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
	for kind in [0,1]:
		await _after_attack(kind)
		for yaw in [0.0,90.0,180.0,270.0]:
			main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
			main.get_node("CameraRig").snap_to_target()
			for direction in [Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.FORWARD]:
				# Exact consumed one-tick goals reproduced the reported regression.
				ai.facing=-direction
				var step:=TinyGoalStep.new()
				step.actor=ai
				step.direction=direction
				ai.add_child(step)
				for frame in range(5):
					if step.completed: break
					await _ticks(1)
				_check(step.completed and ai.walker.horizontal(ai.global_position,step.goal)<0.001,"The small physics-tick goal is actually consumed")
				step.queue_free()
				_aligned("kind=%s yaw=%s" % [kind,yaw])
		var held: Vector3=ai.facing
		ai._walk_towards(ai.global_position,1.0/60.0)
		_check(ai.facing==held,"Idle/zero horizontal movement retains the last valid facing")
		if "--repro" in OS.get_cmdline_user_args():
			await _done()
			return
	# Natural soldier recovery strafes, approaches and retreats after its real strike.
	await _after_attack(0)
	ai.active_attack.recovery_seconds=8.0
	ai.set_physics_process(true)
	var directions: Dictionary={}
	for tick in range(150):
		if tick%40==0:
			main.get_node("CameraRig").rotation.y=deg_to_rad(float(tick/40)*90.0)
			main.get_node("CameraRig").snap_to_target()
		await _ticks(1)
		_aligned("natural soldier recovery")
		if ai.velocity.length_squared()>0.01: directions[ai.combat_move_mode]=true
	_check(directions.size()>=2,"Real recovery exercises multiple combat movement directions")
	# Mage recovery re-chases a moved player in every world/camera quadrant.
	await _after_attack(1)
	ai.set_physics_process(true)
	var index:=0
	for direction in [Vector3.RIGHT,Vector3.BACK,Vector3.LEFT,Vector3.FORWARD]:
		player.reset_motion(ai.home+direction*7.0)
		player.set_physics_process(false)
		main.get_node("CameraRig").rotation.y=deg_to_rad(index*90.0)
		main.get_node("CameraRig").snap_to_target()
		for tick in range(15):
			await _ticks(1)
			_aligned("natural mage re-chase")
		index+=1
	_check(ai.attack_count==1 and ai.state==ai.State.RECOVERY,"Re-facing never bypasses mage's existing cooldown")
	# The continuation branch of a safe horizontal climb must also update facing.
	await _after_attack(0)
	ai.facing=Vector3.LEFT
	ai.walker.climb.assign([ai.global_position+Vector3.BACK*0.2])
	ai.walker.climb_speed=2.0
	ai.set_physics_process(true)
	for tick in range(5):
		await _ticks(1)
		_aligned("continued climb")
	_check(aligned_samples>100,"Real moving samples were observed")
	await _done()
