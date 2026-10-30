extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var reload: bool="--reload" in OS.get_cmdline_user_args()
	var weapon: Resource=load("res://.godot/elevation_saved.tres" if reload else "res://resources/weapons/one_handed_sword.tres")
	if not reload:
		weapon=weapon.duplicate(true)
		weapon.hit_height_up=1.7
		weapon.hit_height_down=1.6
		weapon.elevation_travel=weapon.elevation_travel.duplicate()
		weapon.elevation_travel.maximum_ascent=0.8
		weapon.elevation_travel.maximum_descent=0.9
		weapon.elevation_travel.apex_height=1.05
		weapon.elevation_travel.gravity=22.0
		weapon.motion=weapon.motion.duplicate()
		weapon.motion.approach_speed=11.0
		weapon.motion.return_speed=9.0
		if ResourceSaver.save(weapon,"res://.godot/elevation_saved.tres")!=OK:
			quit(1)
			return
	var valid:=is_equal_approx(weapon.hit_height_up,1.7) and is_equal_approx(weapon.hit_height_down,1.6) and is_equal_approx(weapon.elevation_travel.maximum_ascent,0.8) and is_equal_approx(weapon.elevation_travel.maximum_descent,0.9) and is_equal_approx(weapon.elevation_travel.apex_height,1.05) and is_equal_approx(weapon.elevation_travel.gravity,22.0) and is_equal_approx(weapon.motion.approach_speed,11.0) and is_equal_approx(weapon.motion.return_speed,9.0)
	var sword: Resource=load("res://resources/weapons/one_handed_sword.tres")
	valid=valid and is_equal_approx(sword.hit_height_up,1.8) and is_equal_approx(sword.elevation_travel.maximum_ascent,1.0)
	print("ELEVATION SETTINGS ","RELOAD " if reload else "SAVE ","PASS" if valid else "FAIL")
	quit(0 if valid else 1)
