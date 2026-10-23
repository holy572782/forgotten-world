extends "res://tests/iron_sword_animation.gd"
const MotionSettings = preload("res://scripts/combat/attack_motion_settings.gd")
## Real animation/physics; no manual hit callbacks. Save/reload runs in separate processes.
var motion: MotionSettings
var slash: AnimatedSprite3D
var accepted: Array[int] = []
var impacts: Array[Vector2] = []
var finished_at := 0
var returned_at := 0
var started_at := 0
var records: Array[Dictionary] = []

func _prepare(duration := 0.64, yaw := 0.0) -> void:
	await _reset(yaw, duration)
	combat.equipped_weapon.motion = MotionSettings.new()
	motion = combat.equipped_weapon.motion
	accepted.clear()
	impacts.clear()
	finished_at = 0
	returned_at = 0
	hits = 0

func _begin() -> void:
	started_at = Engine.get_physics_frames()
	_check(combat.request_attack(target), "Start real motion")
	await _phase(combat.State.Attack)

func _done(queue := false) -> void:
	for tick in range(700):
		if not combat.is_busy(): break
		if queue and target.alive() and not combat.queued: combat.request_followup(target)
		await _ticks(1)
	_check(not combat.is_busy(), "Motion always terminates")
	_check(combat.return_error < 0.03, "Return anchor retained")
	_check(not sword.visible and not slash.visible, "No residual weapon/effect")

func _travel_case(speed: float, delay: float, return_speed: float, final_wait: float) -> Dictionary:
	await _prepare()
	motion.approach_speed = speed
	motion.approach_attack_delay = delay
	motion.return_speed = return_speed
	motion.final_attack_wait = final_wait
	await _begin()
	var approach_ticks := accepted[0] - started_at
	await _done()
	_check(hits == 1 and combat.stock.current == 2, "Travel/waits leave hit and cost unchanged")
	return {"approach":approach_ticks,"post":returned_at-finished_at,"return":Engine.get_physics_frames()-returned_at}

