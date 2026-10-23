extends "res://tests/iron_sword_animation.gd"
## Actual attack callbacks and authored transparent images; no added damage path.
var weapon_fx: AnimatedSprite3D
var slash_fx: AnimatedSprite3D
var restarts := 0

func _fx_off(label: String) -> void:
	_check(not weapon_fx.visible and not slash_fx.visible,label)

func _sync_fx() -> void:
	_check(slash_fx.visible and slash_fx.animation == sprite.animation and slash_fx.frame == sprite.frame,"Default slash direction/frame mirrors body")
	_check(is_equal_approx(slash_fx.frame_progress,sprite.frame_progress),"Slash sub-frame phase shares body clock")
	for fx in [weapon_fx,slash_fx]:
		_check(not fx.is_playing(),"Effect has no independent running timer")
		if fx.visible: _check(fx.transform == sprite.transform and fx.pixel_size == sprite.pixel_size and fx.billboard == sprite.billboard,"Active effect keeps native pixel size and body transform")
		_check(not fx.no_depth_test,"Effect retains world depth test")

func _end_fx() -> void:
	await _end()
	_fx_off("No effect remains after return")

func _weighted_frames() -> SpriteFrames:
	var result := visual.slash_effect.frames.duplicate() as SpriteFrames
	for side in ["down","left","right","up"]:
		var name := StringName("attack_"+side)
		var texture := result.get_frame_texture(name,0)
		result.clear(name)
		for weight in [1.0,2.0,1.0,3.0,1.0]: result.add_frame(name,texture,weight)
	return result

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	sword = player.get_node("WeaponSwing")
	weapon_fx = player.get_node("WeaponEffect")
	slash_fx = player.get_node("SlashEffect")
	health = player.get_node("HealthComponent")
	rig = main.get_node("CameraRig")
	target = main.get_node("TrainingEnemy/Targetable")
	target.get_parent().position = origin+Vector3(0,0,-2.5)
	for path in ["TrainingEnemySecond","TrainingEnemyThird"]: main.get_node(path).position = Vector3(12,0,10)
	initial_weapon = combat.equipped_weapon
	visual = initial_weapon.attack_visual
	combat.hit.connect(func(_victim: Node): hits += 1; _check(sprite.frame == combat.settings.hit_frame,"Unchanged hit frame"))
	combat.attack_accepted.connect(func(_id: int,_combo: int):
		restarts += 1
		_check(slash_fx.visible and slash_fx.frame == 0 and slash_fx.frame_progress == 0.0,"Every real attack restarts slash at phase zero"))
	await _ticks(15)
	_fx_off("No effects at rest")
	_check(not visual.weapon_effect.enabled and visual.weapon_effect.frames == null,"Missing second material stays disabled, not invented")
	var effect_path := "res://assets/sprites/weapons/one_handed_sword_white_slash.png"
	var source_path := "res://画像フォルダ/武器/武器エフェクト/片手剣エフェクト白.png"
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(effect_path))
	_check(FileAccess.get_sha256(effect_path) == FileAccess.get_sha256(source_path),"Byte-identical supplied effect")
	_check(image.get_size() == Vector2i(336,448) and image.get_data() == load(effect_path).get_image().get_data(),"All effect RGBA including translucent pixels survives import")
	for row in range(4):
		var name := StringName("attack_"+["down","left","right","up"][row])
		for col in range(3):
			var atlas: AtlasTexture = visual.slash_effect.frames.get_frame_texture(name,col)
			var rect := Rect2i(col*112,row*112,112,112)
			_check(atlas.region == Rect2(rect) and atlas.filter_clip and atlas.get_image().get_data() == image.get_region(rect).get_data(),"Exact transparent crop "+str(row)+str(col))
	# Independent count and duration weights, start/end, playback speed and direction controls.
	var config := visual.slash_effect.duplicate() as WeaponEffectData
	config.frames = _weighted_frames()
	_check(config.sample("attack_down",0.0).x == 0 and config.sample("attack_down",0.5).x == 3,"Five unequal-duration frames follow normalized attack")
	config.start_phase = 0.2
	config.end_phase = 0.8
	_check(config.sample("attack_down",0.19).x < 0 and config.sample("attack_down",0.2).x == 0 and config.sample("attack_down",0.8).x < 0,"Exact phase window gates visibility")
	config.playback_speed = 2.0
	_check(config.sample("attack_down",0.49).x == 4 and config.sample("attack_down",0.51).x < 0,"Faster effect completes once within window")
	config.enabled_directions = PackedStringArray(["up"])
	_check(config.sample("attack_down",0.3).x < 0 and config.sample("attack_up",0.3).x >= 0,"Direction may be individually disabled")
	config.enabled = false
	_check(config.sample("attack_up",0.3).x < 0,"Effect disabled independently")
	for yaw in [0.0,90.0,180.0,270.0]:
		await _reset(yaw,0.64)
		await _start()
		_check(slash_fx.visible and slash_fx.frame == 0,"Slash is visible immediately at attack start")
		var seen: Dictionary = {}
		while sprite._attacking:
			await _ticks(1)
			if not sprite._attacking: break
			_sync_fx()
			_check(not weapon_fx.visible,"Unprovided WeaponEffect does not duplicate white slash")
			if not seen.has(slash_fx.frame):
				seen[slash_fx.frame] = true
				await _capture_iron("effect_"+str(int(yaw))+"_"+str(slash_fx.frame))
		_check(seen.size() == 3,"All effect frames under camera yaw "+str(yaw))
		await _end_fx()
	for speed in [0.5,2.0]:
		await _reset(40,0.64)
		combat.equipped_weapon.attack_speed_multiplier = speed
		await _start()
		_press("camera_right",true)
		for tick in range(160):
			await _ticks(1)
			if not sprite._attacking: break
			_sync_fx()
		_press("camera_right",false)
		await _end_fx()
	# Exercise BOTH slots using the supplied image only as a test fixture; production uses it once.
	await _reset(0,1.2)
	var replacement := visual.duplicate() as WeaponAttackVisualData
	replacement.weapon_effect = visual.slash_effect.duplicate()
	replacement.weapon_effect.offset_up = Vector2(3,-2)
	replacement.weapon_effect.frames = _weighted_frames()
	combat.equipped_weapon.attack_visual = replacement
	await _start()
	var weighted_seen: Dictionary = {}
	while sprite._attacking:
		await _ticks(1)
		if not sprite._attacking: break
		weighted_seen[weapon_fx.frame] = true
		_check(weapon_fx.visible and slash_fx.visible,"Both independent effect slots can be active")
		_check(weapon_fx.offset == sprite.offset+replacement.weapon_effect.direction_offset(String(sprite.animation).get_slice("_",1)),"Effect direction offsets applied without scaling")
	_check(weighted_seen.size() == 5 and visual.weapon_effect.frames == null,"Different frame count and resource isolation")
	await _end_fx()
	# Combo count and speed do not create extra damage or lingering FX.
	for limit in [3,5]:
		await _reset(0,0.32)
		combat.equipped_weapon.max_combo_hits = limit
		combat.stock.settings = combat.stock.settings.duplicate()
		combat.stock.settings.maximum = limit
		combat.stock._current = limit
		target.health.balance = target.health.balance.duplicate()
		target.health.balance.max_hp = 200
		target.health.heal(200)
		var previous := restarts
		_check(combat.request_attack(target),"Combo starts")
		for tick in range(500):
			if not combat.is_busy(): break
			if not combat.queued: combat.request_followup(target)
			await _ticks(1)
			if not sprite._attacking: _fx_off("Effects clear between combo strikes")
		_check(hits == limit and restarts-previous == limit and combat.stock.current == 0,"One visual restart, cost and hit per real strike")
		hits = 0
	# Loss, hurt, manual cancel, direction return and guard must clear presentation.
	for mode in ["death","hurt","cancel","direction","guard","missing","null_atlas"]:
		await _reset(0,0.64)
		combat.stock.settings.maximum = 3
		combat.stock._current = 3
		if mode == "death": target.health.damage(target.health.current_hp-10)
		await _start()
		if mode == "death":
			for tick in range(140):
				await _ticks(1)
				if combat._empty_slot: break
			_check(combat._empty_slot,"Lethal hit enters existing silent wait")
		elif mode == "hurt": health.damage(1)
		elif mode == "cancel": combat.cancel()
		elif mode == "direction": _press("move_right",true)
		elif mode == "guard": _press("guard",true)
		elif mode == "missing": combat._active_weapon.attack_visual = null
		elif mode == "null_atlas":
			var broken := visual.duplicate() as WeaponAttackVisualData
			broken.slash_effect = visual.slash_effect.duplicate()
			broken.slash_effect.frames = visual.slash_effect.frames.duplicate()
			for index in range(3): broken.slash_effect.frames.set_frame(sprite.animation,index,AtlasTexture.new())
			combat._active_weapon.attack_visual = broken
		await _ticks(2)
		_fx_off("Clear on "+mode)
		for action in ["guard","move_right"]: _press(action,false)
		combat.cancel()
		hits = 0
	main.queue_free()
	await _ticks(2)
	if failures.is_empty(): print("WEAPON EFFECTS PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
