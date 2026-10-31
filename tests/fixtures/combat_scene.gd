extends RefCounted
## Fixed combat test geometry, independent of the editable F5 practice layout.
static func create() -> Node3D:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	# Fixed timing as well as geometry; never rewrite the user's F5 tuning Resource.
	var combat := scene.get_node("Player/TargetDash")
	combat.equipped_weapon = combat.equipped_weapon.duplicate()
	combat.equipped_weapon.motion = preload("res://scripts/combat/attack_motion_settings.gd").new()
	# Range/window are also user-tunable; keep historical regression scenarios fixed.
	combat.equipped_weapon.melee_reach = 1.4
	# Preserve the historical flat-ground fixture. Elevation suites use the production sword.
	combat.equipped_weapon.hit_height_up=-1.0
	combat.equipped_weapon.hit_height_down=-1.0
	combat.equipped_weapon.elevation_travel=null
	combat.equipped_weapon.combo_input_window = 0.5
	scene.get_node("PracticeSelector").initial_mode = 0 # Legacy combat trials use stationary targets.
	scene.get_node("PracticeSelector").debug_unlimited_pursuit=false # Historical leash tests use formal rules.
	scene.get_node("PracticeSelector").show_enemy_diagnostics=false
	scene.get_node("TrainingEnemy").position = Vector3(-3,0,-2)
	scene.get_node("TrainingEnemySecond").position = Vector3(-8,0,-2)
	scene.get_node("TrainingEnemyThird").position = Vector3(-5.5,0,-4)
	var extra := scene.get_node_or_null("TrainingEnemy2")
	if extra != null: extra.free()
	return scene
