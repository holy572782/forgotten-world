extends "res://tests/combat_feedback.gd"
var blocks: Array[Dictionary] = []

func _saved_settings() -> void:
	var weapon_path := "res://.godot/audio_pitch_weapon.tres"
	var defense_path := "res://.godot/audio_pitch_defense.tres"
	if "--reload" in OS.get_cmdline_user_args():
		var weapon: Resource = load(weapon_path)
		var defense: Resource = load(defense_path)
		_check(is_equal_approx(weapon.swing_pitch_scale,0.8) and is_equal_approx(weapon.hit_pitch_scale,1.2),"Both weapon pitches persist across processes")
		_check(is_equal_approx(defense.block_success_pitch_scale,0.73),"Block pitch persists across processes")
		_check(weapon.swing_volume_db == -17 and weapon.hit_volume_db == -21 and defense.block_success_volume_db == -19,"Pitch saving is independent of volume")
		_check(weapon.swing_sound.resource_path.ends_with("mz_evasion1.ogg") and weapon.hit_sound.resource_path.ends_with("mz_slash1.ogg") and defense.block_success_sound.resource_path.ends_with("mz_sword2.ogg"),"All assigned streams survive reload")
		return
	var weapon: Resource = load("res://resources/combat_feedback.tres").snapshot()
	weapon.swing_pitch_scale = 0.8
	weapon.hit_pitch_scale = 1.2
	weapon.swing_volume_db = -17
	weapon.hit_volume_db = -21
	var defense: Resource = load("res://resources/defense_settings.tres").duplicate()
	defense.block_success_pitch_scale = 0.73
	defense.block_success_volume_db = -19
	_check(ResourceSaver.save(weapon,weapon_path) == OK and ResourceSaver.save(defense,defense_path) == OK,"Save both existing settings Resources")
	for entry in [[weapon,"swing_pitch_scale"],[weapon,"hit_pitch_scale"],[defense,"block_success_pitch_scale"]]:
		var found := false
		for property in entry[0].get_property_list():
			if property.name != entry[1]: continue
			var limits: PackedStringArray = property.hint_string.split(",")
			found = (property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0 and limits.size() >= 3
			if found: found = is_equal_approx(limits[0].to_float(),0.5) and is_equal_approx(limits[1].to_float(),2.0) and is_equal_approx(limits[2].to_float(),0.01)
		_check(found,"Inspector pitch range/storage: "+entry[1])

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--reload" in OS.get_cmdline_user_args():
		await _saved_settings()
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
		feedback = player.get_node("CombatFeedback")
		initial_weapon = combat.equipped_weapon.duplicate()
		initial_weapon.motion = Motion.new()
		visual = initial_weapon.attack_visual
		combat.defense = combat.defense.duplicate()
		combat.attack_accepted.connect(func(_id: int,_combo: int): accepted.append(Engine.get_physics_frames()))
		combat.hit.connect(func(victim: Node): hits += 1; victim_ids.append(victim.get_instance_id()))
		combat.state_changed.connect(func(next: int): events.append(next))
		feedback.swing_presented.connect(func(_id: int):
			winds.append({"pitch":feedback.swing_audio.pitch_scale,"volume":feedback.swing_audio.volume_db})
			_check(feedback.swing_audio.playing and feedback.swing_audio.stream.resource_path.ends_with("mz_evasion1.ogg"),"Actual swing playback uses Evasion1"))
		feedback.impact_presented.connect(func(_receiver: Node):
			impacts.append({"pitch":feedback.hit_audio.pitch_scale,"volume":feedback.hit_audio.volume_db})
			_check(feedback.hit_audio.playing and feedback.hit_audio.stream.resource_path.ends_with("mz_slash1.ogg"),"Confirmed impact playback uses Slash1"))
		feedback.block_presented.connect(func(_source: Node):
			blocks.append({"pitch":feedback.block_audio.pitch_scale,"volume":feedback.block_audio.volume_db})
			_check(feedback.block_audio.playing and feedback.block_audio.stream.resource_path.ends_with("mz_sword2.ogg"),"Successful block playback uses Sword2"))
		await _ticks(15)
		var defaults: Resource = load("res://resources/combat_feedback.tres")
		_check(defaults.swing_pitch_scale == 1 and defaults.hit_pitch_scale == 1 and combat.defense.block_success_pitch_scale == 1,"All initial pitches are one")
		for names in [["mz_evasion1","Evasion1"],["mz_slash1","Slash1"],["mz_sword2","Sword2"]]:
			var path: String = "res://assets/audio/sfx/"+names[0]+".ogg"
			var source_path: String = "res://RPGツクールMZのaudio/se/"+names[1]+".ogg"
			var stream: AudioStream = load(path)
			_check(stream.get_length() > 0 and not stream.loop,"Actual Ogg imports without a playback loop: "+names[1])
			_check(FileAccess.get_sha256(path) == FileAccess.get_sha256(source_path),"Copied bytes equal exact supplied file: "+names[1])
		for values in [Vector2(0.8,1.2),Vector2(1.2,0.8)]:
			await _setup()
			combat.equipped_weapon.feedback.swing_pitch_scale = values.x
			combat.equipped_weapon.feedback.hit_pitch_scale = values.y
			combat.equipped_weapon.feedback.swing_volume_db = -17
			combat.equipped_weapon.feedback.hit_volume_db = -21
			await _begin()
			await _done(true)
			_check(winds.size() == 3 and impacts.size() == 3 and hits == 3,"Combo retains three swings/actual impacts with no extra sound")
			for entry in winds: _check(is_equal_approx(entry.pitch,values.x) and entry.volume == -17,"Swing pitch/volume independent")
			for entry in impacts: _check(is_equal_approx(entry.pitch,values.y) and entry.volume == -21,"Hit pitch/volume independent")
			_check(blocks.is_empty(),"Attacking alone never plays block success")
		await _setup()
		var source := Node3D.new()
		main.add_child(source)
		_press("guard",true)
		await _ticks(3)
		_check(combat.state == combat.State.Guard and blocks.is_empty(),"Guard pose/holding input alone is silent")
		for pitch in [0.8,1.2]:
			combat.defense.block_success_pitch_scale = pitch
			combat.defense.block_success_volume_db = -19
			source.global_position = player.global_position + player.facing_world*2
			var hp: float = health.current_hp
			var count := blocks.size()
			health.damage(10,source)
			_check(hp-health.current_hp == 5 and blocks.size() == count+1,"One actual front hit produces one block cue and existing half damage")
			_check(is_equal_approx(blocks.back().pitch,pitch) and blocks.back().volume == -19,"Block pitch/volume independent of weapon sound")
		var previous := blocks.size()
		source.global_position = player.global_position - player.facing_world*2
		health.damage(10,source)
		health.damage(10)
		source.global_position = player.global_position
		health.damage(10,source)
		health.damage(0,source)
		health.damage(-10,source)
		health.damage(NAN,source)
		_check(blocks.size() == previous,"Rear, unknown, colocated, zero and invalid damage never give false block success")
		source.global_position = player.global_position + player.facing_world*2
		combat.defense.guard_damage_multiplier = 0.0 # Private fixture; production stays 0.5.
		var hp: float = health.current_hp
		health.damage(10,source)
		_check(health.current_hp == hp and blocks.size() == previous+1,"Full mitigation still presents successful defense")
		combat.defense.guard_damage_multiplier = 0.5
		_press("guard",false)
		await _ticks(3)
		previous = blocks.size()
		health.damage(10,source)
		_check(blocks.size() == previous,"Damage outside Guard does not play success")
		source.free()
		await _saved_settings()
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("COMBAT AUDIO PITCH PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
