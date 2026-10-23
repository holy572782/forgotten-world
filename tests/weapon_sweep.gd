extends "res://tests/m09_enemy_combat.gd"
## Actual animation/physics attacks with production weapon data, not hit callbacks.
var victims: Array[Node3D] = []
var hit_nodes: Array[Node] = []
var swing: AnimatedSprite3D
var rig: Node3D
var base_weapon: WeaponData

func _reset(reach: float = 1.4, angle: float = 100.0) -> void:
	_press("guard",false)
	combat.cancel()
	await _ticks(3)
	combat.equipped_weapon = base_weapon.duplicate()
	combat.equipped_weapon.melee_reach = reach
	combat.equipped_weapon.sweep_angle_degrees = angle
	combat.stock.set_recovery_allowed(true)
	combat.stock.advance(20)
	player.reset_motion(origin)
	health.heal(100)
	rig.rotation.y = 0.0
	rig.snap_to_target()
	var positions := [Vector3(0,0,-2),Vector3(0.9,0,-1.9),Vector3(-0.9,0,-1.9),Vector3(0,0,0.8),Vector3(1.35,0,-0.9),Vector3(0,0,-3.0),Vector3(-1,0.6,-1.9)]
	for i in range(victims.size()):
		victims[i].get_parent().position = origin + positions[i]
		victims[i].get_parent().show()
		victims[i].health.heal(100)
	hit_nodes.clear()
	hit_frames.clear()
	await _ticks(12)
	target = victims[0]

func _start() -> void:
	_check(combat.request_attack(target), "Start production target attack")
	await _phase(combat.State.Attack)

func _end() -> void:
	await _wait_idle()
	_check(player.global_position.distance_to(origin) < 0.03, "Original return anchor")
	_check(not swing.visible, "No lingering sword after return")

