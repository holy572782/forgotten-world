extends "res://tests/enemy_edge_attack.gd"
var fade_rows: Array[Dictionary]=[]
func _color_difference(a: Color,b: Color) -> float:
	return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
func _picture() -> Image:
	await _ticks(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(800,600)
	main=load("res://scenes/main.tscn").instantiate()
	main.get_node("PracticeSelector").initial_mode=0
	root.add_child(main)
	player=main.get_node("Player"); combat=player.combat; sprite=player.get_node("AnimatedSprite3D"); health=player.get_node("HealthComponent")
	main.get_node("HUD").hide()
	var rig: Node3D=main.get_node("CameraRig")
	rig.set_physics_process(false)
	rig.set_process(false)
	var camera: Camera3D=rig.camera
	camera.top_level=true
	camera.size=7.0
	var arena: Node3D=main.get_node("TestArena")
	var ramp: MeshInstance3D=arena.get_node("Terrain/Ramp/Mesh")
	var fader=load("res://scripts/camera/occlusion_fader.gd").new()
	fader._begin(ramp)
	_check(ramp.has_node("OcclusionShadow"),"Faded terrain retains its independent shadow caster")
	_check(arena.get_node("Terrain/Ramp").collision_layer==1,"Terrain alpha never changes collision")
	for material in fader.entries[ramp.get_instance_id()].materials: material.albedo_color.a=0.3
	for kind in [0,1]:
		for z in [0.5,-0.1,-2.0,-4.0]:
			var at: Vector3=arena.to_global(Vector3(-6,0,z))
			await _edge_actor(kind,at,Vector3(12,0,12))
			player.hide()
			ai.debug_label.hide(); ai.targetable.get_node("HealthLabel").hide(); ai.targetable.set_available(false)
			ai.get_node("AnimatedSprite3D").stop()
			ai.get_node("AnimatedSprite3D/Shadow").hide()
			ai.get_node("AnimatedSprite3D").set_process(false)
			for yaw in [0.0,180.0]:
				var dir:=Vector3(0,0,1).rotated(Vector3.UP,deg_to_rad(yaw))
				camera.global_position=ai.global_position+Vector3.UP*7+arena.global_basis*dir*9
				camera.look_at(ai.global_position+Vector3.UP*0.8)
				ramp.hide()
				ai.hide()
				var empty:=await _picture()
				ai.show()
				var reference:=await _picture()
				ramp.show()
				var actual:=await _picture()
				var pixels:=0; var changed:=0
				for y in range(actual.get_height()):
					for x in range(actual.get_width()):
						if _color_difference(reference.get_pixel(x,y),empty.get_pixel(x,y))<0.05: continue
						pixels+=1
						if _color_difference(reference.get_pixel(x,y),actual.get_pixel(x,y))>0.03: changed+=1
				var row: Dictionary={"kind":kind,"z":z,"yaw":yaw,"pixels":pixels,"overlaid":changed,"alpha":ai.get_node("AnimatedSprite3D").modulate.a}
				fade_rows.append(row)
				print("FADE PROBE ",JSON.stringify(row))
				if not "--probe" in OS.get_cmdline_user_args():
					_check(pixels>500 and changed==0,"Faded ramp never overlays the visible actor: "+str(row))
					_check(ai.get_node("AnimatedSprite3D").modulate.a==1.0,"Actor opacity is independent")
				if z==0.5:
					actual.save_png("res://.godot/fade_%s_%s.png" % [kind,yaw])
	# A real terrain wall remains an occluder; depth writing is not an on-top mode.
	var wall:=MeshInstance3D.new()
	var box:=BoxMesh.new(); box.size=Vector3(4,4,0.3); wall.mesh=box
	var solid:=StandardMaterial3D.new(); solid.albedo_color=Color(0.4,0.5,0.6); wall.material_override=solid
	main.add_child(wall)
	wall.global_basis=arena.global_basis
	wall.global_position=ai.global_position+arena.global_basis*Vector3(0,2,-1.0)
	ai.show()
	var obscured:=await _picture()
	ai.hide()
	var absent:=await _picture()
	_check(obscured.get_data()==absent.get_data(),"Opaque wall still hides a character")
	fader._begin(wall)
	for material in fader.entries[wall.get_instance_id()].materials: material.albedo_color.a=0.3
	ai.show()
	var through_faded_wall:=await _picture()
	wall.hide()
	var no_wall:=await _picture()
	_check(through_faded_wall.get_data()!=obscured.get_data() and through_faded_wall.get_data()!=no_wall.get_data(),"Actually foreground faded terrain still blends; character is not always on top")
	fader._restore(wall.get_instance_id())
	wall.free()
	fader.restore_all()
	_check(not ramp.has_node("OcclusionShadow") and ramp.get_active_material(0).albedo_color.a==1.0,"Fade and shadow bindings restore exactly")
	var args:=OS.get_cmdline_user_args()
	var label: String=args[args.find("--label")+1] if args.has("--label") else "sample"
	FileAccess.open("res://.godot/enemy_fade_"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(fade_rows,"  "))
	print("FADED TERRAIN RESULT ","PROBE" if "--probe" in args else ("PASS" if failures.is_empty() else "FAIL")," ",assertions)
	await _finish_edge()
