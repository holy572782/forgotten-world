extends "res://tests/in_place_attack.gd"
## Actual screen projection, input events, physics, animation and damage callbacks.
var b: Node3D
var c: Node3D

func _point(candidate: Node3D, factor := 0.15, degrees := 0.0) -> Vector2:
	var camera: Camera3D = rig.camera
	var from := camera.unproject_position(player.global_position)
	return from + (camera.unproject_position(candidate.global_position)-from).rotated(deg_to_rad(degrees))*factor

func _ground(candidate: Node3D, degrees := 0.0) -> Vector2:
	for factor in [0.15,0.25,1.6,2.0]:
		var point := _point(candidate,factor,degrees)
		if root.get_visible_rect().has_point(point) and combat.pick_target(point) == null: return point
	_check(false,"Fixture provides an empty-ground click")
	return _point(candidate,0.15,degrees)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse_guard(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse_controls() -> void:
	await _setup()
	var point := _ground(target)
	var before := player.global_position
	_mouse_guard(point,true)
	await _ticks(8)
	_check(combat.state == combat.State.Guard and String(sprite.animation).begins_with("guard_"),"Right hold uses existing shield pose")
	_check(player.global_position == before and accepted.is_empty() and hits == 0 and combat.stock.current == 3,"Right hold never approaches, strikes or spends stock")
	_click(point)
	await _ticks(2)
	_check(not combat.queued and accepted.is_empty(),"Left click during Guard cannot defer an extra attack")
	_mouse_guard(Vector2(20,20),false)
	await _ticks(3)
	_check(not combat.is_busy() and not sprite._attacking and accepted.is_empty(),"Release over HUD exits Guard with no delayed attack")
	_key(KEY_D,true)
	await _ticks(4)
	_key(KEY_D,false)
	_check(player.global_position.x > before.x,"Movement resumes after mouse Guard")
	_key(KEY_SPACE,true)
	await _ticks(3)
	_key(KEY_SPACE,false)
	_check(player.global_position.y > before.y+0.05,"Jump resumes after mouse Guard")
	await _setup()
	# A held UI press must not leak through global Input polling, even after moving.
	_mouse_guard(Vector2(20,20),true)
	await _ticks(4)
	var motion := InputEventMouseMotion.new()
	motion.position = _ground(target)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _ticks(4)
	_check(not combat.is_busy() and accepted.is_empty(),"HUD-held right click stays blocked after cursor leaves UI")
	_key(KEY_I,true)
	await _ticks(3)
	_check(combat.state == combat.State.Guard,"Keyboard Guard still works while a UI mouse press is held")
	_key(KEY_I,false)
	await _ticks(3)
	_check(not combat.is_busy(),"Releasing I does not activate the blocked mouse source")
	_mouse_guard(_ground(target),false)
	await _ticks(2)
	# Both valid sources can hold the same Guard independently.
	for mouse_first in [false,true]:
		await _setup()
		point = _ground(target)
		if mouse_first: _mouse_guard(point,true)
		else: _key(KEY_I,true)
		await _ticks(2)
		if mouse_first: _key(KEY_I,true)
		else: _mouse_guard(point,true)
		await _ticks(2)
		if mouse_first: _mouse_guard(point,false)
		else: _key(KEY_I,false)
		await _ticks(3)
		_check(combat.state == combat.State.Guard,"Remaining valid input keeps Guard after the other releases")
		_mouse_guard(point,false)
		_key(KEY_I,false)
		await _ticks(3)
		_check(not combat.is_busy(),"Releasing both Guard sources exits normally")
	for phase in [combat.State.Approach,combat.State.Attack,combat.State.Return]:
		await _setup(3.0)
		await _clicked(target,_ground(target))
		await _phase(phase)
		var paid := accepted.size()
		var delivered := hits
		_mouse_guard(_ground(target),true)
		await _ticks(3)
		_check(combat.state == combat.State.Guard and not combat.queued,"Right hold interrupts existing combat state "+str(phase))
		_check(accepted.size() == paid and hits == delivered and rig.follow_locked,"Guard adds no strike or hit and preserves combat camera lock")
		_mouse_guard(Vector2(20,20),false)
		await _done()
	await _setup(1.2)
	point = _ground(target)
	for repeat in range(20): _click(point)
	await _ticks(2)
	_check(accepted.size() == 1,"Many left clicks in one receiving tick start one strike")
	for repeat in range(20): _click(point)
	await _done()
	_check(accepted.size() == 2 and hits == 2 and combat.stock.current == 1,"Spam keeps one follow-up reservation and one hit/cost per strike")
	await _setup()
	motion.position = Vector2(20,20) # Keyboard attack must not depend on cursor.
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	_key(KEY_L,true)
	_key(KEY_L,false)
	_key(KEY_J,true)
	_key(KEY_J,false)
	await _ticks(2)
	_check(combat.is_busy() and combat.target == target,"L/J attack works with cursor over UI")
	await _done()
	_check(hits == 1,"Keyboard path retains one actual hit")

func _setup(distance := 3.0, yaw := 0.0) -> void:
	await _prepare(distance,yaw)
	combat.settings.directional_click_tolerance_degrees = 20.0
	combat._select_manually(target)
	await _ticks(1)

func _clicked(candidate: Node3D, point: Vector2) -> void:
	_check(combat.pick_target(point) == null,"Click is empty ground, not an accidental direct hit")
	anchor = player.global_position
	_click(point)
	await _ticks(2)
	_check(combat.is_busy() and combat.target == candidate,"Real left click starts the intended target")
	_check(combat.return_anchor == anchor,"Receiving physics tick preserves current moving-player anchor")

func _persistence() -> void:
	var path := "res://.godot/directional_click_settings.tres"
	if "--reload" in OS.get_cmdline_user_args():
		var saved: Resource = load(path)
		_check(saved != null and saved.directional_click_tolerance_degrees == 32.5,"Direction tolerance persists across processes")
		_check(saved.stop_distance == 1.1 and saved.auto_aim_half_angle_degrees == 60,"Existing aiming and travel values persist")
		return
	var saved: Resource = combat.settings.duplicate()
	saved.directional_click_tolerance_degrees = 32.5
	_check(ResourceSaver.save(saved,path) == OK,"Save existing target settings Resource")
	for property in saved.get_property_list():
		if property.name == "directional_click_tolerance_degrees":
			_check((property.usage & PROPERTY_USAGE_EDITOR) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) != 0,"Tolerance editable and stored")

