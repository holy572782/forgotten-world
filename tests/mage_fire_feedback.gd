extends "res://tests/mage_magic.gd"
## Real native pixels and actual swept projectile delivery, including held Guard.

func _clear_impacts() -> void:
	for effect in get_nodes_in_group("fire_hit_presentations"): effect.free()
	await _ticks(2)

func _body_overlap(a: Image, b: Image, actor: CharacterBody3D, camera: Camera3D) -> Vector2i:
	var visual: AnimatedSprite3D = actor.get_node("AnimatedSprite3D")
	var atlas: AtlasTexture = visual.sprite_frames.get_frame_texture(visual.animation,visual.frame)
	var pixels := atlas.get_image()
	var overlap := 0
	var verified := 0
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	for y in range(4,38): # Exclude the foot-contact edge, retain body/hat silhouette.
		for x in range(48):
			# Test opaque interior texels; fractional screen sampling at a sprite
			# silhouette edge can land on the surrounding floor after projection.
			if x < 1 or x > 46 or pixels.get_pixel(x,y).a < 0.9 or pixels.get_pixel(x-1,y).a < 0.9 or pixels.get_pixel(x+1,y).a < 0.9 or pixels.get_pixel(x,y-1).a < 0.9 or pixels.get_pixel(x,y+1).a < 0.9: continue
			var world := actor.global_position + right*(float(x)-23.5)*visual.pixel_size + up*(46.5-float(y))*visual.pixel_size
			var at := Vector2i(camera.unproject_position(world))
			if at.x < 0 or at.y < 0 or at.x >= a.get_width() or at.y >= a.get_height(): continue
			var ca := a.get_pixelv(at)
			var cb := b.get_pixelv(at)
			var original := pixels.get_pixel(x,y)
			# Only count baseline pixels that really contain this sprite color,
			# rather than occluding terrain or a neighboring screen texel.
			if absf(cb.r-original.r)+absf(cb.g-original.g)+absf(cb.b-original.b)>0.04: continue
			verified += 1
			if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)>0.06: overlap += 1
	return Vector2i(overlap,verified)

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	await _ticks(4)
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	for pair in [["assets/audio/sfx/mz_magic1.ogg","RPGツクールMZのaudio/se/Magic1.ogg"],["assets/audio/sfx/mz_fire2.ogg","RPGツクールMZのaudio/se/Fire2.ogg"],["assets/effects/mage_fire_hit/fire_one1.efkefc","RPGツクールMZeffects/FireOne1.efkefc"],["assets/effects/mage_circle_fire/Texture/HexCircle.png","RPGツクールMZeffects/Texture/HexCircle.png"]]:
		_check(FileAccess.get_sha256("res://"+pair[0])==FileAccess.get_sha256("res://"+pair[1]),"Selected source copied without alteration: "+pair[0])
	await _fresh(1,Vector3(5,0,0))
	var warning: Node = ai.get_node("AttackWarning")
	cue_count=0
	warning.warning_sound_presented.connect(_cue)
	await _windup()
	await _ticks(15)
	ai.set_physics_process(false)
	ai.settings.attack_warning_flash_enabled=false
	warning._process(0.0)
	var circle: Node3D=ai.get_node("CastingCircle")
	_check(cue_count==1 and warning.warning_audio.stream.resource_path.ends_with("mz_magic1.ogg") and is_equal_approx(warning.warning_audio.pitch_scale,0.9),"Casting plays Magic1 exactly once at 90 percent pitch")
	_check(circle.emitter.rotation.is_zero_approx() and is_equal_approx(circle.global_position.y,0.01),"Floor-authored effect needs no emitter tilt and stays just above terrain")
	circle.set_process(false)
	circle.emitter.paused=true
	var camera: Camera3D=main.get_node("CameraRig").camera
	var metrics: Array[Dictionary]=[]
	for yaw in [0.0,90.0,180.0,270.0]:
		main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
		main.get_node("CameraRig").snap_to_target()
		circle.emitter.show()
		await _ticks(24) # Let the existing wall-fade/camera safety transition settle.
		var shown := await _image()
		circle.emitter.hide()
		await _ticks(3)
		var hidden := await _image()
		var point := camera.unproject_position(circle.global_position)
		var difference := _changed(shown,hidden,Rect2i(Vector2i(point)-Vector2i(120,90),Vector2i(240,180)))
		var mask := _body_overlap(shown,hidden,ai,camera)
		_check(difference>40,"Floor circle visibly renders at camera yaw "+str(yaw))
		_check(mask.x==0 and mask.y>20,"Circle does not paint over verified mage pixels: yaw %s overlap %d / %d" %[yaw,mask.x,mask.y])
		metrics.append({"yaw":yaw,"circle_pixels":difference,"body_overlap":mask.x,"body_samples":mask.y})
		if yaw==0.0: shown.save_png("res://.godot/mage_fire_floor.png")
	circle.clear()
	main.get_node("CameraRig").rotation.y=0.0
	main.get_node("CameraRig").snap_to_target()
	for guarding in [false,true]:
		await _clear_impacts()
		await _fresh(1,Vector3(4,0,0))
		if guarding:
			_press("guard",true)
			await _phase(combat.State.Guard)
			player.facing_world=Vector3.RIGHT
		var before:=health.current_hp
		var bolt:=_shot(origin+Vector3(0.7,0.9,0),Vector3.LEFT,30.0)
		for tick in range(12):
			await _ticks(1)
			if not is_instance_valid(bolt): break
		_check(health.current_hp==before-10,"Real fire hit delivers one full magic hit; Guard="+str(guarding))
		var hits:=get_nodes_in_group("fire_hit_presentations")
		_check(hits.size()==1,"One fire impact after the projectile is consumed")
		var hurt: AnimatedSprite3D=player.get_node("DamageVisual")
		_check(hurt.visible and not sprite.visible,"Player hurt animation appears even with held Guard="+str(guarding))
		if guarding: _check(combat.state==combat.State.Guard,"Visual hurt preserves logical Guard and its input")
		if hits.size()==1:
			var effect: Node3D=hits[0]
			_check(effect.emitter.effect.resource_path.ends_with("fire_one1.efkefc") and effect.emitter.is_playing(),"Exact FireOne1 plays natively")
			_check(effect.audio.playing and effect.audio.stream.resource_path.ends_with("mz_fire2.ogg") and is_equal_approx(effect.audio.pitch_scale,1.0),"Fire2 plays once at its configured normal pitch")
			await _seconds(0.12)
			var shown:=await _image()
			shown.save_png("res://.godot/mage_fire_hit_guard_%s.png" % str(guarding))
			effect.emitter.hide()
			await _ticks(2)
			var hidden:=await _image()
			var point:=camera.unproject_position(effect.global_position)
			_check(_changed(shown,hidden,Rect2i(Vector2i(point)-Vector2i(160,180),Vector2i(320,360)))>20,"FireOne1 visibly renders at the impact")
			effect.emitter.show()
		await _seconds(0.35)
		_check(not hurt.visible and sprite.visible,"Hurt completes and restores the original action/guard image")
		var flame := await _image()
		flame.save_png("res://.godot/mage_fire_flame_guard_%s.png" % str(guarding))
		if guarding:
			_check(String(sprite.animation).begins_with("guard_"),"Held guard image returns after hurt")
			_press("guard",false)
	ai.set_physics_process(false)
	await _seconds(6.2)
	_check(get_nodes_in_group("fire_hit_presentations").is_empty(),"Hit visuals and audio finish and release without a surviving bolt")
	await _clear_impacts()
	await _fresh(1,Vector3(4,0,0))
	var wall:=_block(origin+Vector3(0.6,0.9,0),Vector3(0.1,1.8,2))
	_shot(origin+Vector3(1,0.9,0),Vector3.LEFT,30.0)
	await _ticks(10)
	_check(get_nodes_in_group("fire_hit_presentations").is_empty() and health.current_hp==100,"Wall consumption does not play player hit visuals or audio")
	wall.free()
	FileAccess.open("res://.godot/mage_fire_floor_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	main.queue_free()
	await _ticks(4)
	_check(get_nodes_in_group("fire_hit_presentations").is_empty(),"Scene teardown releases independent impact objects")
	for failure in failures: push_error(failure)
	print("MAGE FIRE FEEDBACK %s: %d assertions; fps cap=%d" %["PASS" if failures.is_empty() else "FAIL",assertions,Engine.max_fps])
	quit(0 if failures.is_empty() else 1)
