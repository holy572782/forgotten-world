extends SceneTree
const Elevation=preload("res://scripts/combat/elevation_path.gd")
const Budget=preload("res://scripts/combat/planning_budget.gd")
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
var main: Node3D
var player: CharacterBody3D
var enemy: CharacterBody3D
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)
func ticks(count: int) -> void:
	for i in range(count): await physics_frame; await process_frame
func block(at: Vector3) -> StaticBody3D:
	var wall:=StaticBody3D.new()
	wall.collision_layer=1
	var shape:=CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=Vector3(0.2,2,4)
	wall.add_child(shape)
	main.add_child(wall)
	wall.position=at
	return wall
func _run() -> void:
	Engine.max_fps=60
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await ticks(6)
	player=main.get_node("Player")
	enemy=main.get_node("PracticeSelector").active_enemy
	var config: Resource=main.get_node("PracticeSelector").performance_diagnostics
	main.get_node("PracticeSelector").set_process(false)
	enemy.set_physics_process(false)
	player.combat.cancel()
	player.reset_motion(Vector3(-6,0.003,0))
	enemy.global_position=Vector3(-4.8,0.003,0)
	enemy.home=enemy.global_position
	await ticks(4)
	player.set_physics_process(false)
	check(config==enemy.performance_diagnostics and config==player.combat.performance_diagnostics,"Selector shares the four switches with both planning owners")
	check(config.local_astar_enabled and config.attack_planning_enabled and config.terrain_search_enabled and config.details_enabled,"All diagnostic switches default ON")
	check(not config.capture_timings and not config.print_report,"Normal play has no timing collection or log spam")
	var target: Node3D=enemy.targetable
	var combat=player.combat
	check(combat.can_select(target),"Actual sword can reach nearby enemy")
	combat._update_markers()
	check(not combat._preview_cache.is_empty(),"A validated display hint is stored")
	var wall:=block(Vector3(-5.4,1,0))
	await ticks(1)
	check(not combat.request_attack(target),"Input freshly rejects a wall added after a positive display hint")
	check(not combat.is_busy(),"Rejected stale hint cannot enter attack movement")
	wall.free()
	await ticks(1)
	config.attack_planning_enabled=false
	check(not combat.can_select(target) and not combat.request_attack(target),"B OFF rejects player planning and input even if cached hints exist")
	enemy._start_windup()
	check(enemy.state!=enemy.State.WINDUP and enemy.attack_count==0,"B OFF prevents a new enemy attack")
	config.attack_planning_enabled=true
	check(combat.can_select(target),"B ON restores freshly validated attacks")
	combat.selected_target=null
	combat._preview_cache.clear()
	combat._preview_jobs.clear()
	while Budget.take(): pass
	var attack:=InputEventAction.new()
	attack.action="attack"
	attack.pressed=true
	combat._unhandled_input(attack)
	combat.physics_step(1.0/60.0)
	check(combat.is_busy(),"Keyboard attack resolves a fresh target even while advisory planning has no budget")
	combat.cancel()
	config.details_enabled=false
	enemy._update_attack_debug()
	check(not enemy.debug_label.visible,"D OFF hides detailed drawing")
	config.details_enabled=true
	enemy._update_attack_debug()
	check(enemy.debug_label.visible,"D ON restores detailed drawing")
	# C OFF must block the step, while previously airborne motion is still allowed to land.
	player.global_position=Vector3(8,0.003,10)
	enemy.global_position=Vector3(1.3,0.503,5)
	enemy.home=enemy.global_position
	enemy.walker=load("res://scripts/enemies/enemy_walk.gd").new(enemy)
	await ticks(2)
	config.terrain_search_enabled=false
	check(enemy.walker._jump_plan(Vector3.RIGHT).is_empty(),"C OFF disables new jump plans")
	for i in range(60):
		enemy.walker.walk(Vector3(3.3,1,5),1.0/60.0,2.0)
		await ticks(1)
	check(enemy.walker.jump_count==0 and enemy.position.x<1.65,"C OFF stops at a riser without penetrating it")
	config.terrain_search_enabled=true
	# Back off to a valid takeoff point: enabling a switch must not authorize
	# a capsule already pressed against a high riser to tunnel through its lip.
	enemy.global_position=Vector3(1.1,0.503,5)
	enemy.walker=load("res://scripts/enemies/enemy_walk.gd").new(enemy)
	await ticks(2)
	check(not enemy.walker._jump_plan(Vector3.RIGHT).is_empty(),"C ON restores a proven safe jump")
	config.capture_timings=true
	config.reset()
	# Exhaust budget BEFORE entering the router: no long can_reach/jump preflight is allowed.
	while Budget.take(): pass
	var destination: Vector3=enemy._pursuit_route.goal(enemy,player.position,1.0/60.0)
	check(not destination.is_finite() and not config.timings.has("walk.can_reach") and not config.timings.has("walk.jump_plan"),"Shared frame budget covers route preflights, not just A* edges")
	check(enemy._pursuit_route.reason.contains("BUDGET"),"Budget deferral has a concrete safe-stop reason")
	# Switching A OFF cancels a queued search without evaluating an edge.
	config.local_astar_enabled=false
	enemy._pursuit_route._begin_search(enemy,player.position)
	await ticks(1)
	config.reset()
	enemy._pursuit_route._advance_search(enemy)
	check(enemy._pursuit_route._search.is_empty() and not config.timings.has("walk.can_reach"),"A OFF cancels only speculative search and evaluates no edges")
	config.local_astar_enabled=true
	# Incremental and complete plans must agree on fixed, real terrain.
	player.global_position=Vector3(3.3,1.003,5)
	enemy.global_position=Vector3(-0.89,0.253,5)
	await ticks(2)
	var weapon: Resource=combat.equipped_weapon
	var complete:=Elevation.attack(player,enemy.position,weapon,combat.settings,combat.settings.stop_distance,weapon.motion)
	var job:=Elevation.new_attack_job()
	for i in range(64):
		if job.done: break
		Elevation.attack_step(player,enemy.position,weapon,combat.settings,combat.settings.stop_distance,weapon.motion,Vector3.INF,job)
	check(job.done and job.result.is_empty()==complete.is_empty(),"Incremental search agrees with complete safety proof")
	if not complete.is_empty(): check(job.result.destination.distance_to(complete.destination)<0.00001,"Incremental result retains the same safe landing")
	player.global_position.z=3.1 # Native contact can stand here, but a full takeoff footprint cannot.
	await ticks(2)
	var edge_job:=Elevation.new_attack_job()
	var edge_reason: Dictionary={"enabled":true}
	Elevation.attack_step(player,enemy.position,weapon,combat.settings,combat.settings.stop_distance,weapon.motion,Vector3.INF,edge_job,edge_reason)
	check(edge_job.done and edge_job.result.is_empty() and edge_reason.reason=="NO_SAFE_TAKEOFF","Unsafe stair-edge takeoff is rejected before scanning all destinations")
	var data: Dictionary=config.report()
	check(data.has("physics_ms") and data.has("context") and data.enabled.B_attack,"Live report includes physics time, context and switch settings")
	var saved_path: String="res://.godot/work_diagnostics_saved.tres"
	config.terrain_search_enabled=false
	check(ResourceSaver.save(config,saved_path)==OK,"Diagnostic settings can be saved as a Resource")
	var saved: Resource=ResourceLoader.load(saved_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(not saved.terrain_search_enabled,"Saved switches reload without changing combat balance Resources")
	main.free()
	for failure in failures: push_error(failure)
	print("ENEMY WORK DIAGNOSTICS ","PASS" if failures.is_empty() else "FAIL",": ",checks)
	quit(0 if failures.is_empty() else 1)
