extends "res://tests/m09_enemy_combat.gd"
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
const SharedSword = preload("res://resources/weapons/one_handed_sword.tres")
var observed: Dictionary = {}
var rendered: Dictionary = {}

func _planned_warning() -> void:
	# Aim capture and its budgeted landing proof are now separate events.
	if not ("_aim_plan_ready" in ai): return # Allows isolated pre-ADR-055 comparisons.
	var processing: bool = ai.is_physics_processing()
	ai.set_physics_process(true)
	for tick in range(180):
		if ai.state != ai.State.WINDUP or ai._aim_plan_ready:
			ai.set_physics_process(processing)
			return
		await _ticks(1)
	ai.set_physics_process(processing)
	_check(false,"Fixed-target plan finishes without unbounded warning work")

func _fresh_sword(distance: float) -> void:
	for action in ["guard", "attack", "move_left", "move_right", "move_up", "move_down"]: _press(action, false)
	combat.cancel()
	if is_instance_valid(ai): ai.free()
	health.heal(1000)
	player.reset_motion(origin)
	combat.stock.set_recovery_allowed(true)
	combat.stock.advance(20)
	main.get_node("CameraRig").snap_to_target()
	ai = EnemyScene.instantiate()
	ai.settings = load("res://resources/enemies/melee_practice.tres").duplicate(true)
	ai.settings.attack = ai.settings.attack.duplicate()
	ai.settings.attack.weapon = ai.settings.attack.weapon.duplicate()
	ai.settings.attack.weapon.motion = ai.settings.attack.weapon.motion.duplicate()
	ai.player = player
	ai.position = origin + Vector3(distance, 0, 0)
	main.add_child(ai)
	ai.set_physics_process(false)
	ai.facing=ai._horizontal_direction(player.global_position) # Perception boundaries are tested separately in enemy_ai_policy.
	observed.clear()
	rendered.clear()
	await _ticks(4)
	target = ai.targetable

func _finish_strike() -> void:
	for tick in range(240):
		observed[ai.state] = true
		await _ticks(1)
		await RenderingServer.frame_post_draw
		if ai.state == ai.State.ATTACK:
			var body_sprite: AnimatedSprite3D = ai.get_node("AnimatedSprite3D")
			var blade: AnimatedSprite3D = ai.get_node("WeaponSwing")
			var slash: AnimatedSprite3D = ai.get_node("SlashEffect")
			var phase: float = body_sprite.attack_phase()
			var expected := Motion.sample(Motion.weights(SharedSword.attack_visual.attack_frames, body_sprite.animation, ai.active_attack.weapon.motion.frame_time_ratios), phase)
			_check(body_sprite.frame == int(expected.x) and blade.frame == body_sprite.frame, "Same weighted body/blade phase as player")
			_check(blade.pixel_size == body_sprite.pixel_size and blade.offset == body_sprite.offset + SharedSword.attack_visual.direction_offset(String(body_sprite.animation).get_slice("_", 1)), "Same blade canvas/layout as player")
			var effect_expected := SharedSword.attack_visual.slash_effect.sample(body_sprite.animation, phase, ai.active_attack.weapon.motion.frame_time_ratios)
			_check(slash.visible == (effect_expected.x >= 0.0) and (not slash.visible or slash.frame == int(effect_expected.x)), "Player white slash sample/layout follows shared phase")
			_check(not ai.get_node("WeaponEffect").visible, "Player's disabled weapon effect stays disabled")
			rendered[body_sprite.frame] = true
			if "--capture" in OS.get_cmdline_user_args() and not rendered.has("capture"):
				rendered["capture"] = true
				root.get_texture().get_image().save_png("res://.godot/enemy_sword_attack.png")
		if ai.state == ai.State.RECOVERY: return
	_check(false, "Sword sequence timeout")

