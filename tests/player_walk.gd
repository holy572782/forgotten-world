extends "res://tests/m04_camera.gd"
## Real SpriteFrames + live locomotion, camera and renderer; no artwork rewriting.
const SHEET := "res://assets/sprites/player/player_walk.png"
const SOURCE_SHA256 := "c54a1719ab9eeea8730c1da79dac38538d2a133e998e7dea6e34af83534c3683"
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
	_check(FileAccess.get_sha256(SHEET) == SOURCE_SHA256, "Original PNG bytes unchanged")
	var source := Image.new()
	_check(source.load_png_from_buffer(FileAccess.get_file_as_bytes(SHEET)) == OK, "Read original PNG for test")
	var imported: Texture2D = load(SHEET)
	_check(source.get_size() == Vector2i(144, 192), "144x192 original resolution")
	_check(imported.get_image().get_data() == source.get_data(), "Imported texture pixels equal original PNG")
	_check(not imported.get_image().has_mipmaps(), "No mipmaps")
	_check(sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Nearest filtering")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and not sprite.no_depth_test, "Billboard/depth retained")
	var rows := [&"walk_down", &"walk_left", &"walk_right", &"walk_up"]
	for row in range(4):
		_check(sprite.sprite_frames.get_frame_count(rows[row]) == 3, "Three frames per direction")
		for column in range(3):
			var atlas: AtlasTexture = sprite.sprite_frames.get_frame_texture(rows[row], column)
			_check(atlas.region == Rect2(column * 48, row * 48, 48, 48), "Exact frame region")
			var rect := atlas.get_image().get_used_rect()
			_check(rect.end.y == 47, "All twelve frames share foot baseline")
			_check(absf(sprite.position.y + (24 - rect.end.y) * sprite.pixel_size) < 0.00001, "Opaque foot edge at body origin")
	# Screen direction remains consistent for all camera cardinal yaws.
	var directions := {"move_down": &"walk_down", "move_right": &"walk_right", "move_up": &"walk_up", "move_left": &"walk_left"}
	for yaw in [0, 90, 180, 270]:
		for action in directions:
			await _reset(Vector3(0, 0, 6), yaw)
			held[action] = 1.0
			await _ticks(24)
			await process_frame
			_check(sprite.animation == directions[action] and sprite.is_playing(), "Walking direction yaw=%s action=%s" % [yaw, action])
			if yaw == 0: await _image(action)
			held.clear()
			await _ticks(30)
			await process_frame
			_check(not sprite.is_playing() and sprite.frame == 1 and sprite.animation == directions[action], "Idle center and last direction")
	# All three frames advance naturally, rather than a still image labelled walking.
	await _reset(Vector3(0, 0, 6), 0)
	held.move_down = 1.0
	var frames_seen: Dictionary = {}
	for tick in range(36):
		await _ticks(1)
		await process_frame
		frames_seen[sprite.frame] = true
	_check(frames_seen.size() == 3, "Live animation visits all three frames")
	# Diagonal vectors are mapped to a nearest cardinal, without quantizing movement.
	var controller = load("res://scripts/player/player_controller.gd")
	for direction in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var world: Vector3 = controller.input_to_world(direction, Basis.IDENTITY)
		var sector: int = controller.direction_sector(world, Basis.IDENTITY, 4)
		var cardinals := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
		_check(world.dot(cardinals[sector]) > 0.7, "Nearest diagonal display")
	await _reset(Vector3(0, 0, 6), 0)
	held.move_up = 1.0
	held.camera_right = 1.0
	await _ticks(60)
	await process_frame
	_check(sprite.animation == &"walk_up" and sprite.is_playing(), "Walking during camera orbit")
	await _image("orbit")
	# Idle facing is a world direction; orbit changes the displayed side.
	held.clear()
	await _ticks(35)
	var facing: Vector3 = player.facing_world
	var before := sprite.animation
	rig.rotation.y += PI
	rig.snap_to_target()
	await _ticks(3)
	await process_frame
	_check(player.facing_world == facing and sprite.animation != before and sprite.frame == 1, "Idle orbit preserves world facing")
	await _reset(Vector3(0, 0, 6), 0)
	held.jump = 1.0
	held.move_right = 1.0
	await _ticks(18)
	_check(player.position.y > 0.5, "Jump remains active")
	_check(absf(sprite.global_position.y - player.global_position.y - 23 * sprite.pixel_size) < 0.0001, "Foot baseline follows jump")
	await _image("jump")
	held.clear()
	await _ticks(60)
	_check(player.is_on_floor(), "Lands with new sprite")
	# Wall-behind character with production B occlusion enabled.
	await _reset(Vector3(3, 0, -7.5), 180)
	await _ticks(25)
	_check(not rig.fader.entries.is_empty(), "B wall fade still active")
	await _image("wall")
	# Capture the exact authored poses at the gameplay scale, without resizing artwork.
	await _reset(Vector3(0, 0, 6), 0)
	sprite.set_process(false)
	for animation_name in rows:
		sprite.animation = animation_name
		sprite.stop()
		for index in range(3):
			sprite.frame = index
			await _image("%s_%d" % [animation_name, index])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS player walk: original pixels, 12 atlas regions/feet, four yaws/directions, idle, live animation, diagonals, orbit, jump, B fade")
	main.free()
	quit(0 if failures.is_empty() else 1)

func _image(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/player_walk_" + label + ".png") == OK, "Save " + label)
