extends SceneTree
const Elevation=preload("res://scripts/combat/elevation_path.gd")
var main: Node3D
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(5): await physics_frame; await process_frame
	var player: CharacterBody3D=main.get_node("Player")
	var enemy: CharacterBody3D=main.get_node("PracticeSelector").active_enemy
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.global_position=Vector3(3.3,1.003,5)
	enemy.global_position=Vector3(-0.89,0.253,5)
	var edge:=OS.get_cmdline_user_args().has("--edge")
	if edge:
		player.global_position.z=3.1
	var weapon: Resource=player.combat.equipped_weapon
	if EngineDebugger.has_profiler("scripts"): EngineDebugger.profiler_enable("scripts",true)
	var valid:=true
	for i in range(3):
		var at:=Time.get_ticks_usec()
		var result:=Elevation.attack(player,enemy.global_position,weapon,player.combat.settings,player.combat.settings.stop_distance,weapon.motion)
		print("MICRO ATTACK ",Time.get_ticks_usec()-at," us valid=",not result.is_empty())
		valid=valid and (result.is_empty() if edge else not result.is_empty())
	if EngineDebugger.has_profiler("scripts"): EngineDebugger.profiler_enable("scripts",false)
	main.free()
	quit(0 if valid else 1)
