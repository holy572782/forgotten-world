extends "res://tests/m09_enemy_combat.gd"
## Authored 112px overlay: exact pixels, live attack clock, camera and cancellation.
var sword: AnimatedSprite3D
var rig: Node3D
var initial_weapon: WeaponData
var visual: WeaponAttackVisualData
var animations_seen: Dictionary = {}

func _reset(yaw: float = 0.0, duration: float = 0.64) -> void:
	for action in ["guard","camera_left","camera_right"]: _press(action,false)
	combat.cancel()
	await _ticks(3)
	health.heal(100)
	target.health.heal(100)
	combat.equipped_weapon = initial_weapon.duplicate()
	combat.equipped_weapon.attack_duration = duration
	combat.stock.set_recovery_allowed(true)
	combat.stock.advance(20)
	player.reset_motion(origin)
	rig.rotation.y = deg_to_rad(yaw)
	rig.snap_to_target()
	await _ticks(12)

func _check_sync() -> void:
	_check(sword.visible and sword.animation == sprite.animation and sword.frame == sprite.frame,"Same body/sword animation and frame")
	_check(is_equal_approx(sword.frame_progress,sprite.frame_progress),"Same sub-frame progress; no independent timer")
	_check(sword.transform == sprite.transform and sword.billboard == sprite.billboard and sword.pixel_size == sprite.pixel_size,"Shared centre transform, billboard and pixel size")
	var active: WeaponAttackVisualData = combat._active_weapon.attack_visual
	_check(sword.offset == sprite.offset+active.direction_offset(String(sprite.animation).get_slice("_",1)),"Direction pixel adjustment is relative to body centre")
	if sword.offset == sprite.offset:
		_check(sword.get_item_rect().get_center() == sprite.get_item_rect().get_center(),"112px and 48px canvas centres coincide")
	_check(sword.get_item_rect().size == Vector2(112,112) and sprite.get_item_rect().size == Vector2(48,48),"Native frame sizes; no 48/112 normalization")
	_check(not sword.no_depth_test and sword.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,"Pixel filtering and normal world depth")

