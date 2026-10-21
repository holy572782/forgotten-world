extends SceneTree
## Pixel/Resource audit plus actual production Sprite3D rendering. No combat rules mocked.
const Shield = preload("res://scripts/player/shield_visual_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	root.size = Vector2i(960, 720)
	Engine.max_fps = 60
	var main = load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode = 0 # Isolate this legacy trial from the F5 enemy.
	main.get_node("TestArena").transform = Transform3D.IDENTITY
	root.add_child(main)
	var player = main.get_node("Player")
	var sprite = player.get_node("AnimatedSprite3D")
	var shadow = sprite.get_node("Shadow")
	var rig = main.get_node("CameraRig")
	player.reset_motion(Vector3(0, 0, 6))
	rig.snap_to_target()
	for i in range(15):
		await physics_frame
		await process_frame
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	sprite.set_process(false)
	rig.set_physics_process(false)
	rig.set_process(false)
	var shield: Shield = sprite.equipped_shield
	_check(shield != null and shield.is_valid() and shield.display_name == "鉄の盾", "Iron Shield equipped")
	var path := "res://assets/sprites/player/iron_shield_guard.png"
	_check(FileAccess.get_sha256(path) == "5e826bd080609e5900a14d3e5f5a46508bb995332c6a35fdd133016e3815220a", "Original file hash")
	_check(FileAccess.get_sha256(path) == FileAccess.get_sha256("res://画像フォルダ/主人公/鉄の盾.png"), "Byte identical source")
	var source := Image.new()
	source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	var texture: Texture2D = load(path)
	_check(source.get_size() == Vector2i(144, 192) and source.get_format() == Image.FORMAT_RGBA8, "RGBA dimensions")
	_check(source.get_data() == texture.get_image().get_data() and not texture.get_image().has_mipmaps(), "Lossless unmipped import")
	var alpha_counts := {0: 0, 253: 0, 255: 0}
	for y in range(192):
		for x in range(144):
			var alpha := roundi(source.get_pixel(x, y).a * 255)
			_check(alpha_counts.has(alpha), "Expected alpha values")
			alpha_counts[alpha] += 1
	_check(alpha_counts == {0: 10071, 253: 6, 255: 17571}, "Transparent and partially transparent pixels preserved")
	var sides := ["down", "left", "right", "up"]
	var bounds := [Rect2i(0,3,46,44),Rect2i(0,4,44,43),Rect2i(4,4,44,43),Rect2i(4,2,44,45)]
	for row in range(4):
		var animation := StringName("guard_" + sides[row])
		_check(shield.guard_frames.get_frame_count(animation) == 3, "Three authored poses per direction")
		for col in range(3):
			var atlas: AtlasTexture = shield.guard_frames.get_frame_texture(animation, col)
			var rect := Rect2i(col*48,row*48,48,48)
			_check(atlas.region == Rect2(rect) and atlas.filter_clip, "Explicit clipped rectangle")
			_check(atlas.get_image().get_data() == source.get_region(rect).get_data(), "Exact crop: no neighbor or pixel changes")
			_check(atlas.get_image().get_used_rect() == bounds[row], "Measured visible bounds and common foot baseline")
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		rig.rotation.y = deg_to_rad(yaw)
		rig.snap_to_target()
		rig._physics_process(1.0 / 60.0)
		await physics_frame
		await process_frame
		for sector in range(4):
			player.facing_world = [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT][sector].rotated(Vector3.UP,deg_to_rad(yaw))
			sprite.combat_pose = &"Guard"
			sprite._process(0.0)
			var expected := StringName("guard_" + ["down","right","up","left"][sector])
			_check(sprite.animation == expected and sprite.frame == 1 and not sprite.is_playing(), "Camera-relative held guard pose yaw=%s expected=%s actual=%s basis=%s" % [yaw,expected,sprite.animation,player._movement_basis()])
			_check(sprite.offset == Vector2(0,23) and is_equal_approx(sprite.pixel_size, 0.0375) and sprite.position == Vector3.ZERO, "Unscaled 48px foot pivot")
			_check(shadow.sprite_frames == sprite.sprite_frames and shadow.animation == sprite.animation and shadow.frame == 1, "Shadow frames synchronized")
			_check(sprite.material_override.get_shader_parameter("sprite_sheet") == texture, "Guard depth shader uses guard sheet")
			if yaw == 0.0 and "--capture" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png("res://.godot/m08_shield_"+str(sector)+".png") == OK, "Save actual guard render")
	# Reuse the existing M04 wall coordinates with the equipped guard artwork.
	player.reset_motion(Vector3(3,0,-7.5))
	rig.rotation.y = PI
	rig.snap_to_target()
	player.facing_world = Vector3.FORWARD
	sprite.combat_pose = &"Guard"
	for tick in range(25):
		rig._physics_process(1.0 / 60.0)
		sprite._process(0.0)
		await physics_frame
		await process_frame
	_check(not rig.safety_failed and rig.fader.entries.size() > 0, "M04 wall fade remains active during Guard")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://.godot/m08_shield_wall.png") == OK, "Save guard behind faded wall")
	# Equipment changes restore normal layout immediately; Resources remain isolated.
	var changed := shield.duplicate() as Shield
	changed.sprite_offset = Vector2(2,25)
	sprite.equipped_shield = changed
	sprite._process(0.0)
	_check(sprite.offset == Vector2(2,25) and shadow.offset == sprite.offset, "Per-shield layout")
	for pose in [&"", &"Stance", &"Approach", &"Return"]:
		sprite.combat_pose = pose
		sprite._process(0.0)
		_check(not String(sprite.animation).begins_with("guard_") and sprite.offset == Vector2(0,23), "Guard exit restores base presentation")
	sprite.combat_pose = &"Guard"
	sprite._process(0.0)
	_check(sprite.request_attack_preview(), "Guard to attack preview")
	_check(String(sprite.animation).begins_with("attack_") and sprite.offset == Vector2(0,23), "Attack resets layout before callback")
	sprite._attacking = false
	sprite.stop()
	for missing in [null, Shield.new()]:
		sprite.equipped_shield = missing
		sprite._process(0.0)
		_check(String(sprite.animation).begins_with("walk_") and sprite.frame == 1, "Missing reference falls back to legacy Guard")
	var broken := shield.duplicate(true) as Shield
	var invalid := AtlasTexture.new()
	broken.guard_frames.set_frame("guard_down", 1, invalid)
	_check(not broken.is_valid(), "Null atlas rejected")
	sprite.equipped_shield = broken
	sprite._process(0.0)
	_check(sprite.animation.begins_with("walk_"), "Invalid atlas fallback")
	sprite.equipped_shield = shield
	var other = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(other)
	_check(other.get_node("AnimatedSprite3D").sprite_frames != sprite.sprite_frames, "Per-player private SpriteFrames")
	_check(not load("res://assets/sprites/player/player_walk_frames.tres").has_animation("guard_down"), "Shared base Resource untouched")
	other.free()
	main.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M08 guard sprite: exact pixels/12 crops/alpha, four directions x four camera yaws, layout/attack exits, shadow shader, missing/null atlas fallback, Resource isolation")
	quit(0 if failures.is_empty() else 1)
