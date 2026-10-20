extends "res://tests/m06_target_dash.gd"
var other: Node3D
var rig: Node3D
var origin := Vector3(-6,0,0)

func _polar(distance: float, degrees: float) -> Vector3:
	return origin + Vector3(sin(deg_to_rad(degrees)),0,-cos(deg_to_rad(degrees))) * distance

func _layout(a_distance: float, a_angle: float, b_distance: float, b_angle: float) -> void:
	enemy.global_position = _polar(a_distance,a_angle)
	other.get_parent().global_position = _polar(b_distance,b_angle)
	combat.selected_target = null
	combat._manual_selection = false
	combat._aim_candidate = null
	combat._aim_elapsed = 0
	player.facing_world = Vector3.FORWARD
	await _ticks(2)
	_check(combat.valid_candidates().size() == 2, "Both arranged targets pass real safety checks")

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/m07_auto_aim_" + label + ".png")

func _run() -> void:
	root.size = Vector2i(1152,720)
	Engine.max_fps = 30 if "--fps30" in OS.get_cmdline_user_args() else 60
	main = preload("res://tests/fixtures/combat_scene.gd").create()
	main.get_node("TrainingEnemyThird").free()
	root.add_child(main)
	player = main.get_node("Player")
	combat = player.get_node("TargetDash")
	combat.settings = combat.settings.duplicate()
	sprite = player.get_node("AnimatedSprite3D")
	enemy = main.get_node("TrainingEnemy")
	target = enemy.get_node("Targetable")
	other = main.get_node("TrainingEnemySecond/Targetable")
	rig = main.get_node("CameraRig")
	await _settle(origin)
	# Far target has the smaller angle: distance must win inside the forward cone.
	await _layout(2.0,-40,4.0,10)
	_check(combat.selected_target == target, "Near forward target wins over better-aligned far target")
	combat.settings.auto_aim_half_angle_degrees = 30
	combat.selected_target = null
	await _ticks(2)
	_check(combat.selected_target == other, "Forward cone width is configurable")
	combat.settings.auto_aim_half_angle_degrees = 60
	combat.selected_target = null
	await _ticks(2)
	_check(target.selected and not other.selected and other.marker.visible, "Gold filled/hollow selection")
	_check(not combat._ring.visible and not combat._range_guides.is_visible_in_tree(), "Default range and guides hidden")
	await _capture("default")
	var candidates: Array[Node3D] = combat.valid_candidates()
	combat.show_debug_attack_range = true
	await _ticks(2)
	_check(combat._ring.visible and combat._range_guides.is_visible_in_tree(), "Inspector flag shows both debug meshes")
	_check(combat.valid_candidates() == candidates, "Debug flag changes no candidate")
	await _capture("debug")
	combat.show_debug_attack_range = false
	await _ticks(2)
	_check(not combat._range_guides.is_visible_in_tree(), "Toggle back hides both")
	await _layout(2,170,4,0)
	_check(combat.selected_target == other, "Far forward beats near behind")
	await _layout(2,-59,4,59)
	_check(combat.selected_target == target, "Near left cone edge wins")
	await _layout(4,-59,2,59)
	_check(combat.selected_target == other, "Near right cone edge wins")
	await _layout(2,160,4,-100)
	_check(combat.selected_target == other, "No forward candidates falls back to smaller angle")
	await _layout(2.0,-35,2.02,5)
	_check(combat.selected_target == other, "Almost equal initial distances use angle")
	await _layout(2.5,-30,2.5,30)
	_check(combat.selected_target == target, "Equal distance and angle use stable NodePath")
	for i in range(24):
		enemy.global_position = _polar(2.5 + (0.04 if i % 2 else -0.04),-30)
		await _ticks(1)
		_check(combat.selected_target == target, "Tiny distance changes do not flicker")
	other.get_parent().global_position = _polar(1.9,30)
	await _ticks(2)
	_check(combat.selected_target == target, "Distance improvement waits for stability")
	await _ticks(12)
	_check(combat.selected_target == other, "Large stable distance improvement switches")
	# Cone boundary uses an angular exit band only for the current target.
	await _layout(2.5,60,2.5,-59)
	combat.selected_target = target
	for i in range(24):
		player.facing_world = Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(1 if i % 2 else -1))
		await _ticks(1)
		_check(combat.selected_target == target, "Cone edge jitter retains current target")
	player.facing_world = Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(25))
	await _ticks(15)
	_check(combat.selected_target == other, "Clear turn crosses exit band and switches naturally")
	await _layout(2,-40,4,10)
	combat.cycle_target()
	var manual: Node3D = combat.selected_target
	_check(manual == other, "L selects farther target")
	await _ticks(20)
	_check(combat.selected_target == manual and combat.stock.current == 3, "Manual choice overrides distance without stock cost")
	player.facing_world = Vector3.RIGHT
	await _ticks(15)
	_check(not combat._manual_selection, "Clear turn releases manual choice")
	for debug_enabled in [false,true]:
		combat.show_debug_attack_range = debug_enabled
		enemy.global_position = _polar(4.9,-40)
		await _ticks(2)
		_check(combat.can_select(target), "Inside range accepted with either display mode")
		enemy.global_position = _polar(5.1,-40)
		await _ticks(2)
		_check(not combat.can_select(target), "Outside range rejected with either display mode")
		enemy.global_position = _polar(3,-40) + Vector3.UP*0.25
		await _ticks(2)
		_check(not combat.can_select(target), "Height mismatch rejected with either display mode")
		enemy.global_position = _polar(3,-40)
		var wall := _block(origin.lerp(enemy.global_position,0.5)+Vector3.UP*0.8,Vector3(0.5,1.6,0.5))
		await _ticks(2)
		_check(not combat.can_select(target), "Wall rejected with either display mode")
		wall.free()
	combat.show_debug_attack_range = false
	# Real mouse direct selection overrides automatic proximity and survives combat.
	await _layout(2,-40,4,10)
	_click(rig.camera.unproject_position(other.global_position+Vector3.UP*0.75),MOUSE_BUTTON_LEFT)
	await _ticks(2)
	_check(combat.is_busy() and combat.target == other, "Mouse chooses farther enemy directly")
	var selected: Node3D = combat.selected_target
	player.facing_world = Vector3.LEFT
	combat._refresh_selection(1.0)
	_check(combat.selected_target == selected and not combat.queued, "Auto selection cannot overwrite combat or create queue")
	await _wait_idle()
	await _ticks(2)
	_check(combat.selected_target == other and combat._manual_selection, "Mouse choice held after return")
	if failures.is_empty(): print("PASS M07 auto aim: forward distance, behind, cone, fallback, ties, stability, manual, debug range")
	for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
