extends "res://tests/enemy_sword_combat.gd"
var swings := 0
var impacts := 0
var blocks := 0
var warnings := 0
var finish_data: Dictionary = {}
var measurements: Array[Dictionary] = []

func _swing() -> void: swings += 1
func _impact() -> void: impacts += 1
func _block_cue(_source: Node) -> void: blocks += 1
func _warning() -> void: warnings += 1
func _finished(reason: String, effect: Node) -> void:
	finish_data = {"reason":reason,"offscreen":effect.offscreen,"rect":effect.last_rect,"seconds":effect.elapsed}

func _clean_effects() -> void:
	for effect in get_nodes_in_group("enemy_defeat_visuals"): effect.free()

func _fresh_sword(distance: float) -> void:
	_clean_effects()
	await super._fresh_sword(distance)
	swings = 0
	impacts = 0
	blocks = 0
	warnings = 0
	ai.get_node("SwordAudio").swing_presented.connect(_swing)
	ai.get_node("SwordAudio").hit_presented.connect(_impact)
	ai.get_node("AttackWarning").warning_sound_presented.connect(_warning)

func _seconds(seconds: float) -> void:
	var start := Engine.get_physics_frames()
	while float(Engine.get_physics_frames()-start)/60.0 < seconds: await _ticks(1)

func _sequence(fly: bool, followup: bool) -> Dictionary:
	await _fresh_sword(3.4)
	combat.equipped_weapon.hit_shape = WeaponData.HitShape.SINGLE_TARGET
	ai.settings.defeat = ai.settings.defeat.duplicate()
	ai.settings.defeat.mode = 1 if fly else 0
	ai.health.damage(30)
	var first: CharacterBody3D = ai
	var second: CharacterBody3D
	if followup:
		second = EnemyScene.instantiate()
		second.player = player
		second.position = origin+Vector3(3.4,0,1.8)
		main.add_child(second)
		second.set_physics_process(false)
	var anchor: Vector3 = player.global_position
	_check(combat.request_attack(first.targetable), "Real player sequence starts against production soldier")
	await _phase(combat.State.Attack)
	if followup: _check(combat.request_followup(second.targetable), "Live second enemy can be reserved before first death")
	var death_tick := -1
	var end_tick := -1
	var freed_while_busy := false
	for tick in range(360):
		await _ticks(1)
		if death_tick < 0 and (not is_instance_valid(first) or first.health.current_hp == 0.0):
			death_tick = Engine.get_physics_frames()
			_check(combat.state != combat.State.Return and combat.is_busy(), "Lethal hit does not immediately force player return")
			if fly and is_instance_valid(first):
				_check(first.get_node("DefeatPresentation").effect.hit_direction.dot(combat.strike_facing) > 0.999, "Real lethal swing supplies its fixed attack direction")
		if fly and death_tick >= 0 and not is_instance_valid(first) and combat.is_busy(): freed_while_busy = true
		if followup and combat.is_busy() and combat.combo_hits < 3 and not combat.queued:
			combat.request_followup(second.targetable)
		if not combat.is_busy():
			end_tick = Engine.get_physics_frames()
			break
	_check(end_tick > death_tick and death_tick >= 0 and player.global_position.distance_to(anchor) < 0.03, "Sequence finishes and returns to its original player anchor")
	if followup:
		_check(combat.combo_hits == 3 and second.health.current_hp == 20.0 and combat.stock.current == 0, "After flying enemy dies, live target receives the remaining two real combo hits")
		combat.stock.set_recovery_allowed(true)
		combat.stock.advance(20.0)
		await _ticks(2)
		combat.cycle_target()
		_check(combat.valid_candidates().has(second.targetable) and combat.selected_target == second.targetable, "Live target remains selectable with L-equivalent switching after deletion")
		second.free()
	else:
		_check(combat.combo_hits == 1 and combat.stock.current == 2, "No live target means silent remaining slots, no extra swing or cost")
		if fly: _check(freed_while_busy, "Enemy can be freed while player's remaining sequence rhythm continues")
	return {"fly":fly,"followup":followup,"death_to_end":float(end_tick-death_tick)/60.0}

