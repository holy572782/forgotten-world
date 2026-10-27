extends "res://tests/enemy_sword_combat.gd"
const Warning = preload("res://scripts/enemies/enemy_attack_warning.gd")
var cue_count := 0

class MotionTrace extends Node:
	var actor: CharacterBody3D
	var last_state := -1
	var events: Array[Dictionary] = []
	var recovery_moves: Array[float] = []
	var last_position: Vector3
	func _ready() -> void:
		process_physics_priority = 100
		last_position = actor.global_position
	func _physics_process(_delta: float) -> void:
		if actor.state != last_state:
			events.append({"state":actor.state,"position":actor.global_position,"anchor":actor.attack_anchor,"count":actor.attack_count,"frame":Engine.get_physics_frames()})
			last_state = actor.state
		elif actor.state == actor.State.RECOVERY: recovery_moves.append(last_position.distance_to(actor.global_position))
		last_position = actor.global_position

func _fresh_sword(distance: float) -> void:
	await super._fresh_sword(distance)
	ai.settings.combat_movement_enabled = false
	ai.settings.preferred_attack_distance = 5.0

func _seconds(seconds: float) -> void:
	var start := Engine.get_physics_frames()
	while float(Engine.get_physics_frames()-start)/Engine.physics_ticks_per_second < seconds: await _ticks(1)

func _cue() -> void:
	cue_count += 1

func _recovery_fixture() -> void:
	await _fresh_sword(4.5)
	player.reset_motion(origin - Vector3(3,0,0))
	main.get_node("CameraRig").snap_to_target()
	ai.attack_count = 1 # Boundary fixtures start after a completed cycle.
	ai._set_state(ai.State.RECOVERY)
	ai.set_physics_process(true)
	await _ticks(3)

