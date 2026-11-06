extends "res://tests/m10_wind_hills.gd"
## Same production scene and inputs before/after B01; no alternate lighting or camera.
const VIEWS := {"start":Vector3(0,0,12),"gate":Vector3.ZERO,"beyond_gate":Vector3(3,0.22,-5),"bend":Vector3(14,1,-22),"plaza_c":Vector3(0,2,-45)}
var label := "before"
var perf := false
var snapshot: Dictionary = {}
var views: Dictionary = {}
var build_ms := 0

func _save_view(name: String) -> void:
	views[name] = {"player":str(player.global_position),"yaw":rig.rotation.y,"camera_transform":str(rig.camera.global_transform),"pitch":rig.settings.pitch_angle,"distance":rig.settings.camera_distance}
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/images/m10_b01/"+label+"_"+name+".png")
	# Screenshot compression is CPU work outside render performance sampling.
	previous_usec = 0

func _digest(data: PackedByteArray) -> String:
	return data.hex_encode().sha256_text()

func _geometry_snapshot() -> Dictionary:
	var terrain_faces := PackedVector3Array()
	var collisions := PackedVector3Array()
	var outside := PackedByteArray()
	var slabs := PackedByteArray()
	var slab_geometry_valid := true
	for body in field.get_node("Terrain").get_children():
		var shape: ConcavePolygonShape3D = body.get_child(1).shape
		collisions.append_array(shape.get_faces())
		var mesh: Mesh = body.get_child(0).mesh
		# Order-independent triangle signature permits surface regrouping, never geometry changes.
		var tris: Array[String] = []
		var vertices := mesh.get_faces()
		for i in range(0,vertices.size(),3):
			tris.append(str(vertices[i])+str(vertices[i+1])+str(vertices[i+2]))
		tris.sort()
		var expected: Array[String] = []
		var original := shape.get_faces()
		for i in range(0,original.size(),3): expected.append(str(original[i])+str(original[i+1])+str(original[i+2]))
		expected.sort()
		_check(tris==expected,"display triangles exactly equal original collision "+str(body.name))
		terrain_faces.append_array(shape.get_faces())
		if not body.name in ["Chunk_100_200","Chunk_100_220","Chunk_100_240","Chunk_100_260","Chunk_100_280","Chunk_120_200","Chunk_120_220","Chunk_120_240","Chunk_120_260","Chunk_120_280","Chunk_140_200","Chunk_140_220","Chunk_140_240","Chunk_140_260","Chunk_140_280"]:
			outside.append_array(var_to_bytes([str(body.name),tris]))
		_check(tris.size()==800,"terrain triangle count "+str(body.name))
	for tile in field.get_node("RoadDetails").get_children():
		var visual: MeshInstance3D = tile.get_child(0)
		var bounds := visual.mesh.get_aabb()
		if visual.mesh is ArrayMesh:
			var box := BoxMesh.new()
			box.size = Vector3(0.80,0.025,1.12)
			var old_points: Array[String] = []
			var new_points: Array[String] = []
			for p in box.get_faces(): old_points.append(str(p))
			for p in visual.mesh.get_faces(): new_points.append(str(p))
			old_points.sort()
			new_points.sort()
			# ArrayMesh expands zero-height surface bounds by 10 micrometres;
			# the rendering custom AABB preserves the original BoxMesh bound exactly.
			bounds = visual.mesh.custom_aabb
			slab_geometry_valid = slab_geometry_valid and old_points==new_points and bounds==box.get_aabb() and tile.get_child_count()==1
			var arrays: Array = visual.mesh.surface_get_arrays(0)
			var tex_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var area := Rect2(tex_uv[0],Vector2.ZERO)
			for uv in tex_uv: area = area.expand(uv)
			slab_geometry_valid = slab_geometry_valid and area.get_area()<0.03 and area.position.x>0 and area.end.x<1
		slabs.append_array(var_to_bytes([str(tile.transform),bounds]))
	_check(slab_geometry_valid,"slab faces, render bounds and single-stone UVs preserved")
	return {"collision_hash":_digest(collisions.to_byte_array()),"terrain_geometry_hash":_digest(terrain_faces.to_byte_array()),"outside_mesh_hash":_digest(outside),"slab_transform_aabb_hash":_digest(slabs),"terrain_bodies":field.get_node("Terrain").get_child_count(),"slab_count":field.get_node("RoadDetails").get_child_count()}