func _persistence() -> void:
	var path := "res://.godot/attack_motion_saved_weapon.tres"
	var original_ratios: PackedFloat32Array = initial_weapon.motion.frame_time_ratios.duplicate()
	var original_effect_start: float = initial_weapon.attack_visual.slash_effect.start_percent
	for property in WeaponEffectData.new().get_property_list():
		if property.name in ["start_percent","duration_percent"]:
			_check((property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) == 0, "Inspector exposes percent alias without duplicate storage")
		elif property.name in ["start_phase","end_phase","playback_speed"]:
			_check((property.usage & PROPERTY_USAGE_EDITOR) == 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0, "Legacy representation is storage only")
	if "--reload" in OS.get_cmdline_user_args():
		var saved := load(path) as WeaponData
		_check(saved != null and saved.motion != null, "Saved weapon reloads in fresh process")
		if saved != null:
			_check(saved.motion.frame_time_ratios == PackedFloat32Array([1,0.4,1]) and saved.motion.approach_attack_delay == 0.2 and saved.motion.final_attack_wait == 0.3, "Motion ratios/waits persist")
			_check(is_equal_approx(saved.attack_visual.slash_effect.start_percent, 25) and is_equal_approx(saved.attack_visual.slash_effect.duration_percent, 45), "Inspector aliases persist via single canonical storage")
			_check(saved.attack_visual.slash_effect.offset_left == Vector2(3,-2), "Directional offset persists")
	else:
		var saved := initial_weapon.duplicate(true) as WeaponData
		saved.attack_visual = initial_weapon.attack_visual.duplicate()
		saved.attack_visual.slash_effect = initial_weapon.attack_visual.slash_effect.duplicate()
		saved.motion = MotionSettings.new()
		saved.motion.frame_time_ratios = PackedFloat32Array([1,0.4,1])
		saved.motion.approach_attack_delay = 0.2
		saved.motion.final_attack_wait = 0.3
		saved.attack_visual.slash_effect.start_percent = 25
		saved.attack_visual.slash_effect.duration_percent = 45
		saved.attack_visual.slash_effect.offset_left = Vector2(3,-2)
		_check(ResourceSaver.save(saved,path) == OK, "Save motion and effect resources")
		var stored := FileAccess.get_file_as_string(path)
		_check(not "start_percent =" in stored and not "duration_percent =" in stored, "No duplicate serialized timing aliases")
		_check(initial_weapon.motion.frame_time_ratios == original_ratios and initial_weapon.attack_visual.slash_effect.start_percent == original_effect_start, "Shared authored settings are unchanged")

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	sword = player.get_node("WeaponSwing")
	slash = player.get_node("SlashEffect")
	health = player.get_node("HealthComponent")
	rig = main.get_node("CameraRig")
	target = main.get_node("TrainingEnemy/Targetable")
	target.get_parent().position = origin+Vector3(0,0,-2.5)
	for path in ["TrainingEnemySecond","TrainingEnemyThird"]: main.get_node(path).position = Vector3(12,0,10)
	initial_weapon = combat.equipped_weapon
	visual = initial_weapon.attack_visual
	combat.attack_accepted.connect(func(_id: int,_combo: int): accepted.append(Engine.get_physics_frames()))
	combat.hit.connect(func(_victim: Node): hits += 1; impacts.append(Vector2(sprite.frame,sprite.attack_phase())))
	sprite.attack_completed.connect(func(): finished_at = Engine.get_physics_frames())
	combat.state_changed.connect(func(next: int):
		if next == combat.State.Return: returned_at = Engine.get_physics_frames())
	await _ticks(15)
	await _persistence()
	if "--reload" not in OS.get_cmdline_user_args():
		var base := await _travel_case(12,0,10,0)
		var slow := await _travel_case(2,0,10,0)
		var delayed := await _travel_case(12,0.2,10,0)
		var return_slow := await _travel_case(12,0,2,0)
		var final_wait := await _travel_case(12,0,10,0.3)
		_check(slow.approach > base.approach+5, "Approach primary speed adjusts bounded travel")
		_check(abs(delayed.approach-base.approach-12) <= 2, "Post-approach delay is independent")
		_check(return_slow["return"] > base["return"]+5, "Return primary speed adjusts bounded travel")
		_check(abs(final_wait.post-base.post-18) <= 2, "Final wait adds only configured time")
		records.append({"travel_default":base,"slow":slow,"delay":delayed,"return_slow":return_slow,"final_wait":final_wait})
		# Actual body / weapon / slash follow weighted phase under all camera directions.
		for yaw in [0.0,90.0,180.0,270.0]:
			await _prepare(0.72,yaw)
			motion.frame_time_ratios = PackedFloat32Array([1,0.4,1])
			motion.hit_frame_percent = 50
			await _begin()
			var seen: Dictionary = {}
			var counts := [0,0,0]
			while sprite._attacking:
				await _ticks(1)
				if not sprite._attacking: break
				_check_sync()
				_check(slash.visible and slash.frame == sprite.frame and is_equal_approx(slash.frame_progress,sprite.frame_progress), "Slash shares weighted clock")
				counts[sprite.frame] += 1
				if not seen.has(sprite.frame):
					seen[sprite.frame] = true
					await _capture_iron("motion_"+str(int(yaw))+"_"+str(sprite.frame))
			_check(seen.size() == 3 and counts[1] < counts[0] and counts[1] < counts[2], "Middle frame has shorter visible duration")
			_check(abs(finished_at-accepted[0]-43) <= 3, "Weighted frames preserve total swing duration")
			await _done()
			_check(hits == 1 and impacts[0].y >= 0.5 and impacts[0].y < 0.6, "Weighted within-frame hit occurs once")
		# Independent slash window, position and Q/E rotation on the live clock.
		await _prepare(1.0)
		combat.equipped_weapon.attack_visual = visual.duplicate(true)
		combat.equipped_weapon.attack_visual.slash_effect = visual.slash_effect.duplicate()
		var fx: WeaponEffectData = combat.equipped_weapon.attack_visual.slash_effect
		fx.start_percent = 25
		fx.duration_percent = 40
		fx.offset_up = Vector2(2,-1)
		fx.offset_left = Vector2(3,-2)
		await _begin()
		_press("camera_right",true)
		while sprite._attacking:
			await _ticks(1)
			if not sprite._attacking: break
			var phase: float = sprite.attack_phase()
			_check(slash.visible == (phase >= 0.25 and phase < 0.65), "Slash phase window independent of hit")
			if slash.visible: _check(slash.offset == sprite.offset+fx.direction_offset(String(sprite.animation).get_slice("_",1)), "Camera uses directional pixel correction")
		_press("camera_right",false)
		await _done()
		_check(hits == 1, "Visual window adds no damage")
		# Different counts use authored durations mapped to the same normalized time.
		await _prepare(0.8)
		combat.equipped_weapon.attack_visual = visual.duplicate(true)
		combat.equipped_weapon.attack_visual.attack_frames = visual.attack_frames.duplicate()
		var other: SpriteFrames = combat.equipped_weapon.attack_visual.attack_frames
		for side in ["down","left","right","up"]:
			var name := StringName("attack_"+side)
			var texture := other.get_frame_texture(name,0)
			other.clear(name)
			for weight in [1,2,1,2,1]: other.add_frame(name,texture,weight)
		await _begin()
		var five_seen: Dictionary = {}
		while sprite._attacking:
			await _ticks(1)
			if not sprite._attacking: break
			five_seen[sword.frame] = true
			_check(not sword.is_playing() and sword.visible, "Different-count weapon uses no second clock")
		_check(five_seen.size() == 5, "Five weapon frames against three body frames")
		await _done()
		await _prepare(0.8)
		var authored: SpriteFrames = sprite._base_frames
		sprite._base_frames = authored.duplicate()
		for side in ["down","left","right","up"]:
			var name := StringName("attack_"+side)
			var texture: Texture2D = authored.get_frame_texture(name,0)
			sprite._base_frames.clear(name)
			for weight in [1,2,1,2]: sprite._base_frames.add_frame(name,texture,weight)
		sprite._rebuild_guard_frames()
		await _begin()
		var body_seen: Dictionary = {}
		while sprite._attacking:
			await _ticks(1)
			if not sprite._attacking: break
			body_seen[sprite.frame] = true
			_check(sword.visible and sword.frame <= 2 and slash.visible, "Three-frame attachments share four-frame body phase")
		_check(body_seen.size() == 4 and abs(finished_at-accepted[0]-48) <= 3, "Body count differs without changing swing total")
		await _done()
		sprite._base_frames = authored
		sprite._rebuild_guard_frames()
		# Earlier/later endpoints and a frame shorter than a physics tick still hit once.
		for hit_config in [Vector2(0,0),Vector2(2,100),Vector2(1,50)]:
			await _prepare(0.1)
			motion.frame_time_ratios = PackedFloat32Array([1,0.001,1])
			motion.hit_frame = int(hit_config.x)
			motion.hit_frame_percent = hit_config.y
			await _begin()
			await _done()
			_check(hits == 1 and combat.stock.current == 2, "One hit even at endpoint or skipped short frame")
		# Combo gaps and lethal silent slots share changed duration/waits.
		for lethal in [false,true]:
			await _prepare(0.48)
			combat.equipped_weapon.combo_stance_duration = 0.3
			motion.final_attack_wait = 0.2
			if lethal: target.health.damage(target.health.current_hp-10)
			await _begin()
			await _done(true)
			_check(combat._sequence_slots == 3, "Changed rhythm still runs all planned slots")
			if lethal:
				_check(hits == 1 and accepted.size() == 1 and combat.stock.current == 2, "No empty swing or cost after first-strike kill")
			else:
				_check(hits == 3 and accepted.size() == 3, "Live combo preserves three hits")
				_check(abs(accepted[1]-accepted[0]-47) <= 3, "Configured combo stance adjusts interval")
			records.append({"lethal":lethal,"return_from_start":returned_at-started_at})
		_check(abs(records[-1].return_from_start-records[-2].return_from_start) <= 3, "Lethal and live sequences retain rhythm with custom waits")
		# Cancel new waits immediately using the existing controls.
		for wait_at in ["approach","final"]:
			for action in ["move_right","guard"]:
				await _prepare(0.32)
				motion.approach_attack_delay = 1.0 if wait_at == "approach" else 0.0
				motion.final_attack_wait = 1.0
				combat.equipped_weapon.max_combo_hits = 1
				_check(combat.request_attack(target), "Start interruptible wait")
				for tick in range(150):
					await _ticks(1)
					if (wait_at == "approach" and combat._elapsed > combat._duration and combat.state == combat.State.Approach) or (wait_at == "final" and not combat._finishing_reason.is_empty()): break
				_press(action,true)
				await _ticks(2)
				_check(combat.state == (combat.State.Guard if action == "guard" else combat.State.Return), "Existing input interrupts "+wait_at+" wait")
				_press(action,false)
				combat.cancel()
		# Invalid external resource edits are bounded without mutating source data.
		await _prepare()
		motion.approach_speed = NAN
		motion.return_speed = -1
		motion.minimum_travel_time = 0
		motion.maximum_travel_time = -1
		motion.frame_time_ratios = PackedFloat32Array([0,NAN,-1])
		motion.final_attack_wait = NAN
		combat.equipped_weapon.attack_duration = NAN
		await _begin()
		await _done()
		_check(hits == 1 and is_nan(motion.approach_speed), "Invalid timing cannot stall; source stays untouched")
		# A freed target during the new approach wait keeps the unstarted schedule.
		await _prepare(0.48)
		motion.approach_attack_delay = 0.3
		motion.final_attack_wait = 0.2
		combat.equipped_weapon.max_combo_hits = 1
		started_at = Engine.get_physics_frames()
		_check(combat.request_attack(target), "Start target-loss wait fixture")
		for tick in range(80):
			await _ticks(1)
			if combat.state == combat.State.Approach and combat._elapsed > combat._duration: break
		var expected_ticks: float = (combat._duration+0.3+0.48+0.2)*60.0
		motion.approach_attack_delay = 4.0
		motion.final_attack_wait = 4.0
		_check(combat._active_motion.approach_attack_delay == 0.3 and combat._active_motion.final_attack_wait == 0.2, "Active cycle owns an isolated motion snapshot")
		target.get_parent().free()
		await _done()
		_check(hits == 0 and accepted.is_empty() and combat.stock.current == 3, "Freed target wait creates no swing, hit or cost")
		_check(abs(returned_at-started_at-expected_ticks) <= 3, "Freed target preserves remaining approach wait, swing and final wait")
	if "--reload" not in OS.get_cmdline_user_args():
		FileAccess.open("res://.godot/attack_motion_metrics_"+str(Engine.max_fps)+".json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		print("MOTION METRICS ", JSON.stringify(records))
	main.queue_free()
	await _ticks(2)
	if failures.is_empty(): print("ATTACK MOTION PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