func _reload_followup() -> void:
	var settings: Resource = load("res://.godot/enemy_followup_saved.tres")
	_check(is_equal_approx(settings.pursuit_speed,3.2) and is_equal_approx(settings.preferred_attack_distance,3.5) and is_equal_approx(settings.pursuit_step_distance,0.6), "Pursuit tuning persists")
	_check(is_equal_approx(settings.attack_warning_flash_interval,0.1) and is_equal_approx(settings.attack_warning_pitch_scale,0.8) and settings.attack_warning_sound.resource_path.ends_with("mz_fire1.ogg"), "Warning speed/stream/pitch persist")
	_check(settings.visual.idle_frames.get_frame_count(&"idle_down") == 1 and is_equal_approx(settings.visual.idle_fps,6), "Idle frames/speed persist")
	for failure in failures: push_error(failure)
	print("ENEMY FOLLOWUP RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_followup()
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position = Vector3(12,0,10)
	await _ticks(5)
	_check(FileAccess.get_sha256("res://assets/audio/sfx/mz_fire1.ogg") == FileAccess.get_sha256("res://RPGツクールMZのaudio/se/Fire1.ogg"), "Fire1 is the exact SE source, not BGS")
	for ranged in [false,true]:
		if ranged: await _fresh(1,Vector3(2,0,0))
		else: await _fresh_sword(2.0)
		ai.settings = ai.settings.duplicate()
		var body_sprite: AnimatedSprite3D = ai.get_node("AnimatedSprite3D")
		var visual: Resource = body_sprite.visual.duplicate()
		body_sprite.visual = visual
		for side in ["down","left","right","up"]:
			var frames: SpriteFrames = visual.idle_frames
			_check(frames.get_frame_count(StringName("idle_"+side)) == 1, "Normal stand has one historical walk pose per direction")
		for frames in [visual.walk_frames,visual.attack_frames,visual.warning_frames,visual.idle_frames]:
			for animation in frames.get_animation_names():
				_check(FileAccess.file_exists(frames.get_frame_texture(animation,0).atlas.resource_path) and frames.get_frame_texture(animation,0).atlas.resource_path.begins_with("res://画像フォルダ/敵/"), "All active sheets read existing Japanese filenames")
		ai._set_state(ai.State.IDLE)
		_check(visual.idle_frames.get_frame_texture(&"idle_down",0).atlas == visual.walk_frames.get_frame_texture(&"walk_down",0).atlas, "Normal stand uses walk sheet, not warning sheet")
		var seen: Dictionary = {}
		for tick in range(65):
			await _ticks(1)
			seen[body_sprite.frame] = true
		_check(seen.size() == 1 and seen.has(0) and String(body_sprite.animation).begins_with("idle_") and not body_sprite.is_playing(), "Normal stand stays on walk column zero")
		visual.idle_fps = 8.0
		await _ticks(2)
		_check(is_equal_approx(body_sprite.speed_scale*body_sprite.sprite_frames.get_animation_speed(body_sprite.animation),8.0), "Inspector controls idle fps")
		for yaw in [0.0,90.0,180.0,270.0]:
			main.get_node("CameraRig").rotation.y = deg_to_rad(yaw)
			main.get_node("CameraRig").snap_to_target()
			ai.facing = Vector3.BACK.rotated(Vector3.UP,deg_to_rad(yaw))
			await _ticks(2)
			_check(body_sprite.animation == &"idle_down", "Idle direction agrees with camera rotation")
		ai._set_state(ai.State.DASH_APPROACH)
		ai.dash_destination = ai.global_position + ai.facing
		await _ticks(2)
		_check(String(body_sprite.animation).begins_with("walk_") and body_sprite.is_playing(), "Dash uses playing walk animation")
		ai._set_state(ai.State.ATTACK)
		ai.elapsed = 0.1
		await _ticks(2)
		_check(String(body_sprite.animation).begins_with("attack_"), "Attack still uses attack sheet")
		ai._set_state(ai.State.RECOVERY)
		ai.velocity = Vector3.RIGHT
		await _ticks(2)
		_check(String(body_sprite.animation).begins_with("walk_"), "Post-attack walking uses walk sheet")
		ai.velocity = Vector3.ZERO
		await _ticks(2)
		_check(String(body_sprite.animation).begins_with("idle_"), "Stopped recovery returns to normal stand")
		ai._set_state(ai.State.CHASE)
		ai.cooldown = 1.0
		ai.velocity = Vector3.RIGHT
		var stationary: Vector3 = ai.global_position
		ai.set_physics_process(true)
		await _ticks(2)
		ai.set_physics_process(false)
		_check(ai.global_position == stationary and String(body_sprite.animation).begins_with("idle_"), "Stationary cooldown chase displays Idle for both enemy types")
		var warning: Node = ai.get_node("AttackWarning")
		cue_count = 0
		warning.warning_sound_presented.connect(_cue)
		ai._start_windup()
		_check(cue_count == 1 and warning.warning_audio.playing and is_equal_approx(warning.warning_audio.pitch_scale,1.0) and not warning.warning_audio.stream.loop, "Real windup entry plays Fire1 once at pitch 1.0, without looping")
		_check(body_sprite.sprite_frames == visual.warning_frames and String(body_sprite.animation).begins_with("warning_"), "WINDUP entry immediately switches to warning pose")
		for yaw in [0.0,90.0,180.0,270.0]:
			main.get_node("CameraRig").rotation.y = deg_to_rad(yaw)
			main.get_node("CameraRig").snap_to_target()
			ai.facing = Vector3.BACK.rotated(Vector3.UP,deg_to_rad(yaw))
			await _ticks(2) # Let the existing camera rig update its actual Camera3D.
			for time in [0.0,0.1,0.2,0.3,0.4,0.8]:
				ai.elapsed = time
				body_sprite._process(0.0)
				warning._process(0.0)
				_check(body_sprite.animation == &"warning_down" and body_sprite.frame == 0 and not body_sprite.is_playing() and body_sprite.sprite_frames == visual.warning_frames, "Red/normal pulses hold the same warning texture at each camera yaw")
				_check(body_sprite.sprite_frames.get_frame_texture(body_sprite.animation,0).atlas.resource_path.contains("攻撃態勢"), "Warning reads existing Japanese filename directly")
		for state in [ai.State.ATTACK,ai.State.DASH_APPROACH,ai.State.DASH_RETURN,ai.State.RECOVERY,ai.State.IDLE,ai.State.DEAD]:
			ai._set_state(state)
			body_sprite._process(0.0)
			_check(body_sprite.sprite_frames != visual.warning_frames, "Warning texture never remains after windup")
		ai._set_state(ai.State.WINDUP)
		_check(cue_count == 2, "Second real WINDUP entry emits exactly one more sound")
		ai._set_state(ai.State.WINDUP)
		await _seconds(0.45)
		_check(cue_count == 2, "Holding windup / colour cycles never retrigger sound")
		ai._set_state(ai.State.IDLE)
		ai.settings.attack_warning_flash_enabled = false
		ai.settings.attack_warning_pitch_scale = 0.8
		ai.settings.attack_warning_volume_db = -20.0
		ai._start_windup()
		_check(cue_count == 3 and is_equal_approx(warning.warning_audio.pitch_scale,0.8) and warning.warning_audio.volume_db == -20.0, "Sound tuning is independent of flash on/off")
		ai._set_state(ai.State.IDLE)
		ai.settings.attack_warning_sound_enabled = false
		ai._start_windup()
		await _ticks(2)
		_check(cue_count == 3 and not warning.warning_audio.playing, "Sound switch disables cue and stops playback")
	for index in range(10):
		var times := [0.0,0.08,0.095,0.17,0.185,0.26,0.275,0.35,0.365,0.8]
		_check(Warning.pulse_on(times[index],0.9,2,0.09) == (index in [2,3,6,7]), "Fast normal/red sequence at 0.09-second intervals")
	_check(Warning.pulse_on(0.135,0.9,2,0.09) and not Warning.pulse_on(0.135,0.9,2,0.18), "Flash speed changes without changing windup duration")
	# A different-size atlas is legal; visual scale is never normalized to 48px.
	await _fresh_sword(2.0)
	var large_idle := SpriteFrames.new()
	large_idle.remove_animation(&"default")
	for side in ["down","left","right","up"]:
		var name := StringName("idle_"+side)
		large_idle.add_animation(name)
		large_idle.set_animation_speed(name,1.0)
		for index in range(3): large_idle.add_frame(name, SharedSword.attack_visual.attack_frames.get_frame_texture(StringName("attack_"+side),index))
	var large_sprite: AnimatedSprite3D = ai.get_node("AnimatedSprite3D")
	large_sprite.visual = large_sprite.visual.duplicate()
	large_sprite.visual.idle_frames = large_idle
	await _ticks(2)
	_check(large_sprite.sprite_frames.get_frame_texture(large_sprite.animation,0).get_size() == Vector2(112,112) and is_equal_approx(large_sprite.pixel_size,large_sprite.visual.pixel_size), "Different cell dimensions preserve their configured pixel scale")

	# Two real attacks: A -> return A -> walk B -> attack B -> return B.
	await _fresh_sword(4.5)
	main.get_node("CameraRig").rotation.y = 0.0
	main.get_node("CameraRig").snap_to_target()
	var trace := MotionTrace.new()
	trace.actor = ai
	main.add_child(trace)
	await _windup()
	var anchor_a: Vector3 = ai.attack_anchor
	await _state(ai.State.DASH_APPROACH)
	await _ticks(2)
	_check(String(ai.get_node("AnimatedSprite3D").animation).begins_with("walk_"), "Real physical approach plays Walk")
	await _state(ai.State.DASH_RETURN)
	player.reset_motion(origin - Vector3(3,0,0))
	await _state(ai.State.RECOVERY)
	var returned_a: Dictionary = trace.events.filter(func(item: Dictionary) -> bool: return item.state == ai.State.RECOVERY)[0]
	_check(returned_a.position.distance_to(anchor_a) < 0.001 and returned_a.anchor == anchor_a, "Return completes at A before pursuit starts")
	for tick in range(160):
		if ai.global_position.distance_to(player.global_position) <= 5.01: break
		await _ticks(1)
	await _ticks(3) # Allow the arrival tick's velocity to settle to zero.
	_check(ai.state == ai.State.RECOVERY and ai.attack_count == 1 and ai.global_position.distance_to(anchor_a) > 2.0, "Cooldown includes actual walking toward retreating player")
	_check(absf(ai.global_position.distance_to(player.global_position)-5.0) < 0.02 and ai.velocity.length() < 0.01, "Pursuit stops at valid preferred attack distance")
	var anchor_b: Vector3 = ai.global_position
	await _state(ai.State.WINDUP)
	_check(ai.attack_anchor.distance_to(anchor_b) < 0.001 and ai.home == anchor_a, "Next attack uses B, independent of original home A")
	var next_warning: Dictionary = trace.events.filter(func(item: Dictionary) -> bool: return item.state == ai.State.WINDUP)[-1]
	var interval := float(next_warning.frame-returned_a.frame)/Engine.physics_ticks_per_second
	_check(interval >= 3.0 and interval <= 3.06, "Walking never shortens the existing three-second recovery")
	await _state(ai.State.DASH_RETURN)
	await _state(ai.State.RECOVERY)
	var returned_b: Dictionary = trace.events.filter(func(item: Dictionary) -> bool: return item.state == ai.State.RECOVERY)[-1]
	_check(returned_b.position.distance_to(anchor_b) < 0.001 and ai.attack_count == 2, "Second real strike returns to B rather than A")
	_check(trace.recovery_moves.all(func(distance: float) -> bool: return distance <= 2.0/60.0+0.0001), "Pursuit displacement is bounded by normal walk speed per physics tick")
	var stopped: Vector3 = ai.global_position
	for offset in [0.04,-0.04,0.03,-0.03]:
		player.reset_motion(origin-Vector3(3+offset,0,0))
		await _seconds(0.1)
	_check(ai.global_position == stopped, "Small boundary jitter does not repeatedly restart pursuit")
	trace.free()

	# Boundary/safety fixtures use the same physics movement path as real recovery.
	for speed in [1.0,3.0]:
		await _recovery_fixture()
		ai.settings.pursuit_speed = speed
		var before: Vector3 = ai.global_position
		var tick_start := Engine.get_physics_frames()
		await _seconds(0.25)
		var seconds := float(Engine.get_physics_frames()-tick_start)/Engine.physics_ticks_per_second
		_check(absf(before.distance_to(ai.global_position)/seconds-speed) < 0.04, "Pursuit Speed sets constant walk velocity")
	await _recovery_fixture()
	ai.settings.pursuit_speed = 10.0
	ai.settings.pursuit_step_distance = 0.1
	ai._stop_pursuit()
	var fast_start: Vector3 = ai.global_position
	var fast_tick := Engine.get_physics_frames()
	await _seconds(0.1)
	var fast_seconds := float(Engine.get_physics_frames()-fast_tick)/Engine.physics_ticks_per_second
	_check(absf(fast_start.distance_to(ai.global_position)/fast_seconds-10.0) < 0.05, "Tiny step distance never artificially slows a faster walk")
	await _recovery_fixture()
	ai.settings.pursuit_enabled = false
	var held: Vector3 = ai.global_position
	await _seconds(0.5)
	_check(ai.global_position == held, "Pursuit disabled preserves standing recovery")
	for step_distance in [0.25,2.0]:
		await _recovery_fixture()
		ai.set_physics_process(false)
		ai.settings.pursuit_step_distance = step_distance
		ai._stop_pursuit()
		held = ai.global_position
		ai._pursuit_step(1.0/60.0)
		_check(absf(held.distance_to(ai._pursuit_destination)-step_distance) < 0.001, "Step distance controls the next safe walking goal")
	await _recovery_fixture()
	player.reset_motion(ai.global_position-Vector3(4,0,0))
	ai._start_windup()
	held = ai.global_position
	player.reset_motion(held-Vector3(7,0,0))
	await _seconds(0.25)
	_check(ai.state == ai.State.WINDUP and ai.global_position == held, "Player retreat never adds pursuit movement during windup")
	await _recovery_fixture()
	ai.settings.preferred_attack_distance = 2.0
	player.reset_motion(ai.global_position-Vector3(4,0,0))
	main.get_node("CameraRig").snap_to_target()
	await _ticks(3)
	_check(combat.request_attack(ai.targetable), "Player can reserve a pursuing target")
	held = ai.global_position
	await _ticks(5)
	_check(ai.global_position == held and ai.locomotion_held(), "Player attack reservation safely pauses pursuit")
	combat.cancel()
	await _recovery_fixture()
	var wall := _block(ai.global_position+Vector3(-0.5,1,0),Vector3(0.15,2,2))
	await _ticks(3)
	held = ai.global_position
	await _seconds(0.5)
	_check(ai.global_position == held and ai.velocity == Vector3.ZERO, "Wall safely stops pursuit")
	wall.free()
	await _recovery_fixture()
	player.set_physics_process(false)
	ai.global_position = Vector3(0,0,13.1)
	ai.home = ai.global_position
	ai.settings.preferred_attack_distance = 1.1
	player.global_position = Vector3(0,0,15.5)
	held = ai.global_position
	await _seconds(0.5)
	_check(ai.global_position == held, "Full-footprint support rejects pursuit over a cliff")
	player.set_physics_process(true)
	await _recovery_fixture()
	player.reset_motion(ai.global_position + Vector3(-2,0,0))
	ai.settings.preferred_attack_distance = 0.5
	await _seconds(0.8)
	_check(ai.global_position.distance_to(player.global_position) >= 1.099 and ai.preferred_distance() >= ai.active_attack.stop_distance, "Preferred distance respects stop distance and collision clearance")
	await _recovery_fixture()
	ai.health.damage(100,player)
	held = ai.global_position
	await _seconds(0.3)
	_check(ai.global_position == held, "Defeated actor never pursues")
	await _fresh(1,Vector3(7,0,0))
	ai.settings = ai.settings.duplicate()
	ai.settings.pursuit_enabled = true
	ai.attack_count = 1
	ai._set_state(ai.State.RECOVERY)
	ai.set_physics_process(true)
	held = ai.global_position
	await _seconds(0.5)
	_check(ai.global_position == held and not ai._can_pursue(), "Ranged enemy ignores melee pursuit even if flag is set")
	await _fresh_sword(2.0)
	ai.settings.visual = ai.settings.visual.duplicate()
	ai.settings.visual.idle_fps = 6.0
	ai.settings.pursuit_speed = 3.2
	ai.settings.preferred_attack_distance = 3.5
	ai.settings.pursuit_step_distance = 0.6
	ai.settings.attack_warning_flash_interval = 0.1
	ai.settings.attack_warning_pitch_scale = 0.8
	_check(ResourceSaver.save(ai.settings,"res://.godot/enemy_followup_saved.tres") == OK, "All new tuning saves as Resource")
	main.queue_free()
	await _ticks(4)
	if failures.is_empty(): print("ENEMY FOLLOWUP PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
