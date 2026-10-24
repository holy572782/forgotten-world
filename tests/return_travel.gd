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
	for tick in range(700):
		if not combat.is_busy(): break
		if queue and target.alive() and not combat.queued and combat.can_combo_select(target): combat.request_followup(target)
		await _ticks(1)
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
	if record.return_count > 0:
		var expected: float = clampf(record.distance / combat._active_motion.return_speed,
			combat._active_motion.minimum_travel_time if baseline else combat._active_motion.get("return_minimum_travel_time"),
			combat._active_motion.maximum_travel_time if baseline else combat._active_motion.get("return_maximum_travel_time"))
		_check(is_equal_approx(record.duration,expected), "Distance/speed clamped by the correct travel bounds")
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
			_check(saved.motion.return_speed == 17.0 and saved.motion.get("return_minimum_travel_time") == 0.07 and saved.motion.get("return_maximum_travel_time") == 0.29, "All return settings persist after restart")
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
			_check((property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0, "Return setting editable and stored")
			exported.append(property.name)
	_check(exported.size() == 3, "Inspector exposes exactly the three return properties")

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
			_check(defaults.return_speed == 10 and defaults.get("return_minimum_travel_time") == 0.1 and defaults.get("return_maximum_travel_time") == 0.35, "Requested return defaults")
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
			_check(records[1].duration < 0.25 and records[2].duration > records[1].duration and is_equal_approx(records[3].duration,0.35), "Short/medium/long returns scale with distance and cap")
			_check(is_equal_approx(records[9].duration,0.2) and is_equal_approx(records[10].duration,records[2].duration), "Return and approach bounds act independently")
		_check(FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres") == source_hash, "User-authored motion Resource untouched")
		var output := "return_baseline_" if baseline else "return_travel_"
		FileAccess.open("res://.godot/"+output+str(Engine.max_fps)+".json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("RETURN TRAVEL PASS: ",assertions," assertions; fps cap=",Engine.max_fps,"; baseline=",baseline)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