func _reload_defeat() -> void:
	var config: Resource = load("res://.godot/enemy_defeat_saved.tres")
	_check(is_equal_approx(config.minimum_fly_speed,22.0) and is_equal_approx(config.lift_height,0.9) and is_equal_approx(config.flyoff_duration,0.8) and is_equal_approx(config.maximum_lifetime,3.2) and config.scene != null, "Defeat profile persists including selected scene")
	for failure in failures: push_error(failure)
	print("ENEMY DEFEAT RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_defeat()
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	combat.guard_succeeded.connect(_block_cue)
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	await _fresh_sword(2.0)
	_check(ai.settings.attack.weapon.feedback == SharedSword.feedback and combat.equipped_weapon.feedback == SharedSword.feedback, "Player and soldier reference the same feedback resource")
	await _windup()
	await _finish_strike()
	var audio: Node = ai.get_node("SwordAudio")
	_check(swings == 1 and impacts == 1 and warnings == 1 and health.current_hp == 90, "One Evasion1 swing, one confirmed Slash1 hit, one Fire1 cue")
	_check(audio.swing_audio.stream.resource_path.ends_with("mz_evasion1.ogg") and audio.hit_audio.stream.resource_path.ends_with("mz_slash1.ogg"), "Correct shared SE files")
	_check(audio.swing_audio.volume_db == SharedSword.feedback.swing_volume_db and audio.swing_audio.pitch_scale == SharedSword.feedback.swing_pitch_scale and audio.hit_audio.volume_db == SharedSword.feedback.hit_volume_db and audio.hit_audio.pitch_scale == SharedSword.feedback.hit_pitch_scale, "Shared volume and pitch values match player")
	ai.set_physics_process(false)
	for tick in range(10): audio._physics_process(0.1)
	_check(swings == 1 and impacts == 1, "Observers cannot duplicate swing or impact")
	await _fresh_sword(2.0)
	var shared := SharedSword.feedback.duplicate()
	shared.swing_volume_db = -15.0
	shared.hit_volume_db = -19.0
	shared.swing_pitch_scale = 0.83
	shared.hit_pitch_scale = 1.23
	ai.settings.attack.weapon.feedback = shared
	combat.equipped_weapon.feedback = shared
	await _windup()
	await _finish_strike()
	audio = ai.get_node("SwordAudio")
	_check(is_equal_approx(audio.swing_audio.pitch_scale,0.83) and is_equal_approx(audio.hit_audio.pitch_scale,1.23) and audio.swing_audio.volume_db == -15.0 and audio.hit_audio.volume_db == -19.0, "One shared tuning change updates soldier playback")
	ai.set_physics_process(false)
	_check(combat.request_attack(ai.targetable), "Player still accepts attack with shared feedback tuning")
	await _phase(combat.State.Attack)
	_check(is_equal_approx(player.get_node("CombatFeedback").current_settings().swing_pitch_scale,0.83) and is_equal_approx(player.get_node("CombatFeedback").current_settings().hit_pitch_scale,1.23), "The same tuning change updates actual player swing snapshot")
	await _wait_idle()
	combat.equipped_weapon.feedback = SharedSword.feedback
	await _fresh_sword(2.0)
	player.facing_world = Vector3.RIGHT
	_press("guard",true)
	await _phase(combat.State.Guard)
	await _windup()
	await _finish_strike()
	_check(swings == 1 and impacts == 0 and blocks == 1 and health.current_hp == 95, "Successful guard uses one existing Sword2, no extra Slash1; damage remains unchanged")
	_press("guard",false)
	await _wait_idle()
	await _fresh_sword(4.5)
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	player.reset_motion(origin+Vector3(0,0,3.5))
	await _finish_strike()
	_check(swings == 1 and impacts == 0 and health.current_hp == 100, "Real miss has swing sound but no hit sound")
	await _fresh_sword(4.5)
	ai.settings.attack.weapon.attack_duration = 0.1
	ai.settings.attack.weapon.attack_speed_multiplier = 5.0
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	player.reset_motion(origin+Vector3(0,0,3.5))
	await _finish_strike()
	_check(swings == 1 and impacts == 0, "A 0.02-second missed swing still emits exactly one whoosh when rendering skips frames")
	_clean_effects()
	await _fresh(1,Vector3(5,0,0))
	audio = ai.get_node("SwordAudio")
	await _windup()
	await _state(ai.State.ATTACK)
	_check(audio.config == null and not audio.swing_audio.playing and not audio.hit_audio.playing and ai.shots.size() == 1, "Mage shot audio is unchanged")
	ai.set_physics_process(false)
	ai.clear_shots()
	# Actual Camera3D/viewport based exit, both enemy sheets, four yaws, plus rotation during flight.
	for ranged in [false,true]:
		for yaw in [0.0,90.0,180.0,270.0]:
			_clean_effects()
			root.size = Vector2i(800,600) if ranged else Vector2i(1152,720)
			if ranged: await _fresh(1,Vector3(2.0,0,0))
			else: await _fresh_sword(2.0)
			main.get_node("CameraRig").rotation.y = deg_to_rad(yaw)
			main.get_node("CameraRig").snap_to_target()
			await _ticks(2)
			var original: CharacterBody3D = ai
			var original_scale: float = ai.get_node("AnimatedSprite3D").pixel_size
			finish_data.clear()
			ai.health.damage(100,player)
			var effect: Node = ai.get_node("DefeatPresentation").effect
			_check(ai.state == ai.State.DEAD and ai.health.current_hp == 0 and not ai.targetable.alive() and ai.collision_layer == 0 and ai.collision_mask == 0 and not ai.is_visible_in_tree(), "HP0 immediately disables AI, target, contact and original presentation")
			_check(is_instance_valid(effect) and effect.get_parent() == main and effect.hit_direction.y == 0.0, "Detached visual owns no collision or enemy action")
			effect.finished.connect(_finished.bind(effect))
			var texture: AtlasTexture = effect.sprite.texture
			_check(texture.atlas.resource_path.contains("歩行.png") and effect.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and is_equal_approx(effect.world_pixel_size.x,original_scale), "Japanese enemy sheet and original per-pixel size survive")
			_check(effect.flash_remaining > 0.0 and effect.sprite.material.get_shader_parameter("flash_strength") > 0.0, "Lethal white flash is retained in detached visual")
			var count := get_nodes_in_group("enemy_defeat_visuals").size()
			ai.health.damage(100,player)
			ai._die(player)
			_check(get_nodes_in_group("enemy_defeat_visuals").size() == count, "Death presentation cannot trigger twice")
			for tick in range(100):
				if not is_instance_valid(effect): break
				if tick == 5:
					main.get_node("CameraRig").rotation.y += deg_to_rad(30.0)
					main.get_node("CameraRig").snap_to_target()
				_check(original.attack_count == 0 and original.velocity == Vector3.ZERO, "Flying dead actor never attacks or moves physically")
				await _ticks(1)
				if not ranged and yaw == 0.0 and tick == 12:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://.godot/enemy_defeat_midflight.png")
			_check(not is_instance_valid(effect) and finish_data.get("reason") == "offscreen" and finish_data.get("offscreen") == true, "Whole visual exits real viewport before deletion, even during camera rotation")
			_check(not root.get_visible_rect().grow(24.0).intersects(finish_data.get("rect",Rect2())), "Deletion requires the complete sprite bounds outside viewport")
			_check(not is_instance_valid(original), "Owner and temporary visual are both released")
			measurements.append({"ranged":ranged,"yaw":yaw,"seconds":finish_data.get("seconds"),"reason":finish_data.get("reason")})
	root.size = Vector2i(1152,720)
	# Detaching makes the flight survive deletion of the source enemy.
	await _fresh_sword(2.0)
	ai.health.damage(100,player)
	var independent: Node = ai.get_node("DefeatPresentation").effect
	ai.free()
	await _ticks(3)
	_check(is_instance_valid(independent) and independent.sprite.visible, "Visual survives explicit owner deletion")
	_clean_effects()
	# Missing camera cannot retain a visual forever.
	await _fresh_sword(2.0)
	ai.health.damage(100,player)
	var fallback: Node = ai.get_node("DefeatPresentation").effect
	fallback.settings.maximum_lifetime = 0.8
	fallback.settings.flyoff_duration = 0.2
	finish_data.clear()
	fallback.finished.connect(_finished.bind(fallback))
	var camera := root.get_camera_3d()
	camera.clear_current(false)
	await _seconds(1.0)
	_check(not is_instance_valid(fallback) and finish_data.get("reason") == "timeout", "Missing camera uses bounded safety cleanup")
	camera.make_current()
	# Defeat scene selection can be disabled without changing HP0 combat behavior.
	await _fresh_sword(2.0)
	ai.settings.defeat = ai.settings.defeat.duplicate()
	ai.settings.defeat.mode = 0
	ai.health.damage(100,player)
	_check(ai.state == ai.State.DEAD and ai.collision_layer == 0 and ai.get_node("DefeatPresentation").effect == null, "Per-enemy mode NONE disables visual without restoring target or collision")
	var reference := await _sequence(false,false)
	var flying := await _sequence(true,false)
	_check(absf(reference.death_to_end-flying.death_to_end) <= 0.05, "Visual on/off preserves actual post-lethal sequence and return timing")
	await _sequence(true,true)
	var saved: Resource = load("res://resources/enemies/flyoff_defeat.tres").duplicate()
	saved.minimum_fly_speed = 22.0
	saved.lift_height = 0.9
	saved.flyoff_duration = 0.8
	saved.maximum_lifetime = 3.2
	_check(ResourceSaver.save(saved,"res://.godot/enemy_defeat_saved.tres") == OK, "Defeat tuning saves as Resource")
	FileAccess.open("res://.godot/enemy_defeat_measurements.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("ENEMY DEFEAT AUDIO ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)

