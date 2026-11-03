extends SceneTree
const Enemy=preload("res://scenes/enemies/practice_enemy.tscn")
var rows: Array[Dictionary]=[]
func _initialize() -> void: call_deferred("_run")
func _ticks(n: int) -> void:
	for i in range(n): await physics_frame; await process_frame
func _floor(body: CharacterBody3D, at: Vector3) -> Vector3:
	var c:=KinematicCollision3D.new()
	var top:=at+Vector3.UP*3
	assert(body.test_move(Transform3D(body.global_basis,top),Vector3.DOWN*5,c))
	return top+c.get_travel()
func _box(world: Node3D,at: Vector3,size: Vector3) -> void:
	var b:=StaticBody3D.new(); b.collision_layer=1; b.collision_mask=0
	var s:=CollisionShape3D.new(); s.shape=BoxShape3D.new(); s.shape.size=size
	var mesh:=MeshInstance3D.new(); mesh.mesh=BoxMesh.new(); mesh.mesh.size=size
	var material:=StandardMaterial3D.new(); material.albedo_color=Color(0.45,0.55,0.65); mesh.material_override=material
	b.add_child(s); b.add_child(mesh); world.add_child(b); b.global_position=at
func _case(label: String,kinds: Array,unlimited: bool) -> void:
	var main: Node3D=load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode=0; root.add_child(main)
	await _ticks(3)
	for node in main.get_children():
		if node is StaticBody3D and node.has_node("Targetable"): node.free()
	var p: CharacterBody3D=main.get_node("Player")
	var selector: Node=main.get_node("PracticeSelector"); selector.set_process(false)
	var config: Resource=selector.performance_diagnostics; config.capture_timings=true
	var at:=Vector3(0,0,8); var goal:=Vector3(4,0,8)
	var arena: Node3D=main.get_node("TestArena")
	if label=="ramp":
		at=arena.to_global(Vector3(-6,0,-1)); goal=arena.to_global(Vector3(-6,2,-7))
	elif label=="stairs":
		at=arena.to_global(Vector3(5,0,3)); goal=arena.to_global(Vector3(5,1,-3.3))
	p.reset_motion(_floor(p,goal))
	var actors: Array[CharacterBody3D]=[]
	for kind in kinds:
		var e: CharacterBody3D=Enemy.instantiate()
		e.settings=load("res://resources/enemies/melee_practice.tres" if kind==0 else "res://resources/enemies/ranged_practice.tres").duplicate(true)
		e.player=p; e.position=at+Vector3(0,0,-1.5*actors.size()); e.debug_unlimited_pursuit=unlimited; e.performance_diagnostics=config
		e.show_attack_diagnostics=true
		main.add_child(e); e.global_position=_floor(e,e.global_position); e.home=e.global_position
		e._set_state(e.State.CHASE); e.last_seen_position=p.global_position; e._last_seen_valid=true
		actors.append(e)
	if label in ["wall_left","wall_right"]: _box(main,Vector3(2,1.5,7.2 if label=="wall_left" else 8.8),Vector3(0.3,3,3.6))
	elif label.begins_with("wall"): _box(main,Vector3(2,1.5,8),Vector3(0.3,3,2))
	elif label=="closed":
		for item in [[Vector3(1,1.5,8),Vector3(0.2,3,4)],[Vector3(-1,1.5,8),Vector3(0.2,3,4)],[Vector3(0,1.5,6),Vector3(2,3,0.2)],[Vector3(0,1.5,10),Vector3(2,3,0.2)]]: _box(main,item[0],item[1])
	# Performance monitors update periodically. Warm each fresh scene beyond
	# that interval so startup/import or the previous placement is not sampled.
	main.get_node("CameraRig").snap_to_target(); await _ticks(75); config.reset()
	var start:=Time.get_ticks_usec(); var previous:=start
	var frames: Array[float]=[]; var physics: Array[float]=[]; var states: Dictionary={}
	while Time.get_ticks_usec()-start<3000000:
		await process_frame
		var now:=Time.get_ticks_usec(); frames.append((now-previous)/1000.0); previous=now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		for e in actors: states[e.State.keys()[e.state]]=states.get(e.State.keys()[e.state],0)+1
	var seconds: float=(Time.get_ticks_usec()-start)/1000000.0
	frames.sort(); physics.sort()
	var row: Dictionary={"case":label,"kinds":kinds,"unlimited":unlimited,"seconds":seconds,"fps":frames.size()/seconds,"physics_p95_ms":physics[int(physics.size()*0.95)],"frame_max_ms":frames[-1],"states":states,"timings":config.timings.duplicate(true)}
	rows.append(row); print("SEARCH PERF ",JSON.stringify(row))
	main.queue_free(); await _ticks(4)
func _run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1152,720)
	for unlimited in [false,true]:
		for spec in [["empty",[]],["wall_melee",[0]],["wall_mage",[1]],["wall_both",[0,1]],["closed",[0,1]],["ramp",[0,1]],["stairs",[0,1]]]: await _case(spec[0],spec[1],unlimited)
		if "--policy" in OS.get_cmdline_user_args():
			for name in ["wall_left","wall_right"]: await _case(name,[0,1],unlimited)
	var args:=OS.get_cmdline_user_args(); var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/search_performance_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	quit()
