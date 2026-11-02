extends "res://tests/enemy_terrain.gd"
const Route=preload("res://scripts/enemies/enemy_pursuit_route.gd")

class CountingEnemy:
	extends "res://scripts/enemies/practice_enemy.gd"
	var evaluations:=0
	var plans:=0
	func _evaluate_attack_position() -> bool:
		evaluations+=1
		return super._evaluate_attack_position()
	func _plan_attack() -> bool:
		plans+=1
		return super._plan_attack()

class CountingWalker:
	extends RefCounted
	var probes:=0
	func horizontal(a: Vector3,b: Vector3) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
	func _sample(at: Vector3) -> Dictionary: return {"position":at}
	func can_reach(_at: Vector3,_clear: bool=true,_from: Vector3=Vector3.INF) -> bool:
		probes+=1
		return true

class SearchActor:
	extends CharacterBody3D
	var walker:=CountingWalker.new()

func _run() -> void:
	Engine.max_fps=60
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	await _ticks(4)
	player.reset_motion(origin)
	player.set_physics_process(false)
	ai=EnemyScene.instantiate()
	ai.set_script(CountingEnemy)
	ai.settings=load("res://resources/enemies/melee_practice.tres").duplicate(true)
	ai.player=player
	ai.position=origin+Vector3(1.2,0,0)
	main.add_child(ai)
	ai.set_physics_process(false)
	await _ticks(3)
	_check(ai._attack_position_available(),"Real sword has a valid initial plan")
	for i in range(100): _check(ai._attack_position_available(),"Same-frame eligibility reuses its positive result")
	_check(ai.evaluations==1,"100 duplicate calls perform one expensive evaluation")
	var wall:=_block((ai.position+player.position)*0.5+Vector3.UP,Vector3(0.2,2,4))
	await _ticks(2)
	_check(ai._attack_position_available(),"Eligibility may briefly retain positive intent")
	ai._start_windup()
	_check(ai.plans==0 and ai.state!=ai.State.WINDUP,"Fresh recognition rejects a new wall without a synchronous landing search")
	_check(ai.attack_count==0 and health.current_hp==100,"A stale positive cannot launch or damage")
	_check(not ai._attack_position_available(),"Changed attack snapshot invalidates eligibility")
	var count: int=ai.evaluations
	for i in range(100): _check(not ai._attack_position_available(),"Failed plans are cached too")
	_check(ai.evaluations==count,"100 failed calls do not repeat geometry searches")
	player.position.z+=0.2
	ai._attack_position_available()
	_check(ai.evaluations==count+1,"Target displacement invalidates a failed result")
	ai.position.z+=0.2
	ai._attack_position_available()
	_check(ai.evaluations==count+2,"Actor displacement invalidates a failed result")
	await _seconds(0.45) # Failed eligibility is now retained for 0.4 seconds.
	ai._attack_position_available()
	_check(ai.evaluations==count+3,"Stationary failures expire and can discover geometry changes")
	wall.free()
	ai.position=origin+Vector3(3,0,0)
	var hint:=Route.new()
	var first:=ai.position+Vector3(0,0,0.02)
	var second:=ai.position+Vector3(0,0,0.04)
	_check(hint.goal(ai,first,1.0/60.0)==first,"A grounded one-tick move is safe")
	_check(hint.goal(ai,second,1.0/60.0)==second,"Cached direct intent keeps the latest one-tick goal instead of freezing mage movement")
	# A controlled walker measures scheduling, while real terrain suites verify
	# each unchanged safety predicate separately.
	var actor:=SearchActor.new()
	main.add_child(actor)
	var routes: Array[RefCounted]=[Route.new(),Route.new()]
	for route in routes: route._begin_search(actor,Vector3(6,0,0))
	for repeat in range(100):
		for route in routes: route._advance_search(actor)
	_check(actor.walker.probes<=Route.EDGES_PER_FRAME,"Shared budget caps edges across enemies and repeated physics ticks")
	var old:=actor.walker.probes
	await process_frame
	for route in routes: route._advance_search(actor)
	_check(actor.walker.probes>old and actor.walker.probes-old<=Route.EDGES_PER_FRAME,"Next rendered frame resumes within the same bound")
	for route in routes:
		route.reset()
		_check(route._search.is_empty() and route.waypoints.is_empty() and route.reason.is_empty(),"State changes cancel searches and cached intent")
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("PURSUIT BUDGET ","PASS" if failures.is_empty() else "FAIL",": ",assertions," checks")
	quit(0 if failures.is_empty() else 1)