func _material_checks() -> void:
	var materials: RefCounted = field.entrance_materials
	_check(materials!=null,"entrance watercolor material helper present")
	_check(field.grass.detail_enabled==false and field.grass.albedo_texture==null,"original shared terrain material unchanged")
	var painted := 0
	var surfaces := 0
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for body in field.get_node("Terrain").get_children():
		var mesh: Mesh = body.get_child(0).mesh
		for i in range(mesh.get_surface_count()):
			var mat: StandardMaterial3D = mesh.surface_get_material(i)
			if not mat.detail_enabled: continue
			surfaces += 1
			_check(mat==materials.grass and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and mat.next_pass==null,"opaque supported terrain material")
			var arrays := mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var valid := true
			for j in range(vertices.size()):
				var p := vertices[j]
				valid = valid and uv2[j].is_equal_approx(Vector2(p.x,p.z)) and uv[j].x>=0.009 and uv[j].x<=0.991
				if uv[j].x>0.01001:
					valid = valid and p.x>=-24 and p.x<=24 and p.z>=-54 and p.z<=24
					minimum = minimum.min(Vector2(p.x,p.z))
					maximum = maximum.max(Vector2(p.x,p.z))
			_check(valid,"world UV continuity and authorized footprint "+str(body.name))
			painted += vertices.size()/3
	_check(painted==materials.terrain_triangles and surfaces>0,"painted triangle accounting")
	results.materials = {"painted_triangles":painted,"painted_surfaces":surfaces,"painted_slabs":materials.tiles,"grass_repeat_m":field.entrance_ground.grass_repeat_meters,"grass_strength":field.entrance_ground.grass_strength,"paving_strength":field.entrance_ground.paving_strength,"nonzero_mask_vertex_min_xz":str(minimum),"nonzero_mask_vertex_max_xz":str(maximum)}
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/measurements/m10_b01_before.json"))
	for key in ["collision_hash","terrain_geometry_hash","outside_mesh_hash","slab_transform_aabb_hash"]:
		_check(results.geometry[key]==baseline.geometry[key],"baseline unchanged "+key)
	for key in VIEWS:
		var old: Dictionary = baseline.views[key]
		var current: Dictionary = views[key]
		_check(current.pitch==old.pitch and current.distance==old.distance and absf(current.yaw-old.yaw)<0.00001 and _numbers_close(current.player,old.player,0.0001) and _numbers_close(current.camera_transform,old.camera_transform,0.0001),"same before/after player and camera within 0.1mm "+key)

