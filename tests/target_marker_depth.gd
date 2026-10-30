extends "res://tests/target_marker_shadow.gd"
## Render the actual characters, unlike the isolated marker equality fixture.
func _gold_pixels(img: Image) -> Array[Vector2i]:
	var points: Array[Vector2i]=[]
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c:=img.get_pixel(x,y)
			if c.r>0.95 and c.g>0.5 and c.g<0.85 and c.b<0.3: points.append(Vector2i(x,y))
	return points

func _visible_pixels(rendered: Image, reference: Image, pixels: Array[Vector2i]) -> int:
	var visible:=0
	for pixel in pixels:
		if rendered.get_pixelv(pixel)==reference.get_pixelv(pixel): visible+=1
	return visible

func _legacy_material() -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(1,0.72,0.12)
	material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return material

func _run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(640,480)
	var world:=Node3D.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0.1,0.2,0.2)
	world.add_child(environment)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6
	world.add_child(camera)
	camera.make_current()
	var hero:=preload("res://scenes/player/player.tscn").instantiate()
	world.add_child(hero)
	hero.set_physics_process(false)
	for profile in ["melee","ranged"]:
		var actor:=preload("res://scenes/enemies/practice_enemy.tscn").instantiate()
		actor.settings=load("res://resources/enemies/"+profile+"_practice.tres")
		actor.player=hero
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.debug_label.hide()
		actor.get_node("Targetable/HealthLabel").hide()
		var target: Node3D=actor.targetable
		var body: AnimatedSprite3D=actor.get_node("AnimatedSprite3D")
		var marker: MeshInstance3D=target.get_node("Marker/Mesh")
		for yaw in [0.0,90.0,180.0,270.0]:
			var toward:=Vector3(0,0,1).rotated(Vector3.UP,deg_to_rad(yaw))
			camera.position=toward*8+Vector3.UP*8
			camera.look_at(Vector3.UP)
			for filled in [true,false]:
				target.set_available(true,filled)
				hero.hide()
				body.hide()
				var reference:=await _image()
				var pixels:=_gold_pixels(reference)
				_check(pixels.size()>50,"Visible reference mark")
				var current_material:=marker.material_override
				marker.material_override=_legacy_material()
				var legacy:=await _image()
				_check(_visible_pixels(legacy,reference,pixels)==pixels.size() and _gold_pixels(legacy).size()==pixels.size(),"Unobstructed static marker shape/color remains unchanged")
				marker.material_override=current_material
				body.show()
				hero.show()
				for distance in [-1.8,-1.0,0.8,1.6]:
					hero.position=toward*distance
					var rendered:=await _image()
					var visible:=_visible_pixels(rendered,reference,pixels)
					print("MARKER DEPTH ",profile," yaw=",yaw," filled=",filled," hero distance=",distance," visible=",visible,"/",pixels.size())
					_check(visible==pixels.size(),"Characters do not cover mark: "+profile+str(yaw)+str(filled)+str(distance))
					if yaw==0.0 and filled and distance==1.6: rendered.save_png("res://.godot/marker_depth_"+profile+".png")
				actor.health.damage(1,hero)
				_check(_visible_pixels(await _image(),reference,pixels)==pixels.size(),"Real white hit flash does not cover marker")
				actor._set_state(actor.State.ATTACK)
				_check(_visible_pixels(await _image(),reference,pixels)==pixels.size(),"Attack sprite/weapon/effect does not cover marker")
				actor._set_state(actor.State.IDLE)
				# An opaque wall must still occlude all or part of the marker.
				var wall:=MeshInstance3D.new()
				var box:=BoxMesh.new()
				box.size=Vector3(2,4,0.2)
				wall.mesh=box
				wall.rotation.y=deg_to_rad(yaw)
				world.add_child(wall)
				var center: Vector3=target.marker.global_position
				wall.position=center+(camera.position-center)*0.25
				_check(_visible_pixels(await _image(),reference,pixels)==0,"Full wall still hides marker")
				box.size.x=0.25
				wall.position+=camera.global_basis.x*0.13
				var partial:=_visible_pixels(await _image(),reference,pixels)
				_check(partial>0 and partial<pixels.size(),"Partial wall masks only the covered marker pixels")
				box.size.x=2
				wall.position=center-(camera.position-center)*0.25
				_check(_visible_pixels(await _image(),reference,pixels)==pixels.size(),"Wall behind marker does not hide it")
				wall.free()
		actor.free()
	hero.free()
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("TARGET MARKER DEPTH ","PASS" if failures.is_empty() else "FAIL",": ",assertions)
	quit(0 if failures.is_empty() else 1)
