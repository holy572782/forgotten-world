extends "res://tests/enemy_defeat_audio.gd"
const Flight = preload("res://scripts/effects/enemy_flyoff.gd")
var sound_starts := 0
var sound_finishes := 0
var visual_finishes := 0
var curve_samples: Array[Vector2] = []

func _sound_start(_voice: AudioStreamPlayer) -> void: sound_starts += 1
func _sound_finish() -> void: sound_finishes += 1
func _visual_finish(_reason: String) -> void: visual_finishes += 1

func _reload_bounce() -> void:
	var saved: Resource = load("res://.godot/enemy_bounce_saved.tres")
	_check(saved.bounce_count == 1 and is_equal_approx(saved.lift_height,1.1) and is_equal_approx(saved.secondary_bounce_scale,0.3) and is_equal_approx(saved.bounce_decay,0.6), "Bounce controls persist")
	_check(saved.defeat_sound.resource_path.ends_with("mz_cry1.ogg") and is_equal_approx(saved.defeat_volume_db,-16.0) and is_equal_approx(saved.defeat_pitch_scale,0.7), "Cry1 stream, independent volume and pitch persist")
	for failure in failures: push_error(failure)
	print("BOUNCE CRY RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_bounce()
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
	_check(FileAccess.get_sha256("res://assets/audio/sfx/mz_cry1.ogg") == FileAccess.get_sha256("res://RPGツクールMZのaudio/se/Cry1.ogg"), "Cry1 is an unchanged copy of the actual SE")
	for count in [0,1,2,4]:
		var peaks: Array[float] = []
		var last := 0.0
		var rising := false
		for index in range(601):
			var phase := index/600.0
			var height := Flight.bounce_height_at(phase,0.9,count,0.45,0.55)
			_check(height >= -0.000001 and height <= 0.900001, "Bounce height remains bounded and never sinks below launch line")
			if height > last: rising = true
			elif rising:
				peaks.append(last)
				rising = false
			if count == 2: curve_samples.append(Vector2(phase,height))
			last = height
		_check(peaks.size() == count+1 and is_zero_approx(last), "Configured extra bounce count yields the initial hop plus smaller hops")
		for index in range(1,peaks.size()): _check(peaks[index] < peaks[index-1], "Successive bounce amplitudes shrink")
	_check(is_equal_approx(Flight.bounce_height_at(0.225,0.9,2,0.45,0.55),0.9) and is_equal_approx(Flight.bounce_height_at(0.5875,0.9,2,0.45,0.55),0.405), "Initial and later heights follow independent ratio")
	for ranged in [false,true]:
		for yaw in [0.0,90.0,180.0,270.0]:
			_clean_effects()
			if ranged: await _fresh(1,Vector3(2,0,0))
			else: await _fresh_sword(2.0)
			var rig: Node3D = main.get_node("CameraRig")
			rig.rotation.y = deg_to_rad(yaw)
			rig.snap_to_target()
			await _ticks(2)
			var presenter: Node = ai.get_node("DefeatPresentation")
			sound_starts = 0
			presenter.defeat_sound_presented.connect(_sound_start)
			ai.health.damage(1,player)
			_check(sound_starts == 0, "Nonlethal damage never plays Cry1")
			ai.health.damage(100,player)
			var voice: AudioStreamPlayer = presenter.defeat_audio
			var flight: Node = presenter.effect
			var voice_id := voice.get_instance_id()
			_check(sound_starts == 1 and voice.playing and voice.get_parent() == main and voice.pitch_scale == 0.5 and voice.volume_db == -12.0 and not voice.stream.loop, "Both enemies start Cry1 exactly once at HP0, pitch 50 percent")
			_check(ai.state == ai.State.DEAD and ai.collision_layer == 0 and not ai.targetable.alive(), "Bouncing corpse has no combat eligibility")
			var expected_finishes := sound_finishes+1
			voice.finished.connect(_sound_finish)
			ai._die(player)
			presenter.start(player)
			_check(sound_starts == 1 and presenter.defeat_audio.get_instance_id() == voice_id, "Repeated death calls do not retrigger or replace the voice")
			finish_data.clear()
			flight.finished.connect(_finished.bind(flight))
			var camera := root.get_camera_3d()
			var at: Vector2 = camera.unproject_position(flight.origin)
			var direction: Vector2 = (camera.unproject_position(flight.origin+flight.hit_direction)-at).normalized()
			var previous_forward := -1.0
			for tick in range(120):
				if not is_instance_valid(flight): break
				var lift: float = Flight.bounce_height_at(flight.elapsed/flight.settings.flyoff_duration,flight.settings.lift_height,flight.settings.bounce_count,flight.settings.secondary_bounce_scale,flight.settings.bounce_decay)
				var pixels_up: float = (camera.unproject_position(flight.origin+camera.global_basis.y)-at).length()
				var perpendicular := Vector2(-direction.y,direction.x)
				if absf(perpendicular.dot(Vector2.UP)) > 0.25:
					var observed_lift: float = (flight.sprite.position-at).dot(perpendicular)/perpendicular.dot(Vector2.UP)
					_check(absf(observed_lift-lift*pixels_up) < 0.05, "Rendered sprite follows the configured bounce height, not just the forward line")
				var forward: float = (flight.sprite.position-at-Vector2.UP*lift*pixels_up).dot(direction)
				_check(forward >= previous_forward-0.001, "Forward flight never pauses or reverses while vertical hops are added")
				previous_forward = forward
				await _ticks(1)
			_check(not is_instance_valid(flight) and finish_data.get("reason") == "offscreen" and finish_data.get("offscreen") == true, "Both bouncing enemies exit actual viewport before visual cleanup")
			# Cry1 at 50 percent lasts longer than the flight and must finish independently.
			_check((is_instance_valid(voice) and voice.playing) or sound_finishes == expected_finishes, "Visual cleanup preserves playback or its natural finished event")
			for tick in range(600):
				if not is_instance_valid(voice): break
				await _ticks(1)
			_check(not is_instance_valid(voice) and sound_finishes == expected_finishes, "Voice reaches one natural finished event then frees itself")
	# Force deletion before the flight ends; audio is still owned by the world.
	await _fresh_sword(2.0)
	ai.health.damage(100,player)
	var independent_voice: AudioStreamPlayer = ai.get_node("DefeatPresentation").defeat_audio
	ai.get_node("DefeatPresentation").effect.free()
	await _ticks(3)
	_check(not is_instance_valid(ai) and is_instance_valid(independent_voice) and independent_voice.playing, "Forced visual deletion and owner release do not stop Cry1")
	independent_voice.free() # Explicit fixture teardown, not runtime cleanup.
	var saved: Resource = load("res://resources/enemies/flyoff_defeat.tres").duplicate()
	saved.bounce_count = 1
	saved.lift_height = 1.1
	saved.secondary_bounce_scale = 0.3
	saved.bounce_decay = 0.6
	saved.defeat_volume_db = -16.0
	saved.defeat_pitch_scale = 0.7
	_check(ResourceSaver.save(saved,"res://.godot/enemy_bounce_saved.tres") == OK, "Bounce and cry settings save as Resource")
	FileAccess.open("res://.godot/enemy_bounce_curve.json",FileAccess.WRITE).store_string(JSON.stringify(curve_samples))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("BOUNCE CRY ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