func _numbers_close(a: String, b: String, tolerance: float) -> bool:
	var expression := RegEx.new()
	expression.compile("-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
	var aa := expression.search_all(a)
	var bb := expression.search_all(b)
	if aa.size()!=bb.size(): return false
	for i in range(aa.size()):
		if absf(aa[i].get_string().to_float()-bb[i].get_string().to_float())>tolerance: return false
	return true

func _fade_checks() -> void:
	await _place(VIEWS.start)
	rig.rotation.y = 0
	rig.snap_to_target()
	await _ticks(30)
	rig.set_physics_process(false)
	rig.fader.restore_all()
	var mesh: MeshInstance3D = field.get_node("Terrain/Chunk_120_260").get_child(0)
	var originals: Array[Material] = []
	for i in range(mesh.mesh.get_surface_count()): originals.append(mesh.get_active_material(i))
	var fader = preload("res://scripts/camera/occlusion_fader.gd").new()
	fader._begin(mesh)
	var entry: Dictionary = fader.entries[mesh.get_instance_id()]
	entry.hold = 4.0
	for i in range(30): fader.update(scene.get_world_3d().direct_space_state,Vector3(0,4,12),player.global_position,rig.settings,[],1.0/60.0)
	var valid := true
	for i in range(mesh.mesh.get_surface_count()):
		var mat: StandardMaterial3D = mesh.get_active_material(i)
		valid = valid and is_equal_approx(mat.albedo_color.a,0.3) and mat.detail_albedo==originals[i].detail_albedo
	_check(valid,"all surfaces fade to 0.3 with textures retained")
	_check(is_instance_valid(entry.shadow_proxy) and entry.shadow_proxy.mesh==mesh.mesh and entry.shadow_proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"all surfaces retain opaque shadow proxy")
	await _save_view("fade_030")
	fader.restore_all()
	for i in range(originals.size()): _check(mesh.get_active_material(i)==originals[i],"faded surface restored exactly")
	await _ticks(30)
	await _save_view("fade_restored")
	rig.set_physics_process(true)

func _variants() -> void:
	for meters in [3.0,4.0,6.0]:
		field.entrance_materials.set_grass_scale(meters)
		for key in ["start","bend"]:
			await _place(VIEWS[key])
			rig.rotation.y = 0
			rig.snap_to_target()
			await _ticks(30)
			await _save_view(key+"_grass_"+str(int(meters))+"m")
	field.entrance_materials.set_grass_scale(field.entrance_ground.grass_repeat_meters)

func _detail_views() -> void:
	for item in [["east_edge",Vector2(20,5)],["west_edge",Vector2(-20,5)],["chunk_seam",Vector2(10,-20)]]:
		var xz: Vector2 = item[1]
		await _place(Vector3(xz.x,field.height_at(xz.x,xz.y),xz.y))
		rig.rotation.y = 0
		rig.snap_to_target()
		await _ticks(30)
		await _save_view(item[0])

func _rotations() -> void:
	for p in [Vector3(0,0,0),Vector3(14,1,-22)]:
		await _place(p)
		phase = "orbit_"+str(p)
		measuring = perf
		Input.action_press("camera_right")
		var start_time := Engine.get_physics_frames()
		while Engine.get_physics_frames()-start_time<216:
			await _ticks(1)
			_check(not rig.safety_failed,"camera stays visible")
		Input.action_release("camera_right")
		await _ticks(20)
		measuring = false
		_stats(phase)
		_check(rig.fader.unsupported.is_empty(),"all faded materials supported")
		rig.rotation.y = 0
		rig.snap_to_target()

func _walk_entrance(name: String) -> void:
	await _place(VIEWS.start)
	rig.rotation.y = 0
	rig.snap_to_target()
	var path: Array = [VIEWS.start,VIEWS.gate,Vector3(14,1,-22),VIEWS.plaza_c]
	measuring = perf
	await _walk(path,name+"_out")
	path.reverse()
	await _walk(path,name+"_back")
	measuring = false
	_stats(name)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var stations_only := "--stations-only" in args
	label = "after" if "--after" in args else "before"
	capture = "--capture" in args
	perf = "--performance" in args
	fast = "--fast" in args
	fps = 30 if "--30" in args else 60
	Engine.max_fps = 0 if fast else fps
	root.size = Vector2i(1152,720)
	var started := Time.get_ticks_msec()
	scene = load("res://scenes/maps/wind_hills/wind_hills_playground.tscn").instantiate()
	if label=="before":
		# Reproducible stage-A look after the feature exists; never edit the saved Resource.
		var map_node: Node3D = scene.get_node("WindHills")
		if "entrance_ground" in map_node:
			map_node.entrance_ground = map_node.entrance_ground.duplicate()
			map_node.entrance_ground.enabled = false
	root.add_child(scene)
	build_ms = Time.get_ticks_msec()-started
	player = scene.get_node("Player")
	field = scene.get_node("WindHills")
	rig = scene.get_node("CameraRig")
	results.environment = {"godot":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":"1152x720","fps_cap":0 if fast else fps,"physics_hz":Engine.physics_ticks_per_second,"enemies":0,"stage":label,"build_ms":build_ms}
	results.environment["stations_only"] = stations_only
	print("B01 ",label," BUILD ",build_ms)
	# Initial route is measured before teleporting/capturing other locations.
	await _ticks(5)
	if "--cover" in args:
		await _place(VIEWS.start)
		rig.rotation.y = 0
		rig.snap_to_target()
		await _ticks(120)
		await _save_view("final_entrance")
		var cover := FileAccess.open("res://docs/measurements/m10_b01_cover.json",FileAccess.WRITE)
		cover.store_string(JSON.stringify({"view":views.final_entrance,"environment":results.environment},"\t"))
		quit()
		return
	if perf and not stations_only:
		await _walk_entrance("cold")
		if not "--30" in args:
			await _walk_entrance("warm_1")
			await _walk_entrance("warm_2")
		await _rotations()
	for key in VIEWS:
		await _place(VIEWS[key])
		rig.rotation.y = 0
		rig.snap_to_target()
		await _ticks(60)
		await _save_view(key)
		if perf and not "--30" in args:
			phase = key
			previous_usec = 0
			measuring = true
			await _ticks(1800)
			measuring = false
			_stats(key)
	if not perf:
		if not "--views-only" in args: await _walk_entrance("functional")
		await _rotations()
	var jump_points: Dictionary = VIEWS.duplicate()
	jump_points["grass"] = Vector3(6,field.height_at(6,10),10)
	for key in ["gate","bend","grass"]:
		await _place(jump_points[key])
		Input.action_press("jump")
		await _ticks(1)
		Input.action_release("jump")
		var peak := player.position.y
		var base: float = jump_points[key].y
		for i in range(70):
			await _ticks(1)
			peak = maxf(peak,player.position.y)
		_check(peak-base>1.0 and peak-base<1.4 and player.is_on_floor(),"jump and landing "+key)
		if key=="grass":
			var start := player.position
			_steer(Vector3.RIGHT)
			await _ticks(30)
			_release()
			await _ticks(20)
			_check(player.position.distance_to(start)>1 and player.is_on_floor() and player.velocity.length()<0.01,"grass move and stop after landing")
			start = player.position
			_steer(Vector3.LEFT)
			await _ticks(12)
			_release()
			await _ticks(20)
			_check(player.position.distance_to(start)>0.1 and player.is_on_floor(),"grass movement restarts")
	results.geometry = _geometry_snapshot()
	if label=="after":
		_material_checks()
		await _fade_checks()
		if "--variants" in args: await _variants()
		if "--details" in args: await _detail_views()
	results.views = views
	results.long_frames = long_frames
	results.checks = checks
	results.failures = failures
	results.airborne_ticks = airborne_ticks
	var suffix := "_30" if "--30" in args else ""
	if fast: suffix = "_fast"
	if stations_only: suffix = "_stations"
	var file := FileAccess.open("res://docs/measurements/m10_b01_"+label+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("B01 ",label," ",checks," checks; failures ",failures.size())
	_release()
	quit(0 if failures.is_empty() else 1)