func _reload() -> void:
	var profile: Resource = load("res://.godot/enemy_sword_saved.tres")
	_check(is_equal_approx(profile.recovery_seconds, 4.2) and is_equal_approx(profile.weapon.melee_reach, 3.1), "Weapon/interval Resource settings survive new process")
	_check(profile.weapon.attack_visual.slash_effect.frames != null and is_equal_approx(profile.snapshot().attack_seconds, 0.32), "Shared visual/motion references survive reload")
	print("ENEMY SWORD RELOAD ", "PASS" if failures.is_empty() else "FAIL")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload()
		return
	root.size = Vector2i(1152, 720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12, 0, 10)
	await _ticks(5)
	var weapon_hash := FileAccess.get_sha256("res://resources/weapons/one_handed_sword.tres")
	var motion_hash := FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres")
	await _fresh_sword(2.0)
	_check(ai.settings.attack.weapon.resource_path == SharedSword.resource_path or ai.settings.attack.weapon.weapon_id == SharedSword.weapon_id, "Soldier configured with player's sword")
	_check(is_equal_approx(ai.engagement_range(), SharedSword.attack_range) and is_equal_approx(ai.active_attack.hit_radius, SharedSword.melee_reach), "Shared 5m engagement and 2.5m hit reach")
	_check(is_equal_approx(ai.active_attack.attack_seconds, SharedSword.swing_duration()) and ai.active_attack.weapon.motion.frame_time_ratios == SharedSword.motion.frame_time_ratios, "Shared duration/saved frame ratios")
	_check(is_equal_approx(ai.active_attack.hit_delay_seconds, SharedSword.swing_duration()*0.4/2.1), "Hit is aligned with the weighted second frame")
	await _windup()
	var anchor: Vector3 = ai.attack_anchor
	await _finish_strike()
	_check(not observed.has(ai.State.DASH_APPROACH) and not observed.has(ai.State.DASH_RETURN) and ai.global_position.distance_to(anchor) < 0.001, "Inside reach skips both travel paths")
	_check(ai.attack_count == 1 and health.current_hp == 90, "Exactly one swing and one real damage application")
	var recovery_start := Engine.get_physics_frames()
	while ai.state == ai.State.RECOVERY and Engine.get_physics_frames()-recovery_start < 220:
		_check(ai.attack_count == 1 and not ai.get_node("SlashEffect").visible and not ai.get_node("WeaponSwing").visible, "Three-second interval never repeats swing/effect/damage")
		await _ticks(1)
	var recovery_time := float(Engine.get_physics_frames()-recovery_start)/Engine.physics_ticks_per_second
	_check(recovery_time >= 2.96 and recovery_time <= 3.07, "Actual post-attack interval is three seconds")
	await _state(ai.State.WINDUP)
	_check(ai.attack_count == 1, "Still-in-range player receives a new warning after the interval")

	await _fresh_sword(4.5)
	await _windup()
	await _planned_warning()
	anchor = ai.attack_anchor
	_check(is_equal_approx(ai.global_position.distance_to(ai.dash_destination), 3.4), "Same 1.1m stopping position as player")
	_check(is_equal_approx(ai.active_attack.dash_seconds, 3.4/12.0), "Approach duration uses shared distance/speed limits")
	await _finish_strike()
	_check(observed.has(ai.State.DASH_APPROACH) and observed.has(ai.State.DASH_RETURN), "Outside hit reach uses approach then attack then return")
	_check(ai.attack_count == 1 and health.current_hp == 90 and ai.global_position.distance_to(anchor) < 0.001, "Far strike hits once and returns to its original anchor")
	_check(is_equal_approx(ai.active_attack.return_seconds, SharedSword.motion.return_maximum_travel_time), "Return uses same saved motion limits")
	await _fresh_sword(2.0)
	player.facing_world = Vector3.RIGHT
	_press("guard", true)
	await _phase(combat.State.Guard)
	await _windup()
	await _finish_strike()
	_check(ai.attack_count == 1 and health.current_hp == 95, "Existing front guard reduces the real shared sword hit once")
	_press("guard", false)
	await _wait_idle()

	for distance in [2.499, 2.5, 2.501]:
		await _fresh_sword(distance)
		ai._start_windup()
		await _planned_warning()
		_check(ai._in_place == (distance <= 2.5) and ai.melee_hits() == (distance <= 2.5), "Shared hit/reach predicate at boundary " + str(distance))
	await _fresh_sword(5.2)
	ai.set_physics_process(true)
	await _state(ai.State.WINDUP)
	_check(ai.attack_anchor.distance_to(player.global_position) <= SharedSword.attack_range + 0.001, "Walking enters the same 5m range before initiating dash")

	await _fresh_sword(2.0)
	ai.facing = Vector3.LEFT.rotated(Vector3.UP, deg_to_rad(50.0))
	_check(ai.melee_hits(), "Same 100-degree sector includes 50-degree boundary")
	ai.facing = Vector3.LEFT.rotated(Vector3.UP, deg_to_rad(50.1))
	_check(not ai.melee_hits(), "Shared sector rejects outside angle")
	ai.facing = Vector3.LEFT
	var wall := _block(origin+Vector3(1, 0.6, 0), Vector3(0.15, 1.2, 2))
	await _ticks(3)
	_check(ai.has_sight() and not ai.melee_hits(), "A hand-height wall blocks damage while the head remains visible")
	ai._start_windup()
	await _planned_warning()
	_check(ai.state == ai.State.WINDUP and ai._in_place and not ai.melee_hits(), "Visible in-place swing is allowed; the wall still blocks damage")
	ai.set_physics_process(true)
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count==1 and health.current_hp==100,"Occluded swing deals no damage and never dashes through the wall")
	wall.free()
	await _fresh_sword(2.0)
	player.set_physics_process(false)
	ai.global_position = Vector3(0, 0, 13.3)
	ai.home = ai.global_position
	player.global_position = Vector3(0, 0, 15)
	ai._start_windup()
	await _planned_warning()
	_check(ai.state == ai.State.WINDUP and ai._in_place and ai.global_position == ai.home,"In-place reach does not require a body floor corridor across a gap")
	_check(ai.melee_hits(),"An unobstructed blade can reach across a gap without moving the body")
	player.set_physics_process(true)
	await _fresh_sword(4.5)
	await _windup()
	await _state(ai.State.DASH_APPROACH)
	wall = _block(ai.global_position + ai.facing*0.5 + Vector3.UP, Vector3(0.15, 2, 2))
	await _state(ai.State.RECOVERY)
	_check(ai.attack_count == 0 and health.current_hp == 100, "New wall during approach safely cancels without damage")
	wall.free()

	await _fresh_sword(2.0)
	await _windup()
	await _state(ai.State.ATTACK)
	ai.health.damage(100, player)
	await _ticks(3)
	_check(ai.state == ai.State.DEAD and not ai.get_node("SlashEffect").visible and not ai.get_node("WeaponSwing").visible and health.current_hp == 100, "Death before hit cancels blade/effect/pending damage")
	await _fresh_sword(4.5)
	await _windup()
	var saved_reach: float = ai.active_attack.weapon.melee_reach
	ai.settings.attack.weapon.melee_reach = 3.1
	_check(ai.active_attack.weapon.melee_reach == saved_reach, "Active swing snapshots shared settings")
	ai.settings.attack.recovery_seconds = 4.2
	_check(ResourceSaver.save(ai.settings.attack, "res://.godot/enemy_sword_saved.tres") == OK, "Inspector settings can be saved as Resource")
	_check(FileAccess.get_sha256("res://resources/weapons/one_handed_sword.tres") == weapon_hash and FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres") == motion_hash, "Player-authored weapon and motion were not changed")
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("ENEMY SWORD PASS: ", assertions, " assertions; fps cap=", Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
