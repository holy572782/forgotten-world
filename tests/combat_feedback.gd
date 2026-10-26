extends "res://tests/in_place_attack.gd"
const FeedbackSettings = preload("res://scripts/combat/combat_feedback_settings.gd")
var feedback: Node
var reaction: Node
var winds: Array[Dictionary] = []
var impacts: Array[Dictionary] = []

func _setup(distance := 1.2, duration := 0.48) -> void:
	await _prepare(distance,0.0,duration)
	combat.equipped_weapon.feedback = load("res://resources/combat_feedback.tres").snapshot()
	winds.clear()
	impacts.clear()
	await _ticks(12)

func _persist() -> void:
	var path := "res://.godot/combat_feedback_saved.tres"
	if "--reload" in OS.get_cmdline_user_args():
		var saved: Resource = load(path)
		_check(saved != null and saved.swing_volume_db == -18 and saved.flash_duration == 0.2,"Feedback settings persist across processes")
		_check(saved.hit_sound is AudioStream and saved.spark_scene is PackedScene,"Replacement streams and spark scene survive reload")
		return
	var saved: Resource = load("res://resources/combat_feedback.tres").snapshot()
	saved.swing_volume_db = -18
	saved.flash_duration = 0.2
	_check(ResourceSaver.save(saved,path) == OK,"Save Inspector feedback Resource")
	for key in ["swing_volume_db","hit_volume_db","flash_duration","flash_strength","flash_color","spark_duration","spark_count","spark_size_pixels","spark_spread"]:
		var exposed := false
		for property in saved.get_property_list():
			if property.name == key: exposed = (property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0
		_check(exposed,"Inspector/storage exposes "+key)
	var invalid := saved.duplicate()
	invalid.spark_count = 999
	invalid.flash_duration = NAN
	invalid.spark_spread = INF
	var safe: Resource = invalid.snapshot()
	_check(safe.spark_count == 12 and is_equal_approx(safe.flash_duration,0.1) and is_equal_approx(safe.spark_spread,0.18),"Invalid presentation values are bounded without changing source")

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/combat_feedback_"+label+".png")

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--reload" in OS.get_cmdline_user_args():
		await _persist()
	else:
		root.size = Vector2i(1152,720)
		main = preload("res://tests/fixtures/combat_scene.gd").create()
		root.add_child(main)
		player = main.get_node("Player")
		combat = player.combat
		sprite = player.get_node("AnimatedSprite3D")
		sword = player.get_node("WeaponSwing")
		health = player.get_node("HealthComponent")
		rig = main.get_node("CameraRig")
		target = main.get_node("TrainingEnemy/Targetable")
		feedback = player.get_node("CombatFeedback")
		reaction = main.get_node("TrainingEnemy/HitFeedback")
		initial_weapon = combat.equipped_weapon.duplicate()
		initial_weapon.motion = Motion.new()
		visual = initial_weapon.attack_visual
		combat.attack_accepted.connect(func(_id: int,_combo: int): accepted.append(Engine.get_physics_frames()))
		combat.hit.connect(func(victim: Node): hits += 1; victim_ids.append(victim.get_instance_id()))
		combat.state_changed.connect(func(next: int): events.append(next))
		feedback.swing_presented.connect(func(id: int):
			winds.append({"id":id,"phase":sprite.attack_phase(),"frame":sprite.frame,"tick":Engine.get_physics_frames()})
			_check(feedback.swing_audio.playing and feedback.swing_audio.stream != null,"Swing notification follows actual AudioStreamPlayer playback"))
		feedback.impact_presented.connect(func(receiver: Node):
			impacts.append({"receiver":receiver,"phase":sprite.attack_phase(),"hp":receiver.health.current_hp,"tick":Engine.get_physics_frames()})
			_check(feedback.hit_audio.playing and feedback.hit_audio.stream != null,"Impact notification follows actual AudioStreamPlayer playback"))
		await _ticks(15)
		var body_visual: GeometryInstance3D = main.get_node("TrainingEnemy/Body")
		var original: Material = body_visual.material_overlay
		var source_hash := FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres")
		for duration in [0.12,0.8]:
			await _setup(3.0,duration)
			combat.equipped_weapon.motion.frame_time_ratios = PackedFloat32Array([1,0.4,1])
			combat.equipped_weapon.motion.hit_frame = 2
			combat.equipped_weapon.motion.hit_frame_percent = 40
			combat.equipped_weapon.feedback.swing_frame_percent = 30
			await _begin()
			_check(combat.state == combat.State.Approach and winds.is_empty() and impacts.is_empty(),"Approach has no swing or impact feedback")
			for tick in range(180):
				await _ticks(1)
				if not impacts.is_empty(): break
			_check(winds.size() == 1 and impacts.size() == 1 and hits == 1,"One accepted swing and one actual HP loss produce one sound each")
			if not winds.is_empty() and not impacts.is_empty():
				_check(winds[0].phase >= (1.0+0.4*0.3)/2.4-0.001 and winds[0].tick <= impacts[0].tick,"Whoosh follows weighted swing frame before late damage")
				_check(impacts[0].hp == 30 and impacts[0].phase >= 0.75,"Impact starts after confirmed HP change at configured hit phase")
			_check(body_visual.material_overlay != original and reaction.remaining > 0,"Hit overlays the existing enemy visual")
			var bursts := get_nodes_in_group("combat_hit_sparks")
			_check(bursts.size() == 1 and bursts[0].particles.size() == 5,"One impact creates five pixel quads")
			if not bursts.is_empty():
				_check(bursts[0].top_level and bursts[0].global_position.distance_to(reaction.impact_position()) < 0.01,"Burst starts independently on camera-facing enemy surface")
				for particle in bursts[0].particles:
					_check(not particle.material_override.no_depth_test and not particle.material_override.emission_enabled,"Sparks retain world depth and have no glow")
			await _capture("hit_"+str(duration))
			await _done()
			await _ticks(15)
			_check(body_visual.material_overlay == original and get_nodes_in_group("combat_hit_sparks").is_empty(),"Flash restores exact original material and sparks are released")
		# Rejected/reduced-to-zero damage does not trigger receiver-side presentation.
		await _setup()
		target.health.damage_filter = func(_amount: float,_source: Node): return 0.0
		await _begin()
		await _done()
		_check(winds.size() == 1 and impacts.is_empty() and target.health.current_hp == 40,"Zero applied damage has no hit sound, flash or sparks")
		target.health.damage_filter = Callable()
		# A wall blocks before acceptance; a late blocker cancels before late damage.
		await _setup(3.0)
		var wall := _block(origin+Vector3(0,0.6,-1.5),Vector3(1.5,1.2,0.15))
		await _ticks(3)
		_check(not combat.request_attack(target) and winds.is_empty() and impacts.is_empty(),"Wall-rejected attack has no swing or impact presentation")
		wall.free()
		await _setup(1.2,0.8)
		combat.equipped_weapon.motion.hit_frame = 2
		combat.equipped_weapon.motion.hit_frame_percent = 80
		await _begin()
		for tick in range(100):
			if not winds.is_empty(): break
			await _ticks(1)
		wall = _block(origin+Vector3(0,0.6,-0.65),Vector3(1.5,1.2,0.1))
		await _done()
		_check(winds.size() == 1 and impacts.is_empty() and target.health.current_hp == 40,"Late blocked strike has a whoosh but no false impact")
		wall.free()
		await _setup(1.2,0.8)
		await _begin()
		_press("guard",true)
		await _ticks(2)
		_press("guard",false)
		await _done()
		_check(winds.is_empty() and impacts.is_empty(),"Guard cancellation before swing does not defer feedback")
		# Queue three real strikes; the same observer must reset once per paid cycle.
		await _setup()
		await _begin()
		await _done(true)
		_check(winds.size() == 3 and impacts.size() == 3 and hits == 3,"Three strikes each have one whoosh and one impact")
		# Death after the first hit leaves silent sequence slots, never fake sounds.
		await _setup()
		target.health.damage(30)
		await _begin()
		await _done()
		_check(winds.size() == 1 and impacts.size() == 1 and hits == 1,"Lethal hit presents once; dead-target waits are silent")
		_check(reaction.remaining == 0 and body_visual.material_overlay == original,"Lethal hit does not leave a flash on the corpse")
		# Shared HP selectable parts still have one receiver, never duplicate effects.
		await _setup()
		var other: Node3D = main.get_node("TrainingEnemySecond/Targetable")
		var other_health: HealthComponent = other.health
		other.health = target.health
		other.get_parent().position = origin+Vector3(0.15,0,-1.2)
		await _ticks(3)
		await _begin()
		await _done()
		_check(impacts.size() == 1 and target.health.current_hp == 30,"Shared-health parts present one confirmed impact")
		other.health = other_health
		# Existing overlay/shader is private-stacked and restored after rapid damage.
		await _setup()
		var existing := StandardMaterial3D.new()
		existing.albedo_color = Color(0.2,0.3,0.4,0.2)
		body_visual.material_overlay = existing
		target.health.damage(1,player)
		await _ticks(2)
		target.health.damage(1,player)
		_check(existing.next_pass == null and body_visual.material_overlay != existing,"Shared pre-existing material is not edited by flash stacking")
		await _ticks(15)
		_check(body_visual.material_overlay == existing,"Rapid hits restore the original overlay reference")
		body_visual.material_overlay = original
		# Camera yaws keep each impact near the body and restore cleanly.
		for yaw in [0.0,90.0,180.0,270.0]:
			await _setup()
			rig.rotation.y = deg_to_rad(yaw)
			rig.snap_to_target()
			await _ticks(2)
			target.health.damage(1,player)
			_check(reaction.impact_position().distance_to(body_visual.global_position) < 0.9,"Small impact stays near enemy under each camera yaw")
			await _capture("yaw_"+str(yaw))
			await _ticks(15)
		# AI death remains immediate; world-space particles finish independently.
		var ai := preload("res://scenes/enemies/practice_enemy.tscn").instantiate()
		ai.player = player
		ai.position = origin+Vector3(6,0,0)
		main.add_child(ai)
		ai.get_node("HealthComponent").damage(100,player)
		_check(ai.state == ai.State.DEAD and ai.get_node("HitFeedback").remaining > 0,"Lethal flash starts without postponing AI death")
		ai.queue_free()
		await _ticks(15)
		_check(get_nodes_in_group("combat_hit_sparks").is_empty(),"Freed/dead receivers leave no surviving particles")
		await _persist()
		_check(FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres") == source_hash,"Authored motion settings are untouched")
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("COMBAT FEEDBACK PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
