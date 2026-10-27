extends SceneTree
## Render real scene sprites against floor/walls; AI regressions run separately.
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
const EnemyScene = preload("res://scenes/enemies/practice_enemy.tscn")
var failures: Array[String] = []
var assertions := 0
var world: Node3D
var camera: Camera3D
var actor: CharacterBody3D
var player: CharacterBody3D
var ground: StaticBody3D
var wall: StaticBody3D
var sprite: AnimatedSprite3D
var sword: AnimatedSprite3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.32, 0.34)
	mesh.material_override = material
	body.add_child(mesh)
	world.add_child(body)
	return body

func _image() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _difference(before: Image, after: Image) -> Dictionary:
	var a := before.get_data()
	var b := after.get_data()
	var stride := 4 if before.get_format() == Image.FORMAT_RGBA8 else 3
	var mask: Dictionary = {}
	for pixel in range(before.get_width() * before.get_height()):
		var index := pixel * stride
		if a[index] != b[index] or a[index+1] != b[index+1] or a[index+2] != b[index+2]: mask[pixel] = true
	return mask

func _sword_mask() -> Dictionary:
	sword._sync_from_body()
	sword.update_depth_occlusion()
	sword.hide()
	var before := await _image()
	sword.show()
	return _difference(before, await _image())

func _pose(phase: float) -> void:
	actor._set_state(actor.State.ATTACK)
	actor.elapsed = phase * maxf(actor.active_attack.attack_seconds, actor.active_attack.hit_delay_seconds)
	sprite._process(0.0)
	sword._sync_from_body()
	sword.update_depth_occlusion()

func _spawn(ranged: bool) -> void:
	if is_instance_valid(actor): actor.free()
	actor = EnemyScene.instantiate()
	actor.player = player
	actor.settings = load("res://resources/enemies/ranged_practice.tres" if ranged else "res://resources/enemies/melee_practice.tres")
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.show_debug_state = false
	actor.debug_label.hide()
	actor.get_node("Targetable/HealthLabel").hide() # Text changes must not count as a visible flash.
	sprite = actor.get_node("AnimatedSprite3D")
	sword = actor.get_node("SlashEffect" if "--effect" in OS.get_cmdline_user_args() else "WeaponSwing")
	for name in ["WeaponSwing", "WeaponEffect", "SlashEffect"]:
		var layer := actor.get_node(name)
		layer.set_process(false)
		layer.hide()
	sprite.set_process(false)
	sword.set_process(false)
	sprite.get_node("Shadow").hide()

