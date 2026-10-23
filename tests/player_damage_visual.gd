extends "res://tests/m09_enemy_combat.gd"
## Supplied pixels plus live HP, animation, combat and guard integration.
var damage: AnimatedSprite3D

func _capture_damage(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/player_damage_" + label + "_" + str(Engine.max_fps) + ".png") == OK, "Capture " + label)

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	damage = player.get_node("DamageVisual")
	target = main.get_node("TrainingEnemy/Targetable")
	combat.hit.connect(func(_target: Node): hits += 1; hit_frames.append(sprite.frame))
	await _ticks(15)
	_check(not damage.visible and sprite.visible, "No hurt at startup")
	var path := "res://assets/sprites/player/player_damage.png"
	_check(FileAccess.get_sha256(path) == FileAccess.get_sha256("res://画像フォルダ/主人公/ダメージ.png"), "Byte-identical supplied file")
	var source := Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	var texture: Texture2D = load(path)
	_check(source.get_size() == Vector2i(144,192) and source.get_format() == Image.FORMAT_RGBA8, "144x192 RGBA source")
	_check(source.get_data() == texture.get_image().get_data() and not texture.get_image().has_mipmaps(), "Lossless unmipped pixels")
	for row in range(4):
		var name := StringName("damage_" + ["down","left","right","up"][row])
		_check(damage.sprite_frames.get_frame_count(name) == 3 and not damage.sprite_frames.get_animation_loop(name), "Three non-looping poses " + name)
		for col in range(3):
			var atlas: AtlasTexture = damage.sprite_frames.get_frame_texture(name,col)
			var rect := Rect2i(col*48,row*48,48,48)
			_check(atlas.region == Rect2(rect) and atlas.filter_clip and atlas.get_image().get_data() == source.get_region(rect).get_data(), "Exact 48px crop " + name + str(col))
	health.damage(0)
	health.heal(10)
	_check(not damage.visible, "No hurt from zero damage or healing")
	# Isolate the visual direction; production camera-relative calculation remains in use.
	player.set_physics_process(false)
	sprite.set_process(false)
	var rig: Node3D = main.get_node("CameraRig")
	for yaw in [0.0,90.0,180.0,270.0]:
		rig.rotation.y = deg_to_rad(yaw)
		rig.snap_to_target()
		await _ticks(2)
		for sector in range(4):
			player.facing_world = [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT][sector].rotated(Vector3.UP,deg_to_rad(yaw))
			sprite._process(0.0)
			health.damage(1)
			await _ticks(1)
			var expected := StringName("damage_" + ["down","right","up","left"][sector])
			_check(damage.visible and not sprite.visible and damage.animation == expected, "Live camera-relative hurt " + str(yaw) + "/" + str(sector))
			_check(damage.offset == sprite.offset and damage.pixel_size == sprite.pixel_size and damage.position == Vector3.ZERO, "Foot alignment unchanged")
			_check(damage.get_node("Shadow").animation == expected and damage.get_node("Shadow").frame == damage.frame, "Own shadow follows hurt")
			_check(not sprite.get_node("Shadow").is_visible_in_tree() and damage.get_node("Shadow").is_visible_in_tree(), "Only hurt shadow visible")
			_check(damage.material_override != sprite.material_override and damage.material_override.get_shader_parameter("sprite_sheet") == texture, "Own depth material uses supplied sheet")
			if yaw == 0.0: await _capture_damage("direction_" + str(sector))
			health.heal(100)
			_check(not damage.visible and sprite.visible, "Healing/reset clears hurt")
	# Let the animation run its three actual frames, then restore the action pose.
	health.damage(1)
	var elapsed := 0.0
	var seen: Dictionary = {}
	while damage.visible and elapsed < 0.6:
		seen[damage.frame] = true
		await process_frame
		elapsed += damage.get_process_delta_time()
	_check(seen.has(0) and seen.has(1) and seen.has(2), "All three authored poses play")
	_check(absf(elapsed-0.3) <= 0.06 and sprite.visible and not damage.visible, "Timed restoration after about 0.3 seconds: " + str(elapsed))
	health.damage(1)
	await _ticks(10)
	health.damage(1)
	_check(damage.visible and damage.frame == 0, "Repeated hit restarts pose")
	await _ticks(22)
	_check(not damage.visible and sprite.visible, "Repeated hit eventually restores sprite")
	# Missing resources during/at activation must retain the base presentation.
	var frames: SpriteFrames = damage.sprite_frames
	health.damage(1)
	damage.sprite_frames = null
	await _ticks(2)
	_check(not damage.visible and sprite.visible, "Missing frames during hurt restores base")
	health.damage(1)
	_check(not damage.visible and sprite.visible, "Missing frames at hit retains base")
	damage.sprite_frames = frames
	damage.animation = &"damage_down"
	sprite.set_process(true)
	player.set_physics_process(true)
	rig.rotation.y = 0.0
	health.heal(100)
	await _settle(Vector3.ZERO)
	var saved_origin := player.global_position
	_check(combat.request_attack(target), "Begin real target attack")
	await _phase(combat.State.Approach)
	health.damage(1)
	_check(damage.visible and combat.state == combat.State.Approach, "Hurt during approach does not interrupt motion")
	await _phase(combat.State.Attack)
	health.damage(1)
	_check(damage.visible and sprite.is_playing() and not sprite.visible, "Action animation continues beneath hurt")
	await _phase(combat.State.Return)
	health.damage(1)
	await _wait_idle()
	await _ticks(22)
	_check(hits == 1 and hit_frames == [combat._active_motion.hit_frame], "Exactly one real hit at existing animation frame")
	_check(player.global_position.distance_to(saved_origin) < 0.03 and sprite.visible and not damage.visible, "Existing return anchor and visibility restored")
	# Guard always holds the shield, including back hits without mitigation.
	_press("guard",true)
	await _ticks(3)
	_check(combat.state == combat.State.Guard, "Enter live guard")
	var attacker := Node3D.new()
	main.add_child(attacker)
	attacker.global_position = player.global_position + player.facing_world*1.2
	var before := health.current_hp
	health.damage(10,attacker)
	_check(is_equal_approx(before-health.current_hp,5) and combat.state == combat.State.Guard and not damage.visible and sprite.visible, "Guard reduces HP damage without hurt action")
	await _capture_damage("guard_hit")
	attacker.global_position = player.global_position - player.facing_world*1.2
	before = health.current_hp
	health.damage(10,attacker)
	_check(is_equal_approx(before-health.current_hp,10) and not damage.visible and sprite.visible, "Back hit still deals full damage but holds guard image")
	await _ticks(23)
	_check(sprite.visible and not damage.visible and String(sprite.animation).begins_with("guard_") and sprite.equipped_shield.display_name == "鉄の盾", "Equipped shield returns while guard remains held")
	await _capture_damage("guard_restored")
	_press("guard",false)
	await _ticks(3)
	health.damage(1)
	_check(damage.visible, "Hurt action resumes after guard release")
	_press("guard",true)
	await _ticks(2)
	_check(not damage.visible and sprite.visible and String(sprite.animation).begins_with("guard_"), "Entering guard clears an already playing hurt action")
	_press("guard",false)
	await _ticks(3)
	attacker.free()
	# Hurt uses the same depth/fade contract behind the existing M04 wall.
	player.reset_motion(Vector3(3,0,-7.5))
	player.set_physics_process(false)
	rig.rotation.y = PI
	rig.snap_to_target()
	await _ticks(25)
	health.damage(1)
	await _ticks(1)
	_check(not rig.safety_failed and rig.fader.entries.size() > 0 and damage.visible, "Hurt remains visible behind faded wall without camera safety failure")
	await _capture_damage("wall")
	player.set_physics_process(true)
	rig.rotation.y = 0.0
	health.damage(1000)
	_check(health.current_hp == 0 and damage.visible, "Lethal hit briefly shows hurt without new death mechanics")
	health.heal(100)
	_check(sprite.visible and not damage.visible, "HP reset cannot leave sprite hidden")
	# Real F5 melee AI, with no direct HP injection.
	await _fresh(0,Vector3(1.2,0,0))
	ai.settings.attack = load("res://resources/enemies/melee_attack.tres").duplicate(true)
	await _windup()
	before = health.current_hp
	for tick in range(100):
		await _ticks(1)
		if health.current_hp < before: break
	_check(health.current_hp == before-10 and damage.visible and not sprite.visible, "Real hostile attack triggers supplied hurt picture")
	await _capture_damage("enemy_hit")
	ai.set_physics_process(false)
	await _ticks(23)
	_check(sprite.visible and not damage.visible, "Enemy-hit picture ends normally")
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("PLAYER DAMAGE PASS: ",assertions," assertions; fps cap=",Engine.max_fps,"; display seconds=",elapsed)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
