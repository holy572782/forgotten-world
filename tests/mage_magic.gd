extends "res://tests/enemy_tactics.gd"
const Types = preload("res://scripts/combat/damage_types.gd")
var block_events := 0
var flight_end := Vector3.ZERO
var visuals: Array[Dictionary] = []

func _blocked(_source: Node) -> void: block_events += 1

func _image() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _changed(a: Image, b: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(maxi(0,rect.position.y),mini(a.get_height(),rect.end.y)):
		for x in range(maxi(0,rect.position.x),mini(a.get_width(),rect.end.x)):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)>0.1: count+=1
	return count

func _reload_magic() -> void:
	var saved: Resource = load("res://.godot/mage_saved.tres")
	_check(saved.attack.damage_kind == Types.Kind.MAGIC and saved.attack.projectile_speed == 5.0 and is_equal_approx(saved.attack.projectile_range,13.2), "Magic damage, speed and range persist")
	_check(is_equal_approx(saved.attack.magic_visual.fireball_diameter,2.1) and is_equal_approx(saved.attack.projectile_radius,0.2) and is_equal_approx(saved.ranged_stop_margin,0.3), "Separate visual/collision size and pursuit margin persist")
	_check(saved.attack.magic_visual.circle_effect != null and saved.attack.magic_visual.circle_effect.get_subresources().size() == 1 and saved.attack.magic_visual.hit_effect != null, "Floor circle and fire-hit effect dependencies persist")
	for failure in failures: push_error(failure)
	print("MAGE MAGIC RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _cliff_trial() -> void:
	await _fresh(1,Vector3(7,0,0))
	ai.global_position=Vector3(0,0,13.1)
	ai.home=ai.global_position
	player.global_position=Vector3(0,0,20)
	ai.set_physics_process(true)
	await _ticks(50)
	print("MAGE CLIFF position=",ai.global_position," support=",ai.walker._support(ai.global_position)," move=",ai.walker.blocked_reason)
	_check(ai.global_position.z<13.7 and absf(ai.global_position.y)<0.003 and ai.walker._support(ai.global_position),"Mage stops on actual supported floor, allowing bounded native contact recovery")

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_magic()
		return
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size = Vector2i(1152,720)
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.combat
	sprite = player.get_node("AnimatedSprite3D")
	health = player.get_node("HealthComponent")
	combat.guard_succeeded.connect(_blocked)
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(5)
	if "--cliff-only" in OS.get_cmdline_user_args():
		await _cliff_trial()
		main.free()
		print("MAGE CLIFF ","PASS" if failures.is_empty() else "FAIL")
		quit(0 if failures.is_empty() else 1)
		return
	await _fresh(1,Vector3(5,0,0))
	_check(ai.settings.attack_start_distance==6.0 and ai.active_attack.damage_kind==Types.Kind.MAGIC, "Mage starts at the original 6m with explicit magic damage")
	_check(ai.active_attack.projectile_speed==5.0 and is_equal_approx(ai.active_attack.projectile_range,13.2) and ai.active_attack.projectile_lifetime>13.2/5.0, "5m/s and 13.2m are compatible with the 6s safety lifetime")
	var circle: Node3D = ai.get_node("CastingCircle")
	_check(not circle.is_presenting() and circle.mesh.cast_shadow==0 and not ai.telegraph.visible, "Circle has no shadow/collision and is separate from the disabled range indicator")
	cue_count=0
	ai.get_node("AttackWarning").warning_sound_presented.connect(_cue)
	await _windup()
	await _ticks(4)
	_check(circle.is_presenting() and absf(circle.global_position.y-ai.active_attack.magic_visual.ground_offset)<0.001 and circle.global_basis.y.dot(Vector3.UP)>0.999, "Real WINDUP displays a horizontal circle just above terrain")
	_check(circle.emitter.effect != null and circle.emitter.is_playing() and not circle.mesh.visible, "Mage actually plays the native Effekseer circle without doubling the old shader")
	ai.set_physics_process(false)
	var rotation_before := circle.rotation.y
	await _seconds(0.15)
	_check(circle.rotation.y>rotation_before and cue_count==1, "Circle rotates without replaying the casting sound or advancing AI")
	# A/B rendered pixels at four camera views, rather than shader existence alone.
	var camera: Camera3D = main.get_node("CameraRig").camera
	for yaw in [0.0,90.0,180.0,270.0]:
		main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
		main.get_node("CameraRig").snap_to_target()
		await _ticks(2)
		circle.set_process(false)
		var visible_image := await _image()
		circle.emitter.hide()
		circle.mesh.hide()
		await _ticks(3) # Native viewport texture needs a render before the A/B sample.
		var hidden_image := await _image()
		var point := camera.unproject_position(circle.global_position)
		var changes := _changed(visible_image,hidden_image,Rect2i(Vector2i(point)-Vector2i(110,75),Vector2i(220,150)))
		_check(changes>30,"Circle actually renders at camera yaw "+str(yaw))
		visuals.append({"yaw":yaw,"circle_pixels":changes})
		if yaw==0.0: visible_image.save_png("res://.godot/mage_circle.png")
		circle.emitter.show()
		circle.set_process(true)
	ai.set_physics_process(true)
	await _state(ai.State.ATTACK)
	var bolt: CharacterBody3D=ai.shots[0]
	var fire: Node3D=bolt.get_node("FireballVisual")
	_check(is_equal_approx(fire.core.mesh.size.x,1.8) and is_equal_approx(bolt.get_node("CollisionShape3D").shape.radius,0.2) and fire.trail.size()==5, "1.8m visual / 0.2m hit radius / short trail are independent")
	var direction: Vector3=bolt.direction
	var position_before: Vector3=bolt.global_position
	var tick_before:=Engine.get_physics_frames()
	_press("move_down",true)
	await _ticks(12)
	_press("move_down",false)
	var seconds:=float(Engine.get_physics_frames()-tick_before)/60.0
	_check(is_instance_valid(bolt) and bolt.direction==direction and absf(bolt.global_position.distance_to(position_before)/seconds-5.0)<0.01, "Real release travels at 5m/s without homing after player movement")
	_check(not circle.is_presenting() and not circle.emitter.is_playing(), "Circle finishes its short release fade and stops native playback")
	if is_instance_valid(bolt):
		var travelling := await _image()
		travelling.save_png("res://.godot/mage_flying.png")
	ai.set_physics_process(false)
	ai.clear_shots()
	# Inspect rendered fire palettes and animation at a stationary visual-only observation point.
	main.get_node("CameraRig").rotation.y=0
	main.get_node("CameraRig").snap_to_target()
	bolt=_shot(origin+Vector3(2,1.3,0),Vector3.UP,0.0)
	await _ticks(3)
	fire=bolt.get_node("FireballVisual")
	var first:=await _image()
	await _seconds(0.13)
	var second:=await _image()
	var pixel:=camera.unproject_position(bolt.global_position)
	var rect:=Rect2i(Vector2i(pixel)-Vector2i(70,70),Vector2i(140,140))
	_check(_changed(first,second,rect)>10,"Fire shape/pixels actually animate")
	var yellows:=0
	var oranges:=0
	for y in range(maxi(0,rect.position.y),mini(second.get_height(),rect.end.y)):
		for x in range(maxi(0,rect.position.x),mini(second.get_width(),rect.end.x)):
			var color:=second.get_pixel(x,y)
			if color.r>0.85 and color.g>0.7 and color.b<0.7: yellows+=1
			if color.r>0.7 and color.g>0.2 and color.g<0.7 and color.b<0.3: oranges+=1
	_check(yellows>10 and oranges>10,"Rendered flame contains a yellow core and orange/red exterior")
	second.save_png("res://.godot/mage_fireball.png")
	for yaw in [90.0,180.0,270.0]:
		main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
		main.get_node("CameraRig").snap_to_target()
		await _ticks(2)
		_check(fire.core.global_basis.z.dot(camera.global_basis.z)>0.999,"Fire billboard follows the current Q/E camera")
	main.get_node("CameraRig").rotation.y=0.0
	main.get_node("CameraRig").snap_to_target()
	ai.clear_shots()
	await _ticks(2)
	# Exact travelled-distance cleanup; upward travel avoids actors and walls.
	bolt=_shot(origin+Vector3(2,0.9,0),Vector3.UP,5.0)
	var launch: Vector3=bolt.global_position
	bolt.tree_exiting.connect(func(): flight_end=bolt.global_position)
	tick_before=Engine.get_physics_frames()
	for tick in range(200):
		await _ticks(1)
		if not is_instance_valid(bolt): break
	_check(not is_instance_valid(bolt) and absf(launch.distance_to(flight_end)-13.2)<0.001,"Projectile expires at 13.2m from launch, without overshooting")
	var lifetime:=float(Engine.get_physics_frames()-tick_before)/60.0
	_check(absf(lifetime-2.64)<0.07,"Distance expiry occurs near 2.64 seconds, before safety lifetime")
	for physical in [false,true]:
		await _fresh(1,Vector3(4,0,0))
		_press("guard",true)
		await _phase(combat.State.Guard)
		combat.selected_target=null
		combat.target=null
		player.facing_world=Vector3.RIGHT
		block_events=0
		bolt=_shot(origin+Vector3(1,0.9,0),Vector3.LEFT,300.0)
		bolt.settings.damage_kind=Types.Kind.PHYSICAL if physical else Types.Kind.MAGIC
		await _ticks(3)
		_check(health.current_hp==(95 if physical else 90) and block_events==(1 if physical else 0),"Physical arrow blocks; identical magic projectile penetrates without a guard success event")
		_check(combat.state==combat.State.Guard,"Magic damage does not cancel guard stance")
		_check(health.incoming_damage_kind==Types.Kind.PHYSICAL,"Scoped damage kind is restored for legacy callers")
		var hp:=health.current_hp
		health.damage(10,ai)
		_check(health.current_hp==hp-5,"Legacy two-argument damage remains physical even from a mage source")
		_press("guard",false)
	await _fresh(1,Vector3(4,0,0))
	_press("guard",true)
	await _phase(combat.State.Guard)
	combat.selected_target=null
	combat.target=null
	player.facing_world=Vector3.RIGHT
	block_events=0
	health.damage(10,ai,Types.Kind.MAGIC)
	_check(health.current_hp==90 and block_events==0,"Magic melee also bypasses guard; delivery is not the damage kind")
	var original_defense: Resource=combat.defense
	combat.defense=original_defense.duplicate()
	combat.defense.guard_magic_enabled=true
	health.damage(10,ai,Types.Kind.MAGIC)
	_check(health.current_hp==85 and block_events==1,"A future opt-in magic shield can reuse the existing directional guard")
	combat.defense=original_defense
	_press("guard",false)
	# Ordinary soldier mitigation and original combo/return are also covered in regressions.
	await _fresh_sword(2.0)
	_press("guard",true)
	await _phase(combat.State.Guard)
	player.facing_world=Vector3.RIGHT
	block_events=0
	await _windup()
	await _finish_strike()
	_check(health.current_hp==95 and block_events==1,"Actual soldier sword still deals one guarded physical half hit")
	_press("guard",false)
	# Interrupted / dead casters hide immediately, no leaked floor visual.
	await _fresh(1,Vector3(5,0,0))
	await _windup()
	circle=ai.get_node("CastingCircle")
	ai.set_physics_process(false) # Isolate cancellation from a subsequent new encounter.
	ai._set_state(ai.State.RETURN)
	await _ticks(2)
	_check(not circle.is_presenting() and not circle.emitter.is_playing(),"Interrupted warning hides and stops the circle")
	ai._start_windup()
	_check(circle.is_presenting(),"A new warning restores the circle")
	var native_effect: EffekseerEffect = ai.active_attack.magic_visual.circle_effect
	ai.active_attack.magic_visual = ai.active_attack.magic_visual.duplicate()
	ai.active_attack.magic_visual.circle_effect = null
	await _ticks(2)
	_check(circle.mesh.visible and not circle.emitter.is_playing(), "A null native effect preserves the previous procedural circle")
	ai.active_attack.magic_visual.circle_effect = native_effect
	await _ticks(2)
	_check(circle.emitter.is_playing() and not circle.mesh.visible, "Restoring the native effect does not double the floor visual")
	ai.health.damage(100,player)
	_check(not circle.is_presenting() and not circle.emitter.is_playing() and ai.state==ai.State.DEAD,"HP0 clears the circle without waiting for death flight")
	# Mage moves only to recover range; no strafing / wandering inside range.
	await _fresh(1,Vector3(7,0,0))
	var initial: Vector3=ai.global_position
	await _windup()
	_check(initial.distance_to(ai.global_position)>0.5 and ai.global_position.distance_to(player.global_position)<=6.01,"Mage safely walks in from outside 6m")
	var anchor: Vector3=ai.global_position
	await _state(ai.State.RECOVERY)
	await _ticks(25)
	_check(ai.global_position.distance_to(anchor)<0.001 and ai.velocity.is_zero_approx(),"WINDUP / firing / in-range recovery remain stationary")
	ai.clear_shots()
	player.reset_motion(origin-Vector3(1,0,0))
	await _ticks(12)
	_check(ai.global_position.distance_to(anchor)>0.1,"Leaving range restarts pursuit even during recovery")
	await _fresh(1,Vector3(5.8,0,0))
	ai.cooldown=100
	ai._set_state(ai.State.CHASE)
	ai.set_physics_process(true)
	anchor=ai.global_position
	for offset in [0.08,-0.08,0.12,-0.12,0.05]:
		player.reset_motion(origin+Vector3(offset,0,0))
		await _ticks(3)
	_check(ai.global_position.distance_to(anchor)<0.001,"Range hysteresis prevents small boundary stop/start jitter")
	player.reset_motion(origin-Vector3(0.3,0,0))
	await _ticks(3)
	_check(ai.global_position.distance_to(anchor)>0.02,"A target just outside 6m is never stranded in a non-attacking dead band")
	await _fresh(1,Vector3(7,0,0))
	var wall:=_block(origin+Vector3(6.75,1,0),Vector3(0.2,2,2))
	await _ticks(3)
	anchor=ai.global_position
	ai.set_physics_process(true)
	await _ticks(20)
	_check(ai.global_position.distance_to(anchor)<0.001 and ai.attack_count==0,"Mage does not chase through a wall")
	wall.free()
	await _cliff_trial()
	await _fresh(1,Vector3(5,0,0))
	var saved: Resource=ai.settings.duplicate(true)
	saved.attack=saved.attack.duplicate(true)
	saved.attack.magic_visual=saved.attack.magic_visual.duplicate()
	saved.attack.magic_visual.fireball_diameter=2.1
	saved.ranged_stop_margin=0.3
	_check(ResourceSaver.save(saved,"res://.godot/mage_saved.tres")==OK,"Mage tuning saves as a Resource")
	FileAccess.open("res://.godot/mage_visual_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(visuals,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("MAGE MAGIC ","PASS" if failures.is_empty() else "FAIL",": ",assertions," assertions; fps cap=",Engine.max_fps)
	quit(0 if failures.is_empty() else 1)
