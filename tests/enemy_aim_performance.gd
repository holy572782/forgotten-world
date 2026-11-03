extends SceneTree
## Actual main scene/player/weapon, AI attacks and mixed enemies; no legacy fixture.
const Enemy = preload("res://scenes/enemies/practice_enemy.tscn")
const TimerSource = preload("res://tests/enemy_work_performance.gd")
var main: Node3D
var actors: Array[CharacterBody3D] = []
var rows: Array[Dictionary] = []

func _initialize() -> void: call_deferred("_run")
func _ticks(count: int) -> void:
	for i in range(count): await physics_frame; await process_frame

func _floor(body: CharacterBody3D, at: Vector3) -> Vector3:
	var collision := KinematicCollision3D.new()
	var above := at+Vector3.UP*3.0
	if not body.test_move(Transform3D(body.global_basis,above),Vector3.DOWN*5.0,collision,body.safe_margin):
		push_error("Performance fixture has no ground: "+str(at))
		quit(1)
	return above+collision.get_travel()

func _case(terrain: String, kinds: Array, unlimited: bool) -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode = 0
	root.add_child(main)
	await _ticks(4)
	var player: CharacterBody3D = main.get_node("Player")
	var selector: Node = main.get_node("PracticeSelector")
	var config: Resource = selector.performance_diagnostics
	selector.set_process(false)
	config.capture_timings = true
	var timer = TimerSource.PhysicsTimer.new()
	main.add_child(timer)
	var arena: Node3D = main.get_node("TestArena")
	var victim := Vector3(-6,0,0)
	var attacker := Vector3(-2.5,0,0)
	if terrain == "ramp":
		victim = arena.to_global(Vector3(-6,0,-4.5))
		attacker = arena.to_global(Vector3(-6,0,-1.5))
	elif terrain == "stairs":
		victim = arena.to_global(Vector3(5,1,-3))
		attacker = arena.to_global(Vector3(5,0.25,1))
	if "--descent" in OS.get_cmdline_user_args():
		if terrain == "ramp":
			victim = arena.to_global(Vector3(-6,0,0.5))
			attacker = arena.to_global(Vector3(-6,2,-7))
		elif terrain == "stairs":
			victim = arena.to_global(Vector3(5,0,5.5))
			attacker = arena.to_global(Vector3(5,1,-3.3))
	if "--edge" in OS.get_cmdline_user_args():
		if terrain=="ramp":
			victim=arena.to_global(Vector3(-6,0,-3.3))
			attacker=arena.to_global(Vector3(-6,0,-2))
		elif terrain=="stairs":
			victim=arena.to_global(Vector3(6.3,1,-3))
			attacker=arena.to_global(Vector3(7.5,0,-3))
	player.reset_motion(_floor(player,victim))
	actors.clear()
	for index in range(kinds.size()):
		var actor: CharacterBody3D = Enemy.instantiate()
		actor.name = "PerfEnemy"+str(index)
		actor.settings = load("res://resources/enemies/melee_practice.tres" if kinds[index] == 0 else "res://resources/enemies/ranged_practice.tres")
		actor.player = player
		actor.performance_diagnostics = config
		actor.debug_unlimited_pursuit = unlimited
		actor.show_attack_diagnostics = true
		actor.position = attacker+Vector3(0,0,-1.5*index)
		main.add_child(actor)
		actor.global_position = _floor(actor,actor.global_position)
		actor.home = actor.global_position
		if "--descent" in OS.get_cmdline_user_args() or "--edge" in OS.get_cmdline_user_args():
			# Model an already engaged enemy after the player retreats downstairs.
			# The far stair endpoint is outside initial detection, within home leash.
			actor._set_state(actor.State.CHASE)
		actors.append(actor)
	main.get_node("CameraRig").snap_to_target()
	await _ticks(4)
	config.reset()
	timer.samples.clear()
	timer.recording = true
	var start := Time.get_ticks_usec()
	var previous := start
	var frames: Array[float] = []
	var physics: Array[float] = []
	var states: Dictionary = {}
	while Time.get_ticks_usec()-start < 3000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		for actor in actors:
			var key: String = actor.State.keys()[actor.state]
			states[key] = states.get(key,0)+1
		previous = now
	var duration := float(Time.get_ticks_usec()-start)/1000000.0
	timer.recording = false
	frames.sort(); physics.sort(); timer.samples.sort()
	var attacks := 0
	for actor in actors: attacks += actor.attack_count
	var row: Dictionary = {"terrain":terrain,"kinds":kinds,"unlimited":unlimited,"seconds":duration,"fps":frames.size()/duration,"frame_max_ms":frames[-1],"frame_p95_ms":frames[int(frames.size()*0.95)],"physics_p95_ms":physics[int(physics.size()*0.95)],"node_physics_p95_ms":timer.samples[int(timer.samples.size()*0.95)],"attacks":attacks,"states":states,"timings":config.timings.duplicate(true)}
	rows.append(row)
	print("AIM PERF ",JSON.stringify(row))
	main.free()
	await _ticks(3)

func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1152,720)
	for unlimited in [false,true]:
		for terrain in ["flat","ramp","stairs"]:
			for kind in [0,1]: await _case(terrain,[kind],unlimited)
		await _case("flat",[0,1],unlimited)
	var args := OS.get_cmdline_user_args()
	var label: String = args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/aim_performance_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	quit()
