extends "res://tests/in_place_attack.gd"
## Observe real state/physics/animation callbacks, including pre-change timing.
var baseline := false
var record: Dictionary = {}
var records: Array[Dictionary] = []

func _sample_state(next: int) -> void:
	if record.is_empty(): return
	if next == combat.State.Return:
		record.return_tick = Engine.get_physics_frames()-start_tick
		record.distance = combat._travel_start.distance_to(combat._destination)
		record.duration = combat._duration
		record.return_count += 1
	elif next == combat.State.Idle:
		record.end_tick = Engine.get_physics_frames()-start_tick

func _collect(queue := false, safe_end := true) -> void:
	var measured_speeds: Array[float] = []
	for tick in range(700):
		if not combat.is_busy(): break
		if queue and target.alive() and not combat.queued and combat.can_combo_select(target): combat.request_followup(target)
		var was_returning: bool = combat.state == combat.State.Return
		var previous_position: Vector3 = player.global_position
		var previous_tick := Engine.get_physics_frames()
		await _ticks(1)
		if not baseline and was_returning:
			var step_distance := previous_position.distance_to(player.global_position)
			var step_seconds := float(Engine.get_physics_frames()-previous_tick) / 60.0
			_check(step_distance <= combat._active_motion.return_speed*step_seconds+0.001, "Return step never exceeds speed, including arrival")
			if combat.state == combat.State.Return:
				var measured := step_distance / step_seconds
				measured_speeds.append(measured)
				_check(absf(measured-combat._active_motion.return_speed) < 0.03, "Actual full-tick velocity is constant without easing")
		_check(combat.return_anchor == anchor, "Original sequence anchor unchanged")
		if sprite._attacking:
			_check_sync()
			var slash: AnimatedSprite3D = player.get_node("SlashEffect")
			_check(slash.visible and slash.frame == sprite.frame, "Common attack clock preserved")
		if combat.state == combat.State.Return:
			_check(sprite.combat_pose == &"Return" and not sword.visible and not player.get_node("SlashEffect").visible, "Return keeps its pose with no attack overlays")
	_check(not combat.is_busy() and not rig.follow_locked, "Return always exits and releases camera")
	if safe_end: _check(combat.return_error < 0.002, "Safe return reaches original anchor")
	record.hits = hits
	record.attacks = accepted.duplicate()
	record.slots = combat._sequence_slots
	record.stock = combat.stock.current
	record.error = combat.return_error
	record.measured_speeds = measured_speeds
	if record.return_count > 0:
		var expected: float = record.distance / combat._active_motion.return_speed
		if baseline: expected = clampf(expected,combat._active_motion.minimum_travel_time,combat._active_motion.maximum_travel_time)
		_check(is_equal_approx(record.duration,expected), "Return duration is distance/speed with no time limits")
		if safe_end: _check(absf(float(record.end_tick-record.return_tick)/60.0-record.duration) <= 0.05, "Physical return duration matches plan within draw/physics ticks")
	records.append(record.duplicate(true))

func _case(label: String, distance: float, count := 1, lethal := 0, values: Dictionary = {}, jitter := 0.0, change_after_start := false) -> Dictionary:
	await _prepare(distance)
	combat.equipped_weapon.max_combo_hits = count
	for key in values: combat.equipped_weapon.motion.set(key,values[key])
	if lethal > 0: target.health.damage(target.health.current_hp-lethal*10)
	record = {"name":label,"return_tick":0,"end_tick":0,"return_count":0,"distance":0.0,"duration":0.0}
	await _begin()
	if jitter > 0: player.global_position.x += jitter
	if change_after_start:
		combat.equipped_weapon.motion.return_speed = 1.0
		combat.equipped_weapon.motion.set("return_minimum_travel_time",1.0)
		combat.equipped_weapon.motion.set("return_maximum_travel_time",1.0)
	await _collect(count > 1)
	_check(hits == (lethal if lethal > 0 else count), "Same hit count "+label)
	_check(accepted.size() == hits and combat.stock.current == 3-hits, "Same paid swings and no empty attacks "+label)
	records[-1].approach = accepted[0]
	return records[-1]

