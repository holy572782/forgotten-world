extends "res://tests/m06_target_dash.gd"
## Keep logical selection separate from the forward-facing marker presentation.
var checks := 0
var reference_images: Dictionary={}
func _check(ok: bool, message: String) -> void:
	checks += 1
	super._check(ok,message)

func _marker_image(t: Node3D) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var camera: Camera3D=main.get_node("CameraRig").camera
	var center:=Vector2i(camera.unproject_position(t.marker.global_position))
	return root.get_texture().get_image().get_region(Rect2i(center-Vector2i(35,35),Vector2i(70,70)))

func _run() -> void:
	root.size=Vector2i(1152,720)
	Engine.max_fps=60
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.free()
	await _settle(Vector3(-6,0,0))
	for profile in ["static","melee","ranged"]:
		var actor: Node3D=load("res://scenes/enemies/training_enemy.tscn" if profile=="static" else "res://scenes/enemies/practice_enemy.tscn").instantiate()
		if profile!="static":
			actor.settings=load("res://resources/enemies/"+profile+"_practice.tres")
			actor.player=player
		actor.position=Vector3(-6,0,-2)
		main.add_child(actor)
		actor.set_physics_process(false)
		var t: Node3D=actor.get_node("Targetable")
		var mesh: MeshInstance3D=t.get_node("Marker/Mesh")
		# Isolate the mark for exact pixel comparisons. Do not replace its material.
		for child in actor.get_children():
			if child is VisualInstance3D: child.hide()
		t.get_node("HealthLabel").hide()
		_check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"No mark shadow: "+profile)
		_check(t.marker.position==Vector3(0,2,0) and mesh.position==Vector3.ZERO,"Static foot-relative placement: "+profile)
		var material: ShaderMaterial=mesh.material_override
		_check(material.shader==preload("res://assets/shaders/target_marker.gdshader") and material.get_shader_parameter("marker_color")==Color(1,0.72,0.12,1) and material.render_priority==10,"Common color/alpha and late character-safe marker pass: "+profile)
		for yaw in [0.0,90.0,180.0,270.0]:
			main.get_node("CameraRig").rotation.y=deg_to_rad(yaw)
			main.get_node("CameraRig").snap_to_target()
			for direction in [Vector3.FORWARD,Vector3.BACK]:
				player.facing_world=direction
				combat.selected_target=null
				combat._manual_selection=false
				await _ticks(15)
				_check(combat.selected_target==t and t.selected,"Single rear target remains logically selectable: "+profile)
				var is_filled: bool=mesh.mesh==t._filled_mesh
				_check(is_filled==(direction==Vector3.FORWARD),"Front filled / rear hollow, independent of selection fallback: "+profile)
				_check(t.marker.visible and t.marker.collision_layer==8,"Visible clickable marker: "+profile)
				var image:=await _marker_image(t)
				var key:=str(yaw)+str(direction)
				if profile=="static": reference_images[key]=image.get_data()
				else: _check(image.get_data()==reference_images[key],"Exact same marker pixels at camera yaw "+str(yaw)+": "+profile)
				if yaw==0.0: image.save_png("res://.godot/marker_"+profile+("_filled.png" if is_filled else "_hollow.png"))
		# Manual selection still means the same thing even behind the player.
		combat._select_manually(t)
		await _ticks(2)
		_check(combat.selected_target==t and t.selected and mesh.mesh==t._hollow_mesh,"Manual rear selection keeps logical target and hollow presentation: "+profile)
		_check(combat.can_select(t),"Rear mark drawing does not alter attack eligibility: "+profile)
		player.set_physics_process(false)
		var anchor:=actor.position
		for displacement in [Vector3(0.2,0.25,0),Vector3(-0.2,0.5,0),Vector3(0,1.0,0),Vector3(0,0.8,-0.3),Vector3.ZERO]:
			actor.position=anchor+displacement
			t.set_available(true,true)
			await process_frame
			_check(t.marker.global_position.is_equal_approx(actor.global_position+Vector3.UP*2),"Mark follows slope/stair/jump/dash translation without offsets: "+profile)
		actor.position=anchor
		player.set_physics_process(true)
		actor.get_node("HealthComponent").damage(1000,player)
		await _ticks(3)
		_check(not is_instance_valid(t) or (not t.marker.is_visible_in_tree() and t.marker.collision_layer==0),"Defeat removes visible/clickable mark: "+profile)
		actor.free()
	main.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("TARGET MARKER UNIFIED ","PASS" if failures.is_empty() else "FAIL",": ",checks)
	quit(0 if failures.is_empty() else 1)
