extends "res://tests/m04_camera.gd"
var sprite: AnimatedSprite3D

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	player = main.get_node("Player")
	rig = main.get_node("CameraRig")
	camera = rig.camera
	sprite = player.get_node("AnimatedSprite3D")
	for pair in [["walk", "歩行"], ["attack", "攻撃"], ["jump", "ジャンプ"]]:
		var path: String = "res://assets/sprites/player/player_%s.png" % pair[0]
		_check(FileAccess.get_sha256(path) == FileAccess.get_sha256("res://画像フォルダ/主人公/%s.png" % pair[1]), "Byte identical " + path)
		var source := Image.new()
		source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var texture: Texture2D = load(path)
		_check(source.get_size() == Vector2i(144, 192) and source.get_format() == Image.FORMAT_RGBA8, "RGBA dimensions " + path)
		_check(source.get_data() == texture.get_image().get_data() and not texture.get_image().has_mipmaps(), "Lossless import " + path)
		for row in range(4):
			var anim := StringName("%s_%s" % [pair[0], ["down", "left", "right", "up"][row]])
			var count := 4 if pair[0] == "walk" else 3
			_check(sprite.sprite_frames.get_frame_count(anim) == count, "Frame count")
			for slot in range(count):
				var col: int = [1, 0, 1, 2][slot] if count == 4 else slot
				var atlas: AtlasTexture = sprite.sprite_frames.get_frame_texture(anim, slot)
				_check(atlas.region == Rect2(col * 48, row * 48, 48, 48), "Atlas region")
				_check(atlas.get_image().get_used_rect().end.y == 47, "Common foot baseline")
	await _reset(Vector3(0, 0, 6), 0)
	await _ticks(10)
	_check(sprite.state == &"Idle", "Idle after spawn")
	for mouse in [false, true]:
		var event: InputEvent
		if mouse:
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = Vector2(40, 40) # Also exercise clicks over the HUD.
		else:
			event = InputEventKey.new()
			event.physical_keycode = KEY_J
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		_check(sprite.state == &"Attack", "J / left mouse attack")
		_check(not sprite.request_attack_preview(), "Reject overlapping attack")
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		held.move_right = 1.0
		held.camera_right = 1.0
		var seen: Array[int] = []
		for tick in range(28):
			await _ticks(1)
			await process_frame
			if sprite.state == &"Attack":
				var first_seen := not seen.has(sprite.frame)
				if first_seen: seen.append(sprite.frame)
				var atlas: AtlasTexture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
				_check(sprite.material_override.get_shader_parameter("sprite_sheet") == atlas.atlas, "Shader sheet follows attack")
				_check(sprite.get_node("Shadow").frame == sprite.frame, "Shadow follows frame")
				if capture and first_seen: await _image("attack_%d" % sprite.frame)
		_check(seen == [0, 1, 2], "All three attack frames complete while moving/orbiting")
		_check(sprite.state == &"Walk", "Attack returns to walk")
		held.clear()
		await _ticks(25)
		_check(sprite.state == &"Idle", "Returns to idle")
	await _reset(Vector3(0, 0, 6), 0)
	held.jump = 1.0
	var states: Array[StringName] = []
	for tick in range(65):
		await _ticks(1)
		await process_frame
		var first_seen := not states.has(sprite.state)
		if first_seen: states.append(sprite.state)
		if sprite.state in [&"Jump", &"Fall", &"Land"]:
			_check(String(sprite.animation).begins_with("jump_"), "Jump artwork for airborne/landing")
			_check(sprite.position == Vector3.ZERO and sprite.offset == Vector2(0, 23), "Foot pivot unchanged")
			if capture and first_seen: await _image(String(sprite.state))
	_check(states.has(&"Jump") and states.has(&"Fall") and states.has(&"Land") and states.has(&"Idle"), "Jump fall land idle sequence")
	held.clear()
	_refresh()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M05 animations: 36 regions, source pixels, foot pivots, J/mouse, complete attack and return, orbit, jump/fall/land")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _image(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/m05_animation_" + label + ".png") == OK, "Save animation image " + label)
