extends "res://tests/combat_audio_pitch.gd"
var jumps: Array[Dictionary] = []
var starts: Array[Dictionary] = []

func _key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _right(pressed: bool, point := Vector2(900,650)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _persist_action_audio() -> void:
	var movement_path := "res://.godot/action_audio_movement.tres"
	var defense_path := "res://.godot/action_audio_defense.tres"
	if "--reload" in OS.get_cmdline_user_args():
		var movement: Resource = load(movement_path)
		var defense: Resource = load(defense_path)
		_check(is_equal_approx(movement.jump_pitch_scale,0.82) and movement.jump_volume_db == -20,"Jump pitch and volume persist across processes")
		_check(is_equal_approx(defense.guard_start_pitch_scale,1.71) and defense.guard_start_volume_db == -22,"Guard start pitch and volume persist across processes")
		_check(movement.jump_sound.resource_path.ends_with("mz_jump1.ogg") and defense.guard_start_sound.resource_path.ends_with("mz_equip1.ogg"),"Jump1 and Equip1 references persist")
		_check(defense.block_success_sound.resource_path.ends_with("mz_sword2.ogg") and defense.block_success_pitch_scale == 1.0,"Sword2 remains an independent success cue")
		return
	var movement: Resource = player.movement.duplicate()
	var defense: Resource = combat.defense.duplicate()
	movement.jump_pitch_scale = 0.82
	movement.jump_volume_db = -20
	defense.guard_start_pitch_scale = 1.71
	defense.guard_start_volume_db = -22
	_check(ResourceSaver.save(movement,movement_path) == OK and ResourceSaver.save(defense,defense_path) == OK,"Save existing Movement/Defense Resources")
	for entry in [[movement,"jump_sound"],[movement,"jump_volume_db"],[movement,"jump_pitch_scale"],[defense,"guard_start_sound"],[defense,"guard_start_volume_db"],[defense,"guard_start_pitch_scale"]]:
		var exposed := false
		for property in entry[0].get_property_list():
			if property.name != entry[1]: continue
			exposed = (property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0
			if String(entry[1]).ends_with("pitch_scale"):
				var limits: PackedStringArray = property.hint_string.split(",")
				exposed = exposed and limits.size() >= 3
				if exposed: exposed = is_equal_approx(limits[0].to_float(),0.5) and is_equal_approx(limits[1].to_float(),2.0) and is_equal_approx(limits[2].to_float(),0.01)
		_check(exposed,"Inspector and storage expose "+entry[1])

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--reload" in OS.get_cmdline_user_args():
		await _persist_action_audio()
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
		player.movement = player.movement.duplicate()
		combat.defense = combat.defense.duplicate()
		combat.attack_accepted.connect(func(_id: int,_combo: int): accepted.append(Engine.get_physics_frames()))
		combat.hit.connect(func(victim: Node): hits += 1; victim_ids.append(victim.get_instance_id()))
		combat.state_changed.connect(func(next: int): events.append(next))
		feedback.jump_presented.connect(func():
			jumps.append({"pitch":feedback.jump_audio.pitch_scale,"volume":feedback.jump_audio.volume_db})
			_check(feedback.jump_audio.playing and feedback.jump_audio.stream.resource_path.ends_with("mz_jump1.ogg"),"Accepted jump actually plays Jump1")
			_check(player.velocity.y == player.movement.jump_speed and player._jump_consumed,"Jump sound follows actual launch physics"))
		feedback.guard_start_presented.connect(func():
			starts.append({"pitch":feedback.guard_start_audio.pitch_scale,"volume":feedback.guard_start_audio.volume_db})
			_check(combat.state == combat.State.Guard and feedback.guard_start_audio.playing and feedback.guard_start_audio.stream.resource_path.ends_with("mz_equip1.ogg"),"Guard entry actually plays Equip1"))
		feedback.block_presented.connect(func(_source: Node):
			blocks.append({"pitch":feedback.block_audio.pitch_scale})
			_check(feedback.block_audio.playing and feedback.block_audio.stream.resource_path.ends_with("mz_sword2.ogg"),"Only confirmed defense plays Sword2"))
		await _ticks(15)
		await _setup()
		_check(player.movement.jump_pitch_scale == 1.0 and combat.defense.guard_start_pitch_scale == 1.5,"Default jump/start pitches are 1.0/1.5")
		for names in [["mz_jump1","Jump1"],["mz_equip1","Equip1"]]:
			var path: String = "res://assets/audio/sfx/"+names[0]+".ogg"
			var original: String = "res://RPGツクールMZのaudio/se/"+names[1]+".ogg"
			var stream: AudioStream = load(path)
			_check(stream.get_length() > 0 and not stream.loop and FileAccess.get_sha256(path) == FileAccess.get_sha256(original),"Exact supplied non-looping asset: "+names[1])
		_key_event(KEY_SPACE,true)
		await _ticks(2)
		_check(jumps.size() == 1,"Space starts exactly one jump sound")
		_key_event(KEY_SPACE,false)
		await _ticks(1)
		_key_event(KEY_SPACE,true)
		_key_event(KEY_I,true)
		await _ticks(2)
		_check(jumps.size() == 1 and starts.is_empty() and combat.state == combat.State.Idle,"Airborne jump/guard inputs produce no false cues")
		_key_event(KEY_I,false)
		var apex := player.global_position.y
		for tick in range(75):
			await _ticks(1)
			apex = maxf(apex,player.global_position.y)
		_check(player.is_on_floor() and jumps.size() == 1 and apex > 1.15 and apex < 1.35,"Held input/landing are silent and jump height is preserved")
		_key_event(KEY_SPACE,false)
		await _ticks(2)
		_key_event(KEY_SPACE,true)
		await _ticks(2)
		_check(jumps.size() == 2,"New valid jump after release presents once")
		_key_event(KEY_SPACE,false)
		await _ticks(75)
		_check(jumps.size() == 2 and player.is_on_floor(),"Ordinary landing never plays Jump1")
		_key_event(KEY_I,true)
		await _ticks(12)
		_check(starts.size() == 1 and starts[0].pitch == 1.5 and blocks.is_empty(),"I guard entry plays Equip1 at 1.5; holding never plays Sword2")
		_key_event(KEY_SPACE,true)
		await _ticks(3)
		_key_event(KEY_SPACE,false)
		_check(jumps.size() == 2 and starts.size() == 1,"Jump forbidden during Guard is silent")
		var source := Node3D.new()
		main.add_child(source)
		source.global_position = player.global_position+player.facing_world*2
		var hp: float = health.current_hp
		health.damage(10,source)
		_check(hp-health.current_hp == 5 and blocks.size() == 1 and starts.size() == 1,"Confirmed block plays Sword2 without restarting Equip1")
		source.free()
		_key_event(KEY_I,false)
		await _ticks(3)
		_check(starts.size() == 1 and not combat.is_busy(),"Guard release does not play Equip1")
		_right(true)
		await _ticks(12)
		_check(starts.size() == 2 and combat.state == combat.State.Guard,"Right mouse enters Guard once")
		_key_event(KEY_I,true)
		await _ticks(2)
		_right(false)
		await _ticks(2)
		_check(starts.size() == 2 and combat.state == combat.State.Guard,"Overlapping guard bindings do not re-enter or repeat sound")
		_key_event(KEY_I,false)
		await _ticks(3)
		_right(true,Vector2(20,20))
		await _ticks(3)
		_right(false,Vector2(20,20))
		_check(starts.size() == 2 and not combat.is_busy(),"UI-consumed guard input has no start sound")
		await _setup(3.0)
		await _begin()
		_key_event(KEY_SPACE,true)
		await _ticks(3)
		_key_event(KEY_SPACE,false)
		_check(jumps.size() == 2,"Approach pose and combat-blocked jump never play Jump1")
		await _done()
		await _setup()
		player.movement.jump_pitch_scale = 0.8
		player.movement.jump_volume_db = -20
		combat.defense.guard_start_pitch_scale = 1.2
		combat.defense.guard_start_volume_db = -22
		_key_event(KEY_SPACE,true)
		await _ticks(2)
		_key_event(KEY_SPACE,false)
		await _ticks(75)
		_check(jumps.size() == 3 and is_equal_approx(jumps.back().pitch,0.8) and jumps.back().volume == -20,"Jump pitch and volume independently reach AudioStreamPlayer")
		_key_event(KEY_I,true)
		await _ticks(3)
		_check(starts.size() == 3 and is_equal_approx(starts.back().pitch,1.2) and starts.back().volume == -22,"Guard start pitch and volume independently reach AudioStreamPlayer")
		_key_event(KEY_I,false)
		await _ticks(3)
		await _persist_action_audio()
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("ACTION AUDIO PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