func _capture_iron(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/iron_sword_"+label+"_"+str(Engine.max_fps)+".png") == OK,"Capture "+label)

func _start() -> void:
	_check(combat.request_attack(target),"Real target attack starts")
	await _phase(combat.State.Attack)
	_check(sword.visible and sword.frame == 0,"Attack-start signal shows authored first pose immediately")

func _end(expected_hits: int = 1) -> void:
	await _wait_idle()
	_check(not sword.visible and player.global_position.distance_to(origin) < 0.03,"Sword clears and existing return reaches anchor")
	_check(hits == expected_hits and combat.stock.current == 2,"Existing one hit/one stock preserved")
	hits = 0

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
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
	target.get_parent().position = origin+Vector3(0,0,-2.5)
	for path in ["TrainingEnemySecond","TrainingEnemyThird"]: main.get_node(path).position = Vector3(12,0,10)
	initial_weapon = combat.equipped_weapon
	visual = initial_weapon.attack_visual
	combat.hit.connect(func(_victim: Node):
		hits += 1
		_check(sprite.frame == combat._active_motion.hit_frame,"Existing authored hit frame unchanged"))
	await _ticks(15)
	_check(not sword.visible and sprite.visible,"No sword at rest")
	var path := "res://assets/sprites/weapons/iron_sword_attack.png"
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_check(FileAccess.get_sha256(path) == FileAccess.get_sha256("res://画像フォルダ/武器/鉄の剣.png"),"Byte-identical provided sheet")
	_check(image.get_size() == Vector2i(336,448) and image.get_data() == load(path).get_image().get_data(),"Lossless 336x448 import")
	for row in range(4):
		var name := StringName("attack_"+["down","left","right","up"][row])
		_check(visual.attack_frames.get_frame_count(name) == 3 and not visual.attack_frames.get_animation_loop(name),"Three authored poses in direction "+name)
		for col in range(3):
			var atlas: AtlasTexture = visual.attack_frames.get_frame_texture(name,col)
			var rect := Rect2i(col*112,row*112,112,112)
			_check(atlas.region == Rect2(rect) and atlas.filter_clip and atlas.get_image().get_data() == image.get_region(rect).get_data(),"Exact 112px crop "+name+str(col))
	# Four camera yaws exercise all existing body directions without a second map.
	for yaw in [0.0,90.0,180.0,270.0]:
		await _reset(yaw)
		await _start()
		var seen: Dictionary = {}
		for tick in range(100):
			await _ticks(1)
			if not sprite._attacking: break
			_check_sync()
			animations_seen[sprite.animation] = true
			if not seen.has(sprite.frame):
				seen[sprite.frame] = true
				await _capture_iron(String(sprite.animation)+"_"+str(sprite.frame))
		_check(seen.size() == 3,"All three poses displayed yaw="+str(yaw))
		await _end()
	_check(animations_seen.size() == 4,"All four body direction mappings used")
	# Q/E while a strike is playing must switch rows without losing its phase.
	for action in ["camera_left","camera_right"]:
		await _reset(40.0 if action == "camera_left" else 50.0,1.2)
		await _start()
		var rows: Dictionary = {}
		_press(action,true)
		for tick in range(110):
			await _ticks(1)
			if not sprite._attacking: break
			rows[sprite.animation] = true
			_check_sync()
		_press(action,false)
		_check(rows.size() >= 2,"Actual Q/E changes row with matching phase: "+action)
		await _end()
	# Replacement visual resource and direction offsets never mutate the original.
	for yaw in [0.0,90.0,180.0,270.0]:
		await _reset(yaw,0.32)
		var replacement := visual.duplicate() as WeaponAttackVisualData
		replacement.attack_frames = visual.attack_frames.duplicate()
		replacement.offset_down = Vector2(1,2)
		replacement.offset_left = Vector2(-3,4)
		replacement.offset_right = Vector2(3,-4)
		replacement.offset_up = Vector2(-1,-2)
		combat.equipped_weapon.attack_visual = replacement
		await _start()
		await _ticks(1)
		_check_sync()
		_check(sword.sprite_frames == replacement.attack_frames and visual.direction_offset(String(sprite.animation).get_slice("_",1)) == Vector2.ZERO,"Replaceable frames and isolated offsets")
		await _end()
	# Missing/null atlas at activation or mid-attack hides only the weapon.
	await _reset()
	combat.equipped_weapon.attack_visual = null
	await _start_without_visual()
	await _end()
	await _reset()
	var broken := visual.duplicate() as WeaponAttackVisualData
	broken.attack_frames = visual.attack_frames.duplicate()
	broken.attack_frames.set_frame("attack_up",0,AtlasTexture.new())
	combat.equipped_weapon.attack_visual = broken
	await _start_without_visual()
	await _end()
	await _reset()
	await _start()
	combat._active_weapon.attack_visual = null
	await _ticks(1)
	_check(not sword.visible and sprite._attacking,"Missing visual mid-strike does not cancel body attack")
	await _end()
	# Damage keeps its previous rule; guard keeps the supplied shield with no sword.
	await _reset()
	await _start()
	health.damage(1)
	await _ticks(1)
	_check(not sword.visible and player.get_node("DamageVisual").visible,"Hurt display hides the separate weapon")
	_press("guard",true)
	await _ticks(2)
	_check(not sword.visible and sprite.visible and String(sprite.animation).begins_with("guard_") and not player.get_node("DamageVisual").visible,"Existing shield/guard priority remains intact")
	await _capture_iron("guard")
	_press("guard",false)
	await _end(0)
	main.queue_free()
	await _ticks(3)
	if failures.is_empty(): print("IRON SWORD PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _start_without_visual() -> void:
	_check(combat.request_attack(target),"Body attack starts even without valid weapon visual")
	await _phase(combat.State.Attack)
	await _ticks(1)
	_check(not sword.visible and sprite._attacking,"Invalid visual safely hidden")
