extends "res://tests/m04_camera.gd"
var hp_events: Array[Vector2] = []
var zero_sources: Array[Node] = []
var gauge_events: Array[Vector2] = []

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	player = main.get_node("Player")
	rig = main.get_node("CameraRig")
	camera = rig.camera
	await _ticks(20)
	var health: HealthComponent = player.get_node("HealthComponent")
	var gauge: AttackGaugeComponent = player.get_node("AttackGaugeComponent")
	var hud = main.get_node("HUD")
	var sprite = player.get_node("AnimatedSprite3D")
	health.hp_changed.connect(func(current: float, maximum: float): hp_events.append(Vector2(current, maximum)))
	health.depleted.connect(func(source: Node): zero_sources.append(source))
	gauge.gauge_changed.connect(func(current: float, maximum: float): gauge_events.append(Vector2(current, maximum)))
	_check(health.current_hp == 100.0 and health.max_hp == 100.0, "Initial HP 100")
	_check(hud.hp_bar.value == 100.0 and hud.hp_label.text == "HP  100 / 100", "Initial HUD HP")
	health.damage(30.0, player)
	_check(health.current_hp == 70.0 and hud.hp_bar.value == 70.0 and hud.hp_label.text == "HP  70 / 100", "Damage and HUD signal synchronization")
	health.heal(15.0)
	_check(health.current_hp == 85.0, "Heal")
	health.heal(1000.0)
	_check(health.current_hp == 100.0, "HP upper clamp")
	health.damage(-5.0)
	health.heal(-5.0)
	health.damage(NAN)
	health.heal(INF)
	_check(hp_events.size() == 3, "Reject negative/nonfinite amounts without notifications")
	health.damage(1000.0, player)
	health.damage(1.0, player)
	_check(health.current_hp == 0.0 and hud.hp_bar.value == 0.0, "HP lower clamp")
	_check(zero_sources == [player] and hp_events.size() == 4, "One zero notification per depletion with source")
	health.heal(10.0)
	health.damage(10.0)
	_check(zero_sources.size() == 2 and zero_sources[1] == null, "Healing rearms zero transition")
	health.heal(100.0)
	_check(gauge.value == 100.0 and gauge.maximum == 100.0 and is_equal_approx(gauge.recovery_rate, 100.0 / 1.2), "Gauge initial/max/rate")
	gauge.set_process(false)
	_check(gauge.consume() == 100.0 and gauge.value == 0.0, "Consume returns snapshot and clears")
	_check(hud.gauge_bar.value == 0.0 and hud.gauge_label.text == "ATTACK  0 / 100", "Gauge HUD synchronized")
	var zero_count := gauge_events.size()
	gauge.consume()
	_check(gauge_events.size() == zero_count, "No duplicate unchanged gauge notification")
	for fps in [30, 60]:
		gauge.consume()
		for step in range(int(fps * 0.6)):
			gauge._process(1.0 / fps)
		_check(absf(gauge.value - 50.0) < 0.0001, "Half recovery at 0.6 seconds")
		for step in range(int(fps * 0.6)):
			gauge._process(1.0 / fps)
		_check(absf(gauge.value - 100.0) < 0.0001, "Partitioned recovery at 1.2 seconds")
		gauge._process(10.0)
		_check(gauge.value == 100.0, "Gauge upper clamp")
	gauge.consume()
	gauge._process(-1.0)
	gauge._process(NAN)
	_check(gauge.value == 0.0, "Invalid delta ignored")
	# Use the real _process path at both caps; elapsed is summed callback delta.
	gauge.set_process(true)
	var durations: Array[float] = []
	for fps in [30, 60]:
		Engine.max_fps = fps
		await _ticks(10)
		gauge.consume()
		var elapsed := 0.0
		var started := Time.get_ticks_usec()
		var rendered := Engine.get_frames_drawn()
		while gauge.value < gauge.maximum and elapsed < 2.0:
			await process_frame
			elapsed += root.get_process_delta_time()
			await physics_frame
		var wall := (Time.get_ticks_usec() - started) / 1000000.0
		durations.append(elapsed)
		print("GAUGE cap=", fps, " delta_seconds=", elapsed, " wall_seconds=", wall, " rendered_frames=", Engine.get_frames_drawn() - rendered, " value=", gauge.value)
		_check(absf(elapsed - 1.2) < 0.09 and gauge.value == 100.0, "Normal callback recovery at cap " + str(fps))
	_check(absf(durations[0] - durations[1]) < 0.09, "30/60 recovery equivalent within callback quantization")
	Engine.max_fps = 60
	await _reset(Vector3(0, 0, 6), 0)
	gauge.set_process(false)
	gauge._process(2.0)
	_check(sprite.request_attack_preview(), "Attack accepted at full gauge")
	_check(gauge.value == 0.0 and player.get_node("AttackPreview").attack_start_gauge == 100.0, "Preview consumption and snapshot")
	gauge._process(0.3)
	_check(not sprite.request_attack_preview() and is_equal_approx(gauge.value, 25.0), "Rejected overlap does not consume")
	await _ticks(32)
	await process_frame
	_check(sprite.state == &"Idle", "Stationary attack returns to idle")
	_check(sprite.request_attack_preview() and gauge.value == 0.0 and is_equal_approx(player.get_node("AttackPreview").attack_start_gauge, 25.0), "Attack allowed below full")
	await _ticks(32)
	await process_frame
	# Attack in midair cannot change the movement physics or permanently stick.
	held.jump = 1.0
	await _ticks(8)
	_check(sprite.request_attack_preview(), "Airborne preview allowed provisionally")
	await _ticks(30)
	await process_frame
	_check(sprite.state == &"Fall", "Airborne attack returns to fall")
	held.clear()
	await _ticks(35)
	_check(sprite.state == &"Idle", "Air attack lands and recovers")
	gauge.set_process(true)
	# Shared balance Resources do not share mutable runtime state.
	var other: Node = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(other)
	health.damage(25.0)
	gauge.consume()
	_check(other.get_node("HealthComponent").current_hp == 100.0 and other.get_node("AttackGaugeComponent").value == 100.0, "Independent component instances")
	other.free()
	var fixed: Vector2 = hud.panel.get_global_rect().position
	held.camera_right = 1.0
	held.move_up = 1.0
	await _ticks(45)
	_check(hud.panel.get_global_rect().position == fixed, "HUD screen position fixed through move/orbit")
	held.clear()
	_refresh()
	for dimensions in [Vector2i(1152, 720), Vector2i(800, 600), Vector2i(640, 360)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var bounds: Rect2 = hud.panel.get_global_rect()
		_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "HUD within resized viewport " + str(dimensions))
		_check(bounds.encloses(hud.hp_label.get_global_rect()) and bounds.encloses(hud.gauge_label.get_global_rect()) and bounds.encloses(hud.debug_label.get_global_rect()), "HUD content contained")
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/m05_hud_%dx%d.png" % [dimensions.x, dimensions.y])
	for event in gauge_events:
		_check(event.x >= 0.0 and event.x <= 100.0 and event.y == 100.0, "Every gauge signal bounded")
	_check(gauge_events.size() > 10, "Recovery emits value changes")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M05 HP/gauge/HUD: clamps, signals, zero transition, 1.2s at 30/60, preview snapshots, low gauge, instance isolation, screen fixed, resize")
	main.free()
	quit(0 if failures.is_empty() else 1)
