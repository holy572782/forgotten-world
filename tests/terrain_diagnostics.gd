extends "res://tests/enemy_terrain.gd"
func _run() -> void:
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(5)
	for enabled in [false,true]:
		await _fresh_sword(2.0)
		ai.show_debug_state=false
		ai.show_attack_diagnostics=enabled
		await _windup()
		await _finish_strike()
		_check(health.current_hp==90 and ai.attack_count==1,"Diagnostics toggle cannot add damage or change attack count")
		if enabled: _check(ai.attack_start_reason=="OK" and ai.attack_hit_reason=="OK" and ai.debug_label.visible,"Live debug separates planning and actual hit")
	var d: Dictionary={"enabled":true}
	var plan: Dictionary=load("res://scripts/combat/elevation_path.gd").attack(ai,ai.global_position+Vector3.RIGHT*30,ai.active_attack.weapon,ai.settings.path,1.1,ai.active_attack.weapon.motion,Vector3.INF,d)
	_check(plan.is_empty() and d.reason=="OUT_OF_RANGE","Planner reports out-of-range without confusing it with hit failure")
	main.queue_free()
	await _ticks(3)
	for failure in failures: push_error(failure)
	print("TERRAIN DIAGNOSTICS ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
