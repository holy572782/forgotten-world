extends "res://tests/m06_target_dash.gd"
var accepted: Array[int] = []

func _run() -> void:
	root.size = Vector2i(1152, 720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	target.health.balance = target.health.balance.duplicate()
	target.health.balance.max_hp = 200.0
	combat.hit.connect(func(_t: Node):
		hits += 1
		_check(sprite.frame == combat._active_motion.hit_frame, "Visible hit frame"))
	combat.attack_accepted.connect(func(id: int, _combo: int): accepted.append(id))
	await _ticks(20)
	var origin := player.global_position
	var stock = combat.stock
	_check(stock.current == 3 and stock.maximum == 3, "Initial stock")
	_check(not player.has_node("AttackGaugeComponent"), "No parallel legacy gauge")
	# Independent instances share settings, never runtime counts.
	var other := AttackStockComponent.new()
	other.settings = stock.settings
	root.add_child(other)
	stock.spend()
	_check(other.current == 3 and stock.current == 2, "Instance isolation")
	other.free()
	for fps in [30, 60]:
		stock._current = 0
		stock.set_recovery_allowed(false)
		stock.advance(10.0)
		_check(stock.current == 0, "Inhibited recovery")
		stock.set_recovery_allowed(true)
		for i in range(fps * 3): stock.advance(1.0 / fps)
		_check(stock.current == 2, "Two stocks in three seconds at " + str(fps))
		stock.advance(100.0)
		_check(stock.current == 3, "Recovery clamp")
	for fps in [30, 60]:
		Engine.max_fps = fps
		stock._current = 0
		stock.set_recovery_allowed(false)
		var started := Time.get_ticks_msec()
		for i in range(150):
			await _ticks(1)
			if stock.current > 0: break
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		_check(stock.current == 1 and absf(seconds - 1.5) < 0.15, "Real FREE recovery at " + str(fps))
		print("RECOVERY cap=", fps, " seconds=", seconds)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	stock._current = 3
	stock.spend()
	stock.advance(1.0)
	stock.set_recovery_allowed(false)
	stock.set_recovery_allowed(true)
	stock.advance(0.5)
	_check(stock.current == 2, "Entering combat discards fractional recovery")
	for pair in [[3,3], [2,3], [1,3], [5,3], [5,5]]:
		var limit: int = pair[0]
		var capacity: int = pair[1]
		combat.equipped_weapon = load("res://resources/weapons/one_handed_sword.tres") if limit == 3 else load("res://tests/fixtures/weapon_%d.tres" % limit)
		stock.settings = stock.settings.duplicate()
		stock.settings.maximum = capacity
		stock._current = capacity
		target.health.heal(200.0)
		var wall := _block(origin.lerp(target.global_position, 0.5) + Vector3.UP, Vector3(0.4,2,2))
		await _ticks(2)
		_check(not combat.can_select(target) and not combat.request_attack(target), "Weapon preserves wall rejection")
		_check(stock.current == capacity, "Wall rejection costs nothing")
		wall.free()
		await _ticks(2)
		var before_hp: float = target.health.current_hp
		var before_hits := hits
		_check(combat.request_attack(target), "Weapon starts " + str(pair))
		var weapon = combat.equipped_weapon
		combat.equipped_weapon = load("res://tests/fixtures/weapon_1.tres")
		_check(combat.equipped_weapon == weapon, "Busy equip rejected")
		var minimum_stock: int = stock.current
		for i in range(400):
			if not combat.is_busy(): break
			if limit == 3 and i == 0: Input.action_press("camera_right")
			if i == 6: Input.action_release("camera_right")
			var before: int = stock.current
			combat.request_followup()
			_check(stock.current == before, "Reservation never consumes")
			_check(not combat.request_followup(), "Queue capacity or limit rejects duplicate")
			await _ticks(1)
			_check(stock.current <= minimum_stock, "No recovery while busy")
			minimum_stock = stock.current
		Input.action_release("camera_right")
		var expected := mini(limit, capacity)
		_check(not combat.is_busy() and not combat.queued, "Returns and clears queue")
		_check(hits - before_hits == expected and before_hp - target.health.current_hp == expected * 10, "Weapon damage/count " + str(pair))
		_check(stock.current == capacity - expected, "Exact strike consumption")
		_check(combat.combo_hits == expected, "Weapon/stock independent limits")
		_check(player.global_position.distance_to(origin) < 0.03, "Anchor maintained")
		print("WEAPON ", pair, " hits=", hits - before_hits, " stock=", stock.current)
	# Real mouse press held across the entire cycle must not auto-repeat.
	combat.equipped_weapon = load("res://resources/weapons/one_handed_sword.tres")
	stock._current = 3
	target.health.heal(200)
	await _ticks(3)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = main.get_node("CameraRig").camera.unproject_position(enemy.global_position + Vector3.UP * 0.75)
	event.pressed = true
	var before_hits := hits
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _ticks(3)
	await _wait_idle()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(hits == before_hits + 1, "Held button gives exactly one hit")
	# Grace accepts another input, cancellation never consumes the queued strike.
	stock._current = 3
	_check(combat.request_attack(target), "Grace test start")
	for i in range(100):
		await _ticks(1)
		if combat._waiting: break
	_check(combat._waiting and combat.request_followup(), "Input after animation accepted")
	await _ticks(10)
	_check(combat.combo_hits == 2 and stock.current == 1, "Grace starts one next strike")
	_check(combat.request_followup(), "Cancel pending reservation")
	target.health.damage(1000)
	await _wait_idle()
	_check(stock.current == 1 and not combat.queued, "Death cancels unpaid reservation")
	target.health.heal(200)
	stock._current = 0
	_check(not combat.request_attack(target) and stock.current == 0, "Zero rejects without consumption")
	stock._current = 3
	_check(combat.request_attack(target), "Timeout test start")
	for i in range(100):
		await _ticks(1)
		if combat.state == combat.State.Attack: break
	sprite.stop()
	_check(combat.request_followup(), "Timeout queued")
	await _wait_idle()
	_check(not combat.queued and stock.current == 2 and combat.last_result.contains("timeout"), "Animation timeout clears unpaid queue")
	stock._current = 3
	_check(combat.request_attack(target) and combat.request_followup(), "Approach reservation")
	enemy.position.z += 0.2
	await _wait_idle()
	_check(stock.current == 3 and not combat.queued, "Moved target cancels approach without consumption")
	enemy.position.z -= 0.2
	await _ticks(2)
	_check(combat.request_attack(target) and combat.request_followup(), "Player death reservation")
	player.get_node("HealthComponent").damage(1000)
	_check(not combat.is_busy() and not combat.queued and stock.current == 3, "Player death clears queue")
	player.get_node("HealthComponent").heal(1000)
	await _settle(origin)
	for i in range(1, accepted.size()):
		_check(accepted[i] > accepted[i-1], "Unique monotonic attack IDs")
	var hud = main.get_node("HUD")
	_check(hud.gauge_label.text.ends_with("%d/%d" % [stock.current, stock.maximum]), "HUD stock synchronized")
	stock.settings = load("res://resources/attack_stock_settings.tres")
	stock._current = 3
	stock.stock_changed.emit(stock.current, stock.maximum)
	for size in [Vector2i(1152,720), Vector2i(800,600), Vector2i(640,360)]:
		root.size = size
		await _ticks(3)
		var bounds: Rect2 = hud.panel.get_global_rect()
		_check(Rect2(Vector2.ZERO, Vector2(size)).encloses(bounds), "HUD screen bounds " + str(size))
		_check(bounds.encloses(hud.debug_label.get_global_rect()), "HUD content bounds")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/m07_hud_%dx%d.png" % [size.x,size.y])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M07: weapon matrix, stock, queue, hold, grace, cancellation, timeout, HUD")
	stock._current = 3
	_check(combat.request_attack(target) and combat.request_followup(), "Scene exit with queued attack")
	root.remove_child(main)
	_check(not combat.queued, "Scene exit releases queue")
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