func _run() -> void:
	root.size = Vector2i(800, 600)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	world = Node3D.new()
	root.add_child(world)
	ground = _box(Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	wall = _box(Vector3(8, 5, 0.3), Vector3(0, 1.8, 3))
	wall.hide()
	wall.collision_layer = 0
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	camera.position = Vector3(0, 7, 10)
	camera.look_at(Vector3(0, 0.8, 0))
	player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(10, 0, 10)
	world.add_child(player)
	player.set_physics_process(false)
	player.hide()
	for ranged in [false, true]:
		_spawn(ranged)
		await physics_frame
		_check(not actor.get_node("Body").visible and sprite.visible, "Capsule replaced by selected character image")
		_check(is_equal_approx(actor.get_node("CollisionShape3D").shape.radius, 0.4) and actor.health.current_hp == 40, "Collision/health unchanged")
		_check(sprite.visual.weapon_visual == null if ranged else sprite.visual.weapon_visual == load("res://resources/weapons/iron_sword_visual.tres"), "Only soldier shares player iron sword Resource")
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			if "--flash" in OS.get_cmdline_user_args(): break
			camera.position = Vector3(0, 7, 10).rotated(Vector3.UP, deg_to_rad(yaw))
			camera.look_at(Vector3(0, 0.8, 0))
			for side_index in range(4):
				var expected: String = ["down", "right", "up", "left"][side_index]
				actor.facing = Vector3.BACK.rotated(Vector3.UP, side_index*PI/2 + deg_to_rad(yaw))
				for index in range(3):
					var weights := Motion.weights(sprite.visual.attack_frames, StringName("attack_"+expected), sprite.attack_ratios())
					_pose(Motion.phase_at(weights, index, 0.3))
					_check(sprite.animation == StringName("attack_" + expected) and sprite.frame == index, "Four camera yaws/directions follow attack elapsed time")
					_check(sword.visible == not ranged, "Sword only visible on melee attack")
					if not ranged:
						_check(sword.frame == index and sword.animation == sprite.animation and sword.transform == sprite.transform and sword.pixel_size == sprite.pixel_size, "Sword/body same phase/centre/pixel scale")
						_check(sword.offset == sprite.offset, "Weapon/effect uses the same centred layout as the player")
						ground.hide()
						var absent := await _sword_mask()
						ground.show()
						var present := await _sword_mask()
						_check(not present.is_empty() and absent == present, "All sword pixels survive floor at every yaw/direction/frame")
				if "--capture" in OS.get_cmdline_user_args() and yaw == 0.0:
					(await _image()).save_png("res://.godot/enemy_sprite_" + ("mage_" if ranged else "soldier_") + expected + ".png")
		camera.position = Vector3(0, 7, 10)
		camera.look_at(Vector3(0, 0.8, 0))
		actor.facing = Vector3.BACK
		for state in [actor.State.IDLE, actor.State.WINDUP, actor.State.DASH_APPROACH, actor.State.DASH_RETURN, actor.State.RECOVERY]:
			actor._set_state(state)
			sprite._process(0.0)
			sword._sync_from_body()
			_check(not sword.visible, "No sword on windup/approach/return/idle")
		actor._set_state(actor.State.CHASE)
		actor.velocity = Vector3.RIGHT
		sprite._process(0.0)
		_check(sprite.is_playing() and sprite.animation == &"walk_down", "Walking animates")
		await create_timer(0.2).timeout
		_check(sprite.frame != 0, "Walking advances actual engine frames")
		actor.velocity = Vector3.ZERO
		sprite._process(0.0)
		_check(not sprite.is_playing() and sprite.frame == 0, "Idle returns to a still frame")
		_pose(0.5)
		wall.show()
		wall.collision_layer = 1
		await physics_frame
		_check((await _sword_mask()).is_empty() if not ranged else not sword.visible, "Opaque wall hides weapon")
		sword.hide()
		var blocked := await _image()
		sprite.hide()
		_check(_difference(blocked, await _image()).is_empty(), "Opaque wall hides body")
		sprite.show()
		wall.hide()
		wall.collision_layer = 0
		var receiver: Node = actor.get_node("HitFeedback")
		actor._set_state(actor.State.IDLE)
		sprite._process(0.0)
		sword.hide()
		var normal := await _image()
		if "--capture" in OS.get_cmdline_user_args(): normal.save_png("res://.godot/enemy_sprite_normal_" + ("mage" if ranged else "soldier") + ".png")
		actor.health.damage(1, player)
		receiver.set_process(false)
		_check(receiver.remaining > 0 and sprite.material_overlay != null, "Confirmed damage flashes new character sprite")
		var flashed := await _image()
		var flash_pixels := _difference(normal, flashed)
		_check(not flash_pixels.is_empty(), "Flash is actually visible")
		sprite.hide()
		var silhouette := _difference(normal, await _image())
		sprite.show()
		_check(flash_pixels.keys().all(func(pixel: int) -> bool: return silhouette.has(pixel)), "Flash stays inside the real character silhouette")
		if "--capture" in OS.get_cmdline_user_args(): flashed.save_png("res://.godot/enemy_sprite_flash_" + ("mage" if ranged else "soldier") + ".png")
		wall.show()
		wall.collision_layer = 1
		await physics_frame
		var hidden_flash := await _image()
		receiver.clear_flash()
		_check(_difference(hidden_flash, await _image()).is_empty(), "Flash cannot show through an opaque wall")
		wall.hide()
		wall.collision_layer = 0
		_check(sprite.material_overlay == null, "Flash restores original material")
		actor.health.damage(100, player)
		sprite._process(0.0)
		sword._sync_from_body()
		_check(actor.state == actor.State.DEAD and not sword.visible and sprite.frame == 0 and sprite.position.y == 0.0 and not sprite.is_playing(), "Death immediately ends sword and holds a still image at the foot pivot")
	# Observe the real AI clock too, without invoking its attack/hit callbacks.
	for ranged in [false, true]:
		_spawn(ranged)
		player.position = Vector3(0, 0, 1.2)
		sprite.set_process(true)
		sword.set_process(true)
		actor.set_physics_process(true)
		var seen: Dictionary = {}
		for tick in range(180):
			await physics_frame
			await RenderingServer.frame_post_draw
			if actor.state == actor.State.ATTACK:
				seen[sprite.frame] = true
				_check(sword.visible == not ranged and (ranged or sword.frame == sprite.frame), "Real AI update keeps weapon and body in sync")
			if actor.state == actor.State.RECOVERY: break
		_check(seen.has(0) and seen.has(1) and seen.has(2), "Real attack displays all three frames")
		_check(actor.attack_count == 1, "One real AI attack only")
		if not ranged:
			_check(actor.global_position.distance_to(actor.attack_anchor) < 0.001 and player.get_node("HealthComponent").current_hp == 90, "Real melee hit and anchor return preserved")
		else:
			_check(not actor.shots.is_empty(), "Mage really releases the existing projectile")
	world.queue_free()
	await process_frame
	if failures.is_empty(): print("ENEMY SPRITES PASS: ", assertions, " assertions; fps cap=", Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
