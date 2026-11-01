extends SceneTree
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
var main: Node3D
var player: CharacterBody3D
var enemy: CharacterBody3D
var config: Resource
var rows: Array[Dictionary]=[]
var corner:=false
var edge:=false
class PhysicsTimer extends Node:
	var started:=0
	var recording:=false
	var samples: Array[float]=[]
	func _ready() -> void:
		process_physics_priority=1000000
		get_tree().physics_frame.connect(_start)
	func _start() -> void: started=Time.get_ticks_usec()
	func _physics_process(_delta: float) -> void:
		if recording: samples.append(float(Time.get_ticks_usec()-started)/1000.0)
var physics_timer: PhysicsTimer

func _initialize() -> void: call_deferred("_run")
func _ticks(count: int) -> void:
	for i in range(count): await physics_frame; await process_frame

func _place() -> void:
	player.combat.cancel()
	player.reset_motion(Vector3(3.3,1.003,5))
	enemy.global_position=Vector3(3.3-sqrt(4.19*4.19-2.4*2.4),0.003,2.6) if corner else Vector3(-0.89,0.253,5)
	if edge:
		player.global_position.z=3.1
		enemy.global_position.z=3.1
	enemy.home=enemy.global_position
	enemy.walker=load("res://scripts/enemies/enemy_walk.gd").new(enemy)
	enemy.attack_count=1
	enemy._combat_move_index=0
	enemy.cooldown=3.0
	enemy._set_state(enemy.State.RECOVERY)
	main.get_node("CameraRig").snap_to_target()

func _measure(label: String) -> void:
	_place()
	var warm:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm<1100000: await process_frame
	_place()
	config.reset()
	physics_timer.samples.clear()
	physics_timer.recording=true
	var started:=Time.get_ticks_usec()
	var last:=started
	var frames: Array[float]=[]
	var physics: Array[float]=[]
	var states: Dictionary={}
	var moves: Dictionary={}
	while Time.get_ticks_usec()-started<2000000:
		await process_frame
		var now:=Time.get_ticks_usec()
		frames.append(float(now-last)/1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		states[enemy.State.keys()[enemy.state]]=states.get(enemy.State.keys()[enemy.state],0)+1
		moves[enemy.walker.blocked_reason]=moves.get(enemy.walker.blocked_reason,0)+1
		last=now
	var seconds:=float(Time.get_ticks_usec()-started)/1000000.0
	physics_timer.recording=false
	frames.sort(); physics.sort()
	physics_timer.samples.sort()
	var row: Dictionary={"case":label,"fps":frames.size()/seconds,"seconds":seconds,"frame_p95_ms":frames[int(frames.size()*0.95)],"frame_max_ms":frames[-1],"physics_p95_ms":physics[int(physics.size()*0.95)],"timings":config.timings.duplicate(true),"states":states,"moves":moves,"enemy":enemy.global_position,"player":player.global_position,"move":enemy.walker.blocked_reason,"start":enemy.attack_start_reason}
	rows.append(row)
	row["node_physics_p95_ms"]=physics_timer.samples[int(physics_timer.samples.size()*0.95)]
	print("WORK PERF ",JSON.stringify(row))

func _run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(1152,720)
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	physics_timer=PhysicsTimer.new()
	main.add_child(physics_timer)
	await _ticks(6)
	player=main.get_node("Player")
	enemy=main.get_node("PracticeSelector").active_enemy
	config=main.get_node("PracticeSelector").performance_diagnostics
	# Prevent the optional one-second Inspector report from clearing test counters.
	main.get_node("PracticeSelector").set_process(false)
	config.capture_timings=true
	var args:=OS.get_cmdline_user_args()
	var phase: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	corner=args.has("--corner")
	edge=args.has("--edge")
	await _measure("all_on")
	for key in ["local_astar_enabled","attack_planning_enabled","terrain_search_enabled","details_enabled"]:
		config.set(key,false)
		await _measure(key+"_off")
		config.set(key,true)
	# Additional cut isolates the previously unmeasured player's preview.
	player.set_physics_process(false)
	await _measure("player_updates_off")
	player.set_physics_process(true)
	config.capture_timings=false
	await _measure("timers_off")
	FileAccess.open("res://.godot/enemy_work_"+phase+".json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	main.queue_free()
	await process_frame
	quit()
