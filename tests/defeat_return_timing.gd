extends "res://tests/m06_target_dash.gd"
## Real physics, animation and HP notifications. Never invoke a hit callback.
var assertions := 0
var origin := Vector3.ZERO
var accepted_ticks: Array[int] = []
var impact_ticks: Array[int] = []
var victim_ids: Array[int] = []
var return_tick := -1
var depleted_count := 0
var metrics: Array[Dictionary] = []
var death_tick := -1
var reference_ticks: Dictionary = {}

func _check(ok: bool, message: String) -> void:
	assertions += 1
	super._check(ok, message)

func _fresh(limit: int = 3, capacity: int = 3, lethal: int = 1, speed: float = 1.0, cost: int = 1) -> void:
	if is_instance_valid(main):
		combat.cancel()
		main.free()
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	combat.equipped_weapon = combat.equipped_weapon.duplicate()
	combat.equipped_weapon.hit_shape = WeaponData.HitShape.SINGLE_TARGET
	combat.equipped_weapon.max_combo_hits = limit
	combat.equipped_weapon.attack_speed_multiplier = speed
	combat.equipped_weapon.stock_cost_per_hit = cost
	combat.stock.settings = combat.stock.settings.duplicate()
	combat.stock.settings.maximum = capacity
	combat.stock._current = capacity
	target.health.balance = target.health.balance.duplicate()
	target.health.balance.max_hp = 200
	target.health.heal(200)
	if lethal > 0: target.health.damage(200 - lethal * 10)
	await _ticks(15)
	origin = player.global_position
	accepted_ticks.clear()
	impact_ticks.clear()
	victim_ids.clear()
	return_tick = -1
	depleted_count = 0
	death_tick = -1
	combat.attack_accepted.connect(func(_id: int, _combo: int): accepted_ticks.append(Engine.get_physics_frames()))
	combat.hit.connect(func(victim: Node):
		impact_ticks.append(Engine.get_physics_frames())
		victim_ids.append(victim.get_instance_id())
		_check(sprite.frame == combat.settings.hit_frame, "Actual central-frame impact"))
	combat.state_changed.connect(func(next: int):
		if next == combat.State.Return: return_tick = Engine.get_physics_frames())
	target.health.depleted.connect(func(_source: Node):
		depleted_count += 1
		death_tick = Engine.get_physics_frames())
	_check(combat.request_attack(target), "Start fixture")

func _to_return(queue: bool = false, capture_label: String = "") -> int:
	var captured_wait := false
	for tick in range(600):
		if return_tick >= 0: break
		if queue and is_instance_valid(target) and target.alive() and not combat.queued:
			combat.request_followup(target)
		await _ticks(1)
		if combat._empty_slot:
			_check(not sprite._attacking and String(sprite.animation).begins_with("walk_") and sprite.frame == 0, "Silent slot uses natural stance")
			_check(not player.get_node("WeaponSwing").visible, "Silent slot has no sword swing")
			_check(player.velocity.is_zero_approx(), "No drift during silent slot")
			if not captured_wait and not capture_label.is_empty() and "--capture" in OS.get_cmdline_user_args():
				captured_wait = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.godot/defeat_wait_"+capture_label+"_"+str(Engine.max_fps)+".png")
	_check(return_tick >= 0, "Sequence eventually starts return")
	return return_tick - accepted_ticks[0] if not accepted_ticks.is_empty() else -1

func _end() -> void:
	await _wait_idle()
	_check(player.global_position.distance_to(origin) < 0.03, "Existing return reaches original anchor")
	_check(not main.get_node("CameraRig").follow_locked and not combat.queued, "Return releases camera and queue")

func _until(condition: Callable, label: String) -> void:
	for tick in range(180):
		if condition.call(): return
		await _ticks(1)
	_check(false,"Phase timeout: "+label)