func _run() -> void:
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	if "--reload" in OS.get_cmdline_user_args():
		await _persistence()
	else:
		root.size = Vector2i(1152,720)
		main = preload("res://tests/fixtures/combat_scene.gd").create()
		root.add_child(main)
		player = main.get_node("Player")
		combat = player.combat
		combat.settings = combat.settings.duplicate()
		sprite = player.get_node("AnimatedSprite3D")
		sword = player.get_node("WeaponSwing")
		health = player.get_node("HealthComponent")
		rig = main.get_node("CameraRig")
		target = main.get_node("TrainingEnemy/Targetable")
		b = main.get_node("TrainingEnemySecond/Targetable")
		c = main.get_node("TrainingEnemyThird/Targetable")
		initial_weapon = combat.equipped_weapon.duplicate()
		initial_weapon.motion = Motion.new()
		visual = initial_weapon.attack_visual
		combat.attack_accepted.connect(func(_id: int,_count: int): accepted.append(Engine.get_physics_frames()))
		combat.hit.connect(func(victim: Node): hits += 1; victim_ids.append(victim.get_instance_id()))
		combat.state_changed.connect(func(next: int): events.append(next))
		await _ticks(15)
		var motion_hash := FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres")
		var settings_hash := FileAccess.get_sha256("res://resources/target_dash_settings.tres")
		_check(combat.settings.directional_click_tolerance_degrees == 20.0,"Default half angle is twenty degrees")
		for yaw in [0.0,90.0,180.0,270.0]:
			await _setup(3.0,yaw)
			for angle in [-20.1,-20.0,-19.9,0.0,19.9,20.0,20.1]:
				var point := _ground(target,angle)
				_check(combat.pick_attack_target(point) == (target if absf(angle)<=20.0 else null),"Screen cone under camera yaw "+str(yaw)+" angle "+str(angle))
			for factor in [0.15,1.6]:
				_check(combat.pick_attack_target(_point(target,factor)) == target,"Ground in front of or beyond enemy keeps direction")
			var marker: Vector3 = target.get_node("Marker").position
			target.get_node("Marker").position += Vector3(2,3,0)
			_check(combat.pick_attack_target(_ground(target,19.0)) == target,"Marker rendering offset does not tilt logical aim")
			target.get_node("Marker").position = marker
			await _clicked(target,_ground(target,10.0))
			await _phase(combat.State.Attack)
			await _capture_iron("directional_"+str(int(yaw)))
			await _done()
			_check(hits == 1 and combat.stock.current == 2,"One left click gives one paid hit under each camera yaw")
		await _setup()
		var centre: Vector2 = rig.camera.unproject_position(player.global_position)
		_check(combat.pick_attack_target(centre) == null,"Zero-length direction has no arbitrary target")
		for values in [Vector2(5,4),Vector2(5,6),Vector2(35,30),Vector2(35,36)]:
			combat.settings.directional_click_tolerance_degrees = values.x
			_check(combat.pick_attack_target(_ground(target,values.y)) == (target if values.y<values.x else null),"Inspector tolerance controls cone")
		combat.settings.directional_click_tolerance_degrees = NAN
		_check(combat.pick_attack_target(_ground(target,19)) == target,"Non-finite tolerance uses safe default")
		combat.settings.directional_click_tolerance_degrees = 0.0
		_check(combat.pick_attack_target(_ground(target)) == target and combat.pick_attack_target(_ground(target,1)) == null,"Zero tolerance keeps the exact direction only")
		await _setup()
		b.get_parent().position = origin+Vector3(-2,0,-2)
		await _ticks(3)
		combat._select_manually(b)
		_check(combat.pick_attack_target(_ground(target)) == target and combat.selected_target == b,"Selected target outside cone is never forced into a direction click")
		var explicit: Vector2 = rig.camera.unproject_position(target.global_position+Vector3.UP*0.75)
		_check(combat.pick_target(explicit) == target and combat.pick_attack_target(explicit) == target,"Direct click overrides a different selected enemy")
		anchor = player.global_position
		_click(explicit)
		await _ticks(2)
		await _done()
		_check(hits == 1 and victim_ids == [target.get_instance_id()],"Direct left click retains its actual damage target")
		# Close overlapping targets isolate selection priority from travel/body collisions.
		await _setup(1.2)
		target.get_parent().position = origin+Vector3(0.1,0,-1.2)
		b.get_parent().position = origin+Vector3(-0.1,0,-1.2)
		await _ticks(3)
		combat._select_manually(target)
		var toward_b := _ground(b)
		_check(target.marker.visible and b.marker.visible and target.selected,"Existing gold candidate/selected markers retained")
		_check(combat.pick_attack_target(toward_b) == target,"Selected candidate inside cone wins over a smaller angle")
		combat.selected_target = null
		_check(combat.pick_attack_target(toward_b) == b,"Smallest screen angle wins without selected candidate")
		combat._select_manually(b)
		var direct: Vector2 = rig.camera.unproject_position(target.global_position+Vector3.UP*0.75)
		var directly_hit: Node3D = combat.pick_target(direct)
		_check(directly_hit != null and combat.pick_attack_target(direct) == directly_hit,"Frontmost direct body click has highest priority")
		b.get_parent().position = origin+Vector3(0,0,-1.2)
		target.get_parent().position = origin+Vector3(0,0,-1.35)
		await _ticks(3)
		combat.selected_target = null
		_check(combat.pick_attack_target(_ground(b)) == b,"Equal angle uses existing nearer-distance priority")
		target.get_parent().position = b.get_parent().position
		c.get_parent().position = b.get_parent().position
		await _ticks(3)
		combat.selected_target = null
		var stable: Node3D = combat.valid_candidates()[0]
		for repeat in range(8):
			for candidate in [target,b,c]: candidate.remove_from_group("combat_targets"); candidate.add_to_group("combat_targets")
			_check(combat.pick_attack_target(_ground(target)) == stable,"Exact ties use stable NodePath order")
		# Actual WASD and arrow events: selection follows the screen, not movement facing.
		for code in [KEY_W,KEY_A,KEY_UP,KEY_RIGHT]:
			await _setup()
			_key(code,true)
			await _ticks(3)
			await _clicked(target,_ground(target))
			_key(code,false)
			await _done()
			_check(hits == 1,"Moving-player click retains one actual hit")
		for orbit in ["camera_left","camera_right"]:
			await _setup(1.3)
			_press(orbit,true)
			await _ticks(10)
			await _clicked(target,_ground(target))
			await _done()
			_press(orbit,false)
			_check(not combat.State.Approach in events and not combat.State.Return in events,"Near directional attack still skips both travels during Q/E")
		# Directional attack moved to left. UI and an empty cone cause no attack/cost.
		await _setup()
		_click(_ground(target))
		await _ticks(2)
		_check(combat.is_busy() and combat.target == target,"Left ground click uses directional attack")
		await _done()
		await _setup()
		_click(Vector2(20,20))
		await _ticks(2)
		_check(not combat.is_busy(),"GUI consumes left attack click")
		_click(_ground(target,100))
		await _ticks(2)
		_check(not combat.is_busy() and combat.stock.current == 3,"Empty cone has no swing or stock cost")
		for block_height in [0.25,2.0]:
			await _setup()
			var wall := _block(origin+Vector3(0,block_height/2.0,-1.5),Vector3(1.5,block_height,0.15))
			await _ticks(3)
			_check(combat.pick_attack_target(_ground(target)) == null and not target.marker.visible,"Existing low/high wall safety excludes direction candidate")
			wall.free()
		for offset in [Vector3(0,0,-5.2),Vector3(0,0.2,-3)]:
			await _setup()
			target.get_parent().position = origin+offset
			await _ticks(3)
			_check(combat.pick_attack_target(_ground(target)) == null,"Range and height safety exclude candidate")
		await _setup()
		target.health.damage(100)
		await _ticks(2)
		_check(combat.pick_attack_target(_ground(target)) == null,"Dead targets cannot be selected directionally")
		await _setup()
		player.reset_motion(origin+Vector3.UP*0.5)
		await _ticks(2)
		_check(combat.pick_attack_target(_ground(target)) == null,"Airborne player retains existing attack restriction")
		# Left ground clicks replace the one existing reservation, not the active swing.
		await _setup(1.2)
		b.get_parent().position = origin+Vector3(2.7,0,-1.2)
		c.get_parent().position = origin+Vector3(1.6,0,-1.9)
		await _ticks(3)
		await _clicked(target,_ground(target))
		_click(_ground(b))
		_check(combat.queued and combat.queued_attack_target == b and combat.target == target,"Directional follow-up uses the existing queue")
		for tick in range(150):
			if combat.combo_hits == 2: break
			await _ticks(1)
		_click(_ground(c))
		_check(combat.queued and combat.queued_attack_target == c,"Next direction can select the third enemy")
		await _done()
		_check(accepted.size() == 3 and victim_ids == [target.get_instance_id(),b.get_instance_id(),c.get_instance_id()],"Three real strikes follow A/B/C with no extra hit")
		await _mouse_controls()
		await _persistence()
		_check(FileAccess.get_sha256("res://resources/weapons/default_attack_motion.tres") == motion_hash and FileAccess.get_sha256("res://resources/target_dash_settings.tres") == settings_hash,"Authored and user-edited Resources unchanged")
		main.queue_free()
		await _ticks(3)
	if failures.is_empty(): print("DIRECTIONAL CLICK PASS: ",assertions," assertions; fps cap=",Engine.max_fps)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
