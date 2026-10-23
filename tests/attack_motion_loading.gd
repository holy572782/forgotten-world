extends SceneTree
## Also run in an isolated project with only the new class absent from its cache.
## No global custom type here: consumers must resolve their own dependencies.
var failures: Array[String] = []
var assertions := 0

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--expect-unregistered" in OS.get_cmdline_user_args():
		var cache := ConfigFile.new()
		_check(cache.load("res://.godot/global_script_class_cache.cfg") == OK, "Isolated class cache loads")
		var found := false
		for item in cache.get_value("", "list", []):
			if item.get("class", "") == "AttackMotionSettings": found = true
		_check(not found, "New class is intentionally unregistered in this fixture")
	# Consumers first: explicitly loading the provider first could mask ordering bugs.
	for path in ["scripts/player/player_sprite.gd", "scripts/combat/weapon_data.gd", "scripts/player/target_dash.gd", "scripts/player/weapon_effect_data.gd", "scripts/player/weapon_swing_visual.gd", "scripts/player/weapon_effect_visual.gd"]:
		var script := load("res://"+path) as GDScript
		_check(script != null and script.can_instantiate(), "Consumer parses: "+path)
	var definition := load("res://scripts/combat/attack_motion_settings.gd") as GDScript
	_check(definition != null and definition.can_instantiate(), "Definition parses and extends Resource")
	if definition != null and definition.can_instantiate():
		var motion: Resource = definition.new()
		_check(motion is Resource and motion.get_script() == definition, "Explicit script construction")
		var snapshot: Resource = motion.snapshot()
		_check(snapshot != motion and snapshot.get_script() == definition, "Typed snapshot resolves its own class")
		_check(snapshot.frame_time_ratios == PackedFloat32Array([1,1,1]) and snapshot.hit_frame == 1, "Defaults unchanged")
		var saved := load("res://resources/weapons/default_attack_motion.tres") as Resource
		_check(saved != null and saved.get_script() == definition, "Motion Resource script path")
		var weapon := load("res://resources/weapons/one_handed_sword.tres") as Resource
		if weapon != null and weapon.get_script() != null and weapon.get_script().can_instantiate():
			_check(weapon.motion == saved and is_equal_approx(weapon.swing_duration(),0.32), "Weapon reference and timing unchanged")
		else: _check(false,"Weapon Resource loads")
	var scene := load("res://scenes/main.tscn") as PackedScene
	_check(scene != null and scene.can_instantiate(), "Main scene loads")
	if scene != null and scene.can_instantiate() and failures.is_empty():
		var instance := scene.instantiate()
		_check(instance.get_node("Player/AnimatedSprite3D").get_script() != null and instance.get_node("Player/TargetDash").get_script() != null, "Player and combat scripts stay attached")
		instance.free()
	if failures.is_empty(): print("ATTACK MOTION LOADING PASS: ",assertions," assertions")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