func _freed_chain() -> void:
	for mode in ["sync","deferred"]:
		await _fresh()
		var b: Node3D = main.get_node("TrainingEnemyThird/Targetable")
		var b_id := b.get_instance_id()
		_check(combat.request_followup(b), "Reserve live enemy before primary freed "+mode)
		if mode == "sync": target.health.depleted.connect(func(_source: Node): target.free())
		else: target.health.depleted.connect(func(_source: Node): enemy.queue_free())
		await _to_return()
		_check(victim_ids.has(b_id) and b.health.current_hp == 30 and accepted_ticks.size() == 2, "Freed primary safely chains to live reservation "+mode)
		_check(depleted_count == 1 and combat.stock.current == 1, "Freed chain preserves notifications and payments "+mode)
		await _end()

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--freed-chain" in OS.get_cmdline_user_args():
		await _freed_chain()
		main.queue_free()
		await process_frame
		for failure in failures: push_error(failure)
		if failures.is_empty(): print("FREED CHAIN PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
		quit(0 if failures.is_empty() else 1)
		return
	# Baseline with all strikes reserved: defeat may not shorten this rhythm.
	for pair in [[1,3],[2,3],[3,3],[5,5]]:
		await _fresh(pair[0],pair[1],0)
		var elapsed := await _to_return(true)
		reference_ticks[pair[0]] = elapsed
		_check(accepted_ticks.size() == pair[0], "Reference attack count "+str(pair))
		await _end()
	for lethal in [1,2,3]:
		await _fresh(3,3,lethal)
		var elapsed := await _to_return(true,"hit"+str(lethal))
		_check(depleted_count == 1 and target.health.current_hp == 0, "Death notification remains immediate and unique")
		_check(return_tick > death_tick and elapsed >= reference_ticks[3]-2, "Defeat does not shorten sequence hit="+str(lethal))
		_check(abs(elapsed-reference_ticks[3]) <= 4, "Defeat preserves normal rhythm hit="+str(lethal)+" ticks="+str(elapsed)+" reference="+str(reference_ticks[3]))
		_check(accepted_ticks.size() == lethal and impact_ticks.size() == lethal and combat.combo_hits == lethal, "No empty attacks or IDs after defeat")
		_check(combat.stock.current == 3-lethal, "No cost for silent remaining slots")
		metrics.append({"case":"lethal_"+str(lethal),"ticks":elapsed,"reference_ticks":reference_ticks[3],"strikes":accepted_ticks.size()})
		await _end()
	# Snapshot weapon count, available stock and speed; larger weapons are not hardcoded to three.
	for profile in [[1,3,1.0,1],[2,3,1.0,1],[5,5,1.0,1],[5,3,1.0,1],[5,5,2.0,2]]:
		await _fresh(profile[0],profile[1],0,profile[2],profile[3])
		var reference := await _to_return(true)
		await _end()
		await _fresh(profile[0],profile[1],1,profile[2],profile[3])
		var planned: int = mini(profile[0],int(profile[1]/profile[3]))
		combat.equipped_weapon.max_combo_hits = 99
		combat.equipped_weapon.attack_speed_multiplier = 0.1
		var elapsed := await _to_return()
		_check(combat._planned_hits == planned and combat._sequence_slots == planned, "Weapon/stock count snapshot "+str(profile))
		_check(abs(elapsed-reference) <= 6, "Speed and count independent silent rhythm "+str(profile)+" ticks="+str(elapsed)+" reference="+str(reference))
		_check(accepted_ticks.size() == 1 and impact_ticks.size() == 1 and combat.stock.current == profile[1]-profile[3], "Only actual strike paid "+str(profile))
		metrics.append({"case":"profile_"+str(profile),"ticks":elapsed,"reference_ticks":reference,"planned":planned})
		await _end()
	# Already-reserved B survives A's defeat, and new input can reserve B afterwards.
	for late in [false,true]:
		await _fresh()
		var b: Node3D = main.get_node("TrainingEnemyThird/Targetable")
		var b_id := b.get_instance_id()
		var a_id := target.get_instance_id()
		if not late: _check(combat.request_followup(b), "Reserve live B during approach")
		await _until(func(): return death_tick >= 0,"primary defeated")
		if late:
			await _until(func(): return combat._empty_slot,"late reservation stance")
			_check(combat.request_followup(b), "Reserve live B during silent slot")
		await _to_return()
		_check(victim_ids == [a_id,b_id] and b.health.current_hp == 30, "Live reservation continues after defeat late="+str(late))
		_check(accepted_ticks.size() == 2 and combat.stock.current == 1, "No automatic attacks on unreserved survivors")
		await _end()
	# Freed references: immediately in damage signal, deferred death, and disappearance pre-hit/approach.
	for mode in ["sync","deferred","pre_hit","approach"]:
		await _fresh()
		if mode == "sync": target.health.depleted.connect(func(_source: Node): target.free())
		elif mode == "deferred": target.health.depleted.connect(func(_source: Node): enemy.queue_free())
		elif mode == "approach": enemy.queue_free()
		elif mode == "pre_hit":
			await _until(func(): return not accepted_ticks.is_empty(),"delete pre-hit")
			enemy.queue_free()
		await _to_return()
		_check(combat.stock.current == (3 if mode == "approach" else 2), "Freed target never spends unpaid strikes "+mode)
		_check(accepted_ticks.size() <= 1 and combat._sequence_slots == 3, "Freed target preserves slots safely "+mode)
		await _end()
	# A reserved target may die while A remains alive. Preserve time, not an empty attack.
	await _freed_chain()
	await _fresh(3,3,0)
	var next: Node3D = main.get_node("TrainingEnemyThird/Targetable")
	_check(combat.request_followup(next), "Reserve doomed B")
	next.health.damage(1000)
	var elapsed := await _to_return()
	_check(abs(elapsed-reference_ticks[3]) <= 4 and accepted_ticks.size() == 1 and combat.stock.current == 2, "Dead reservation holds planned timing without spending")
	await _end()
	# New directional input and guard still preempt silent slots.
	for action in ["move_right","guard","cancel","player_death"]:
		await _fresh(5,5)
		await _until(func(): return combat._empty_slot,"cancellation stance")
		var before := Engine.get_physics_frames()
		if action == "cancel": combat.cancel()
		elif action == "player_death": player.get_node("HealthComponent").damage(1000)
		else: Input.action_press(action)
		await _ticks(2)
		if action == "move_right":
			_check(return_tick >= before and return_tick-before <= 2, "Direction return interrupts silent sequence immediately")
		elif action == "guard":
			_check(combat.state == combat.State.Guard and not sprite._attacking, "Guard interrupts silent sequence")
		else: _check(not combat.is_busy(), "Reset/player death cancels silent sequence "+action)
		_check(combat.stock.current == 4, "Cancellation has no silent cost")
		if action in ["move_right","guard"]: Input.action_release(action)
		if combat.is_busy(): await _end()
	# Safety regression: moved live target or a new obstacle still aborts immediately.
	for mode in ["moved","blocked"]:
		await _fresh(3,3,0)
		await _until(func(): return not accepted_ticks.is_empty(),"safety strike")
		if mode == "moved": enemy.position.z -= 0.2
		else: _block(player.global_position+Vector3.UP,Vector3(1,2,1))
		await _ticks(2)
		_check(return_tick >= 0 or not combat.is_busy(), "Safety abort retained "+mode)
		combat.cancel()
	FileAccess.open("res://.godot/defeat_return_metrics_"+str(Engine.max_fps)+".json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print(JSON.stringify(metrics))
	main.queue_free()
	await process_frame
	if failures.is_empty(): print("DEFEAT RETURN PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