func _capture_swing(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/weapon_"+label+"_"+str(Engine.max_fps)+".png") == OK,"Capture "+label)

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = load("res://scenes/tests/weapon_sweep_trial.tscn").instantiate()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	swing = player.get_node("WeaponSwing")
	rig = main.get_node("CameraRig")
	base_weapon = combat.equipped_weapon
	for path in ["TrainingEnemy/Targetable","TrainingEnemySecond/Targetable","TrainingEnemyThird/Targetable"]:
		victims.append(main.get_node(path))
	for i in range(4):
		var extra: Node3D = load("res://scenes/enemies/training_enemy.tscn").instantiate()
		extra.name = "SweepExtra"+str(i)
		main.add_child(extra)
		victims.append(extra.get_node("Targetable"))
	combat.hit.connect(func(victim: Node): hit_nodes.append(victim); hit_frames.append(sprite.frame))
	await _ticks(15)
	var image := Image.new()
	var path := "res://assets/sprites/weapons/iron_sword_attack.png"
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_check(FileAccess.get_sha256(path) == FileAccess.get_sha256("res://画像フォルダ/武器/鉄の剣.png"), "Latest supplied iron sword sheet bytes")
	_check(image.get_size() == Vector2i(336,448) and image.get_data() == load(path).get_image().get_data(), "Iron sword pixels preserved through import")
	for profile in [Vector2(1.4,100),Vector2(1.2,100),Vector2(1.4,60),Vector2(2.2,100)]:
		await _reset(profile.x,profile.y)
		await _start()
		# Changing the equipped Resource mid-cycle must not mutate the snapshot.
		combat.equipped_weapon.melee_reach = 0.1
		await _end()
		var expected := 3 if profile == Vector2(1.4,100) else (4 if profile.x > 2 else 1)
		_check(hit_nodes.size() == expected and hit_nodes.count(victims[0]) == 1,"Weapon reach/angle determines victims: "+str(profile)+" actual="+str(hit_nodes.size()))
		_check(hit_nodes.count(victims[3]) == 0 and hit_nodes.count(victims[4]) == 0 and hit_nodes.count(victims[6]) == 0,"No back, side or height hit")
		_check(combat.stock.current == 2 and combat.combo_hits == 1,"One stock and one combo step per swing, independent of victims")
		for index in hit_frames: _check(index == combat._active_motion.hit_frame,"Existing central frame timing")
	# A selected victim can die without preventing other victims of the same swing.
	await _reset()
	victims[0].health.damage(35)
	await _start()
	await _end()
	_check(victims[0].health.current_hp == 0 and victims[1].health.current_hp == 30 and victims[2].health.current_hp == 30,"Primary death still permits all same-swing recipients")
	# Shared health parts cannot cause duplicate actor damage.
	await _reset()
	var part: Node3D = victims[1].duplicate()
	part.name = "SharedPart"
	victims[1].get_parent().add_child(part)
	part.position = Vector3(0.02,0,0)
	await _start()
	await _end()
	_check(victims[1].health.current_hp == 30 and hit_nodes.size() == 3,"Shared HP owner takes one hit")
	part.free()
	# Terrain introduced next to the main route blocks just the side victim.
	await _reset()
	var wall := _block(origin+Vector3(0.52,0.85,-1.46),Vector3(0.12,1.7,0.35))
	await _ticks(3)
	await _start()
	await _end()
	_check(victims[1].health.current_hp == 40 and victims[0].health.current_hp == 30 and victims[2].health.current_hp == 30,"No incidental hit through a wall")
	wall.free()
	# An incidental victim that leaves the sector before impact must miss.
	await _reset()
	await _start()
	victims[1].get_parent().position.x += 4
	await _end()
	_check(victims[1].health.current_hp == 40 and hit_nodes.size() == 2,"Current position at hit frame, no remembered victim")
	# Explicit single-target mode retains the old weapon behavior.
	await _reset()
	combat.equipped_weapon.hit_shape = WeaponData.HitShape.SINGLE_TARGET
	await _start()
	await _end()
	_check(hit_nodes == [victims[0]],"Single target weapon mode remains available")
	# A side victim killed by this swing cannot consume the queued next strike.
	await _reset()
	victims[1].health.damage(35)
	_check(combat.request_attack(target) and combat.request_followup(victims[1]),"Queue a different live enemy")
	await _end()
	_check(victims[1].health.current_hp == 0 and combat.combo_hits == 1 and combat.stock.current == 2 and not combat.queued,"Cleave-killed reservation cancels without extra cost")
	# Local range never extends the original cycle's global boundary.
	await _reset()
	combat.equipped_weapon.attack_range = 2.05
	await _start()
	await _end()
	_check(hit_nodes == [victims[0]],"Incidental victims outside the original anchor radius miss")
	# Guard can cancel before impact and must hide sword/hurt immediately.
	await _reset()
	await _start()
	_press("guard",true)
	await _ticks(2)
	health.damage(10)
	await _ticks(1)
	_check(combat.state == combat.State.Guard and not swing.visible and not player.get_node("DamageVisual").visible and sprite.visible,"Guard suppresses sword and hurt while HP still decreases")
	_check(hit_nodes.is_empty() and combat.stock.current == 2,"Interrupted strike keeps cost and causes no pending hit")
	await _capture_swing("guard")
	_press("guard",false)
	await _end()
	# Same world-space strike under four camera yaws; actual three-frame sword poses.
	for yaw in [0.0,90.0,180.0,270.0]:
		await _reset()
		for index in range(3,victims.size()): victims[index].get_parent().hide()
		rig.rotation.y = deg_to_rad(yaw)
		rig.snap_to_target()
		await _ticks(3)
		await _start()
		var captured_frames: Dictionary = {}
		for tick in range(45):
			await _ticks(1)
			if not sprite._attacking: break
			_check(swing.visible and swing.sprite_frames == base_weapon.attack_visual.attack_frames and not swing.no_depth_test,"Separate sword retains world depth and source frames")
			_check(swing.animation == sprite.animation and swing.frame == sprite.frame and swing.transform == sprite.transform and swing.offset == sprite.offset and swing.pixel_size == sprite.pixel_size,"Authored sword aligns with body centre and current frame")
			if not captured_frames.has(sprite.frame):
				captured_frames[sprite.frame] = true
				await _capture_swing("yaw_"+str(int(yaw))+"_frame_"+str(sprite.frame))
		_check(captured_frames.size() == 3,"Visible start/middle/end under yaw "+str(yaw))
		await _end()
		_check(hit_nodes.size() == 3,"Orbit does not change world-space fan")
	# Removing the optional image leaves mechanics intact and no stuck presentation.
	await _reset()
	combat.equipped_weapon.attack_visual = null
	await _start()
	await _ticks(1)
	_check(not swing.visible,"Missing sword texture is safe")
	await _end()
	_check(hit_nodes.size() == 3,"Texture missing does not change hit mechanics")
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("WEAPON SWEEP PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
