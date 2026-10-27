extends "res://tests/enemy_sprites.gd"
const Warning = preload("res://scripts/enemies/enemy_attack_warning.gd")

class PhysicsTrace extends Node:
	var enemy: CharacterBody3D
	var health: HealthComponent
	var frames: Array = []
	var done := false
	func _ready() -> void:
		process_physics_priority = 100
	func _physics_process(_delta: float) -> void:
		frames.append([enemy.state, enemy.elapsed, enemy.global_position, enemy.facing, enemy.attack_count, health.current_hp, enemy.shots.size()])
		if enemy.state == enemy.State.RECOVERY:
			done = true
			enemy.set_physics_process(false)
			set_physics_process(false)

func _spawn(ranged: bool) -> void:
	super._spawn(ranged)
	actor.settings = actor.settings.duplicate() # Never edit authored resources.

func _warning(phase: float) -> void:
	actor._set_state(actor.State.WINDUP)
	actor.elapsed = phase * actor.active_attack.windup_seconds
	sprite._process(0.0)
	actor.get_node("AttackWarning")._process(0.0)

func _strength() -> float:
	return sprite.material_override.get_shader_parameter("attack_warning_strength")

func _reload() -> void:
	var settings: Resource = load("res://.godot/enemy_warning_saved.tres")
	_check(not settings.attack_warning_flash_enabled and settings.attack_range_indicator_enabled, "Both visual switches persist")
	_check(settings.attack_warning_flash_count == 3 and is_equal_approx(settings.attack_warning_flash_strength, 0.4) and settings.attack_warning_flash_color == Color(0.8,0.1,0.2,1), "Colour/count/strength persist across process restart")
	for failure in failures: push_error(failure)
	print("WARNING RELOAD ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _trace_trial(main: Node3D, ranged: bool, warning: bool, indicator: bool) -> Array:
	var hero: CharacterBody3D = main.get_node("Player")
	hero.combat.cancel()
	hero.reset_motion(Vector3(-6,0,0))
	hero.set_physics_process(false)
	hero.get_node("HealthComponent").heal(1000)
	var enemy: CharacterBody3D = EnemyScene.instantiate()
	enemy.settings = load("res://resources/enemies/ranged_practice.tres" if ranged else "res://resources/enemies/melee_practice.tres").duplicate()
	enemy.settings.attack_warning_flash_enabled = warning
	enemy.settings.attack_range_indicator_enabled = indicator
	enemy.player = hero
	enemy.position = Vector3(-2,0,0)
	main.add_child(enemy)
	enemy.set_physics_process(false)
	for tick in range(4):
		await physics_frame
		await process_frame
	var trace := PhysicsTrace.new()
	trace.enemy = enemy
	trace.health = hero.get_node("HealthComponent")
	main.add_child(trace)
	enemy.set_physics_process(true)
	for tick in range(220):
		if trace.done: break
		await physics_frame
		await process_frame
	_check(trace.done and enemy.attack_count == 1, "Real AI completes one warned attack")
	var result := trace.frames.duplicate(true)
	trace.free()
	enemy.free()
	return result

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload()
		return
	root.size = Vector2i(800,600)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	world = Node3D.new()
	root.add_child(world)
	ground = _box(Vector3(30,0.2,30),Vector3(0,-0.1,0))
	wall = _box(Vector3(8,5,0.3),Vector3(0,1.8,3))
	wall.hide()
	wall.collision_layer = 0
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	camera.position = Vector3(0,7,10)
	camera.look_at(Vector3(0,0.8,0))
	player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(10,0,10)
	world.add_child(player)
	player.set_physics_process(false)
	player.hide()
	_check(player.get_node("AnimatedSprite3D").material_override.get_shader_parameter("attack_warning_strength") == 0.0, "Player tint remains disabled")
	for ranged in [false,true]:
		_spawn(ranged)
		var warning: Node = actor.get_node("AttackWarning")
		_check(actor.settings.attack_warning_flash_enabled and actor.settings.attack_warning_flash_count == 2 and not actor.settings.attack_range_indicator_enabled, "Both enemies default to two red pulses without range geometry")
		var original_pixel_size := sprite.pixel_size
		var original_transform := sprite.transform
		var collider_id: int = actor.get_node("CollisionShape3D").shape.get_instance_id()
		for yaw in [0.0,90.0,180.0,270.0]:
			camera.position = Vector3(0,7,10).rotated(Vector3.UP,deg_to_rad(yaw))
			camera.look_at(Vector3(0,0.8,0))
			actor.facing = Vector3.BACK
			_warning(0.15)
			actor.settings.attack_warning_flash_enabled = false
			var normal := await _image()
			sprite.hide()
			var silhouette := _difference(normal,await _image())
			sprite.show()
			actor.settings.attack_warning_flash_enabled = true
			var red := await _image()
			var red_pixels := _difference(normal,red)
			_check(not red_pixels.is_empty() and red_pixels.keys().all(func(pixel: int) -> bool: return silhouette.has(pixel)), "Red changes only opaque character pixels at each camera yaw")
			_check(sprite.pixel_size == original_pixel_size and sprite.transform == original_transform and actor.get_node("CollisionShape3D").shape.get_instance_id() == collider_id, "Tint preserves size/transform/collision")
			_warning(0.25)
			_check(_difference(normal,await _image()).is_empty(), "First pulse returns to exact original image")
			_warning(0.35)
			_check(not _difference(normal,await _image()).is_empty(), "Second red pulse is visible")
			_warning(0.55)
			_check(_difference(normal,await _image()).is_empty(), "Second pulse returns to exact original image")
			if "--capture" in OS.get_cmdline_user_args() and yaw == 0.0:
				normal.save_png("res://.godot/warning_normal_"+("mage" if ranged else "soldier")+".png")
				red.save_png("res://.godot/warning_red_"+("mage" if ranged else "soldier")+".png")
		camera.position = Vector3(0,7,10)
		camera.look_at(Vector3(0,0.8,0))
		actor.settings.attack_warning_flash_count = 3
		for index in range(6):
			_warning((float(index)+1.25)*actor.settings.attack_warning_flash_interval/actor.active_attack.windup_seconds)
			_check((_strength() > 0.0) == (index % 2 == 0), "Inspector count produces three distinct pulses")
		actor.settings.attack_warning_flash_count = 2
		_warning(0.15)
		var strong := await _image()
		actor.settings.attack_warning_flash_strength = 0.4
		var weak := await _image()
		_check(not _difference(strong,weak).is_empty() and is_equal_approx(_strength(),0.4), "Inspector strength visibly adjusts tint")
		actor.settings.attack_warning_flash_color = Color(0.2,0.8,0.3,1)
		_check(not _difference(weak,await _image()).is_empty(), "Inspector colour visibly adjusts tint")
		actor.settings.attack_warning_flash_color = Color(1.0,0.15,0.1,1)
		actor.settings.attack_warning_flash_strength = 0.75
		_warning(0.15)
		_check(not actor.telegraph.visible and not actor.dash_guide.visible, "Default hides sector and route during warning")
		var clean := await _image()
		actor.settings.attack_range_indicator_enabled = true
		var indicated := await _image()
		_check(actor.telegraph.visible and actor.telegraph.mesh.get_surface_count() > 0 and not _difference(clean,indicated).is_empty(), "Inspector switch restores actual range drawing")
		_check(actor.dash_guide.visible == not ranged, "Same switch restores melee route only")
		actor.settings.attack_range_indicator_enabled = false
		_check(_difference(clean,await _image()).is_empty(), "Turning range off restores exact clean image")
		for state in [actor.State.IDLE,actor.State.CHASE,actor.State.DASH_APPROACH,actor.State.ATTACK,actor.State.DASH_RETURN,actor.State.RECOVERY,actor.State.RETURN]:
			actor._set_state(state)
			warning._process(0.0)
			_check(_strength() == 0.0, "No warning tint outside WINDUP")
		_warning(0.15)
		wall.show()
		wall.collision_layer = 1
		await physics_frame
		var blocked := await _image()
		actor.settings.attack_warning_flash_enabled = false
		_check(_difference(blocked,await _image()).is_empty(), "Red never leaks through opaque wall")
		wall.hide()
		wall.collision_layer = 0
		actor.settings.attack_warning_flash_enabled = true
		_warning(0.15)
		actor.hide()
		warning._process(0.0)
		_check(_strength() == 0.0, "Hiding clears red")
		actor.show()
		_warning(0.15)
		actor.health.damage(100,player)
		_check(_strength() == 0.0 and actor.state == actor.State.DEAD, "Death clears tint immediately without changing death handling")
	for duration in [0.03,0.08,0.15]:
		_check(Warning.pulse_on(duration*0.1,duration,8) and Warning.pulse_on(duration*0.9,duration,8) and not Warning.pulse_on(duration,duration,8), "Very short windup uses one steady pulse and ends on time")
	_check(not Warning.pulse_on(0.0,0.0,2) and not Warning.pulse_on(NAN,1.0,2), "Invalid/instant duration does not leave tint")
	var settings: Resource = actor.settings.duplicate()
	settings.attack_warning_flash_enabled = false
	settings.attack_warning_flash_color = Color(0.8,0.1,0.2,1)
	settings.attack_warning_flash_count = 3
	settings.attack_warning_flash_strength = 0.4
	settings.attack_range_indicator_enabled = true
	_check(ResourceSaver.save(settings,"res://.godot/enemy_warning_saved.tres") == OK, "Presentation settings save without modifying source")
	world.free()
	# Real presenter/HP path: white dominates red and sparks still spawn.
	var main := preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	var hero: CharacterBody3D = main.get_node("Player")
	hero.reset_motion(Vector3(-6,0,0))
	hero.set_physics_process(false)
	hero.hide()
	main.get_node("HUD").visible = false
	main.get_node("PracticeSelector").visible = false
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	actor = EnemyScene.instantiate()
	actor.player = hero
	actor.settings = load("res://resources/enemies/melee_practice.tres").duplicate()
	actor.position = Vector3(-4,0,0)
	main.add_child(actor)
	actor.set_physics_process(false)
	sprite = actor.get_node("AnimatedSprite3D")
	actor.get_node("Targetable/HealthLabel").hide()
	actor.show_debug_state = false
	actor.debug_label.hide()
	_warning(0.15)
	main.get_node("CameraRig").snap_to_target()
	await _image()
	actor.health.damage(1,hero)
	var receiver: Node = actor.get_node("HitFeedback")
	receiver.set_process(false)
	_check(not get_nodes_in_group("combat_hit_sparks").is_empty() and actor.health.current_hp == 39, "Real damage during windup preserves sparks and exact HP loss")
	for burst in get_nodes_in_group("combat_hit_sparks"): burst.hide()
	actor.settings.attack_warning_flash_enabled = false
	var white_only := await _image()
	actor.settings.attack_warning_flash_enabled = true
	_check(_difference(white_only,await _image()).is_empty() and _strength() == 0.0, "White flash is pixel-identical with warning enabled or disabled")
	if "--capture" in OS.get_cmdline_user_args(): white_only.save_png("res://.godot/warning_white_priority.png")
	receiver.clear_flash()
	actor.get_node("AttackWarning")._process(0.0)
	_check(_strength() > 0.0 and sprite.material_overlay == null, "After white flash, resume current red phase without overwriting material")
	main.remove_child(actor)
	_check(_strength() == 0.0, "Detaching clears owned tint")
	actor.free()
	for ranged in [false,true]:
		var off := await _trace_trial(main,ranged,false,false)
		var on := await _trace_trial(main,ranged,true,true)
		_check(off == on, "Every physics tick/position/phase/damage/projectile count matches with visuals on/off")
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("ATTACK WARNING PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