func _saved_resource() -> void:
	var path := "res://.godot/return_motion_saved_weapon.tres"
	if "--reload" in OS.get_cmdline_user_args():
		var saved := load(path) as WeaponData
		_check(saved != null and saved.motion != null, "Fresh process loads weapon motion")
		if saved != null and saved.motion != null:
			_check(saved.motion.return_speed == 17.0 and saved.motion.get("return_minimum_travel_time") == 0.07 and saved.motion.get("return_maximum_travel_time") == 0.29, "Speed and legacy Resource fields survive restart")
			_check(saved.motion.minimum_travel_time == 0.31 and saved.motion.maximum_travel_time == 0.46, "Approach limits persist independently")
			_check(saved.motion.snapshot() != saved.motion, "Per-weapon runtime snapshot remains isolated")
		return
	var weapon := initial_weapon.duplicate() as WeaponData
	weapon.motion = Motion.new()
	weapon.motion.return_speed = 17
	weapon.motion.set("return_minimum_travel_time",0.07)
	weapon.motion.set("return_maximum_travel_time",0.29)
	weapon.motion.minimum_travel_time = 0.31
	weapon.motion.maximum_travel_time = 0.46
	_check(ResourceSaver.save(weapon,path) == OK, "Save per-weapon return settings")
	var exported := []
	for property in weapon.motion.get_property_list():
		if property.name in ["return_speed","return_minimum_travel_time","return_maximum_travel_time"]:
			_check((property.usage & PROPERTY_USAGE_STORAGE) != 0, "Existing Resource fields remain stored")
			_check(((property.usage & PROPERTY_USAGE_EDITOR) != 0) == (property.name == "return_speed"), "Only Return Speed is editable; legacy limits hidden")
			exported.append(property.name)
	_check(exported.size() == 3, "Return Speed and both legacy fields remain compatible")

func _run() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--reload" in OS.get_cmdline_user_args():
		await _saved_resource()
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
		initial_weapon = combat.equipped_weapon.duplicate()
		initial_weapon.motion = Motion.new()
		visual = initial_weapon.attack_visual
		combat.attack_accepted.connect(func(_id: int,_combo: int): accepted.append(Engine.get_physics_frames()-start_tick))
		combat.hit.connect(func(_victim: Node): hits += 1)
		combat.state_changed.connect(_sample_state)
		await _ticks(15)
		var source_hash := FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres")
		for distance in [1.3,1.5,2.5,4.8]:
			var result := await _case("distance_"+str(distance),distance)
			_check(result.return_count == (0 if distance == 1.3 else 1), "No return when no approach")
		for count in [2,3]: await _case("combo_"+str(count),2.5,count)
		for lethal in [1,2]: await _case("lethal_"+str(lethal),2.5,3,lethal)
		if not baseline:
			var defaults := Motion.new()
			_check(defaults.return_speed == 12, "Provisional constant Return Speed default is 12m/s")
			_check(defaults.approach_speed == 12 and defaults.minimum_travel_time == 0.25 and defaults.maximum_travel_time == 0.4, "Approach defaults unchanged")
			await _case("slow_return",2.5,1,0,{"return_speed":2.0})
			await _case("new_limits",2.5,1,0,{"return_minimum_travel_time":0.2,"return_maximum_travel_time":0.22})
			await _case("approach_only",2.5,1,0,{"minimum_travel_time":0.35,"maximum_travel_time":0.5})
			var tiny := await _case("sub_mm_jitter",1.3,1,0,{},0.0005)
			_check(tiny.return_count == 0 and tiny.error < 0.001, "Sub-millimetre drift never starts return or snaps body")
			var real := await _case("over_epsilon",1.3,1,0,{},0.0015)
			_check(real.return_count == 1, "Real displacement above epsilon still returns")
			await _case("invalid",2.5,1,0,{"return_speed":NAN,"return_minimum_travel_time":-1.0,"return_maximum_travel_time":INF})
			await _case("reversed_limits",2.5,1,0,{"return_minimum_travel_time":0.3,"return_maximum_travel_time":0.02})
			var snapshot := await _case("snapshot",2.5,1,0,{},0.0,true)
			_check(is_equal_approx(snapshot.duration,records[2].duration), "Editing source settings mid-sequence cannot change the active return")
			await _saved_resource()
			var previous: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/return_travel_before.json"))
			for old in previous:
				for current in records:
					if old.name != current.name: continue
					_check(absf(old.approach-current.approach) <= 2 and absf(old.return_tick-current.return_tick) <= 2, "Approach and return-start timing preserved "+old.name)
					_check(old.hits == current.hits and old.stock == current.stock and old.slots == current.slots, "Combat outcome unchanged "+old.name)
			_check(records[1].duration < 0.1 and records[8].duration > 0.35, "Neither former minimum nor maximum limits return duration")
			_check(is_equal_approx(records[9].duration,records[2].duration) and is_equal_approx(records[10].duration,records[2].duration), "Legacy return limits and approach bounds cannot change return speed")
			var double_distance := await _case("double_distance",1.9)
			_check(absf(double_distance.duration/records[1].duration-2.0) < 0.001, "Doubling return distance doubles planned time")
			await _case("faster_return",2.5,1,0,{"return_speed":24.0})
			_check(is_equal_approx(records[-1].duration*2.0,records[2].duration), "Changing Return Speed applies proportionally at every distance")
			await _case("negative_speed",1.3,1,0,{"return_speed":-1.0},0.02)
			_check(combat._active_motion.return_speed == 0.1, "Invalid negative speed is safely bounded without a duration cap")
		_check(FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres") == source_hash, "User-authored motion Resource untouched")
		var output := "return_baseline_" if baseline else "return_travel_"
		FileAccess.open("res://.godot/"+output+str(Engine.max_fps)+".json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("RETURN TRAVEL PASS: ",assertions," assertions; fps cap=",Engine.max_fps,"; baseline=",baseline)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
