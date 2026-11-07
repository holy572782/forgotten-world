extends "res://tests/m10_rebuild_composition.gd"
## Both sides use the same production scene, camera and real renderer.
const EVIDENCE := "res://docs/images/m10_rebuild/relief/"
var revision := "before" if "--before" in OS.get_cmdline_user_args() else "after"

func _run() -> void:
	if "--geometry-only" in OS.get_cmdline_user_args():
		var field: Node3D = load("res://scenes/maps/wind_hills_rebuild/field.tscn").instantiate()
		root.add_child(field)
		_check_terrain(field)
		print(JSON.stringify(result))
		print("Geometry checks: ",checks,"; failures: ",failures)
		field.free()
		quit(0 if failures.is_empty() else 1)
		return
	var layout_text := FileAccess.get_file_as_string("res://resources/maps/wind_hills_rebuild/layout.json")
	if revision=="before" and JSON.parse_string(layout_text).has("shelves"):
		push_error("The before capture requires the original stage 01 map at e11b0c2.")
		quit(1)
		return
	await super._run()

func report_path() -> String:
	return "res://docs/measurements/m10_rebuild_relief_%s.json" % revision

func save_image(label: String) -> void:
	if label == "entrance_play" or (revision == "before" and label != "comparison"):
		return
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	check(shot.save_png(EVIDENCE + revision + "_" + label + ".png") == OK,"save "+label)

func inspect_scene(label: String, scene: Node3D) -> void:
	var field: Node3D = scene.get_node("Field")
	if label == "playground":
		var rig: Node3D = scene.get_node("CameraRig")
		var yaw: float = rig.rotation.y
		Input.action_press("camera_left")
		await ticks(20)
		Input.action_release("camera_left")
		check(wrapf(rig.rotation.y-yaw,-PI,PI)>0.1,"Q rotates opposite E")
		result.views[label] = {"generation_ms":field.generation_ms}
		return
	if label != "comparison": return
	var camera: Camera3D = scene.get_node("ReviewCamera")
	result["lighting"] = str(scene.get_node("Lighting/Sun").global_transform)
	result["colliders"] = field.find_children("*","CollisionShape3D",true,false).size()
	check(result.colliders == 1,"only the existing entrance floor has collision")
	# Exclude screenshot encoding, scene construction and warm-up from frame samples.
	for i in range(30): await RenderingServer.frame_post_draw
	var elapsed_ms: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	for i in range(240):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		elapsed_ms.append((now-previous)/1000.0)
		previous = now
	elapsed_ms.sort()
	result["fixed_view"] = {
		"frames":elapsed_ms.size(), "average_fps":240.0e6/(previous-start),
		"p95_ms":elapsed_ms[ceili(elapsed_ms.size()*0.95)-1],"max_ms":elapsed_ms[-1],
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	}
	if revision == "before": return
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/measurements/m10_rebuild_relief_before.json"))
	var original: Dictionary = baseline.views.comparison
	var current: Dictionary = result.views.comparison
	for key in ["camera_position","rotation_degrees","projection","fov","size"]:
		check(original[key]==current[key],"fixed camera and landmarks match baseline: "+key)
	for marker in original.landmarks:
		var old: Array = original.landmarks[marker]
		var new: Array = current.landmarks[marker]
		var delta_px := Vector2((new[0]-old[0])*root.size.x,(new[1]-old[1])*root.size.y)
		check(delta_px.length()<0.001,"landmark projection matches to 0.001 px: "+str(marker))
	check(absf(original.player_height_px-current.player_height_px)<0.001,"projected player size matches to 0.001 px")
	check(result.lighting==baseline.lighting,"sun transform matches baseline")
	_check_terrain(field)
	var positions := {
		"terraces":[Vector3(-26,48,-24),Vector3(16,18,-105),52.0],
		"valley":[Vector3(79,29,16),Vector3(67,-12,-74),53.0],
		"summit":[Vector3(59,59,-124),Vector3(36,49,-190),46.0]
	}
	for detail in positions:
		var preset: Array = positions[detail]
		camera.position = preset[0]
		camera.look_at(preset[1],Vector3.UP)
		camera.fov = preset[2]
		await ticks(6)
		await save_image(detail)
		result.views[detail] = {"position":str(camera.position),"target":str(preset[1]),"fov":camera.fov}

func _check_terrain(field: Node3D) -> void:
	var scale_m := field.scale.x
	var all_routes := {}
	for route in field.routes:
		var surface: Mesh = field.get_node("RouteProxies/"+str(route.id)).mesh
		var faces := surface.get_faces()
		var bins := {}
		var minimum := INF
		var maximum := -INF
		for i in range(0,faces.size(),3):
			var center := (faces[i]+faces[i+1]+faces[i+2])/3.0
			var gap: float = (center.y-field.surface_height(center.x,center.z))*scale_m
			minimum = minf(minimum,gap)
			maximum = maxf(maximum,gap)
			var bounds := Rect2(Vector2(faces[i].x,faces[i].z),Vector2.ZERO)
			for j in [1,2]: bounds = bounds.expand(Vector2(faces[i+j].x,faces[i+j].z))
			var first := Vector2i((bounds.position/8).floor())
			var last := Vector2i((bounds.end/8).floor())
			for x in range(first.x,last.x+1):
				for z in range(first.y,last.y+1):
					var key := Vector2i(x,z)
					if not bins.has(key): bins[key]=[]
					bins[key].append(i)
		var sections: Array = field.bridge_approaches(route.curve) if route.id=="river" else [route.curve]
		var misses := 0
		var observations := 0
		var steepest := 0.0
		var steepest_at := Vector2.ZERO
		for section in sections:
			for i in range(section.size()-1):
				var a: Vector3 = section[i]
				var b: Vector3 = section[i+1]
				var from := Vector2(a.x,a.z)
				var to := Vector2(b.x,b.z)
				var count := maxi(1,ceili(from.distance_to(to)*scale_m/0.5))
				var last_y: float = field.surface_height(a.x,a.z)
				for j in range(1,count+1):
					var point := from.lerp(to,float(j)/count)
					if not _covered(point,faces,bins): misses += 1
					var y: float = field.surface_height(point.x,point.y)
					var grade := absf(y-last_y)*count/from.distance_to(to)
					if grade>steepest:
						steepest=grade
						steepest_at=point*scale_m
					last_y = y
					observations += 1
		check(minimum>0.020 and maximum<0.034,"road hugs displayed triangles: "+str(route.id))
		check(misses==0,"continuous rendered route center: "+str(route.id))
		if route.id=="main": check(steepest<tan(deg_to_rad(35.0)),"main road has room for the planned ascent")
		all_routes[route.id]={"triangles":faces.size()/3,"min_clearance_m":minimum,"max_clearance_m":maximum,"center_samples":observations,"missing":misses,"sampled_max_degrees":rad_to_deg(atan(steepest)),"steepest_xz_m":str(steepest_at)}
	result["roads"]=all_routes
	var summit: Vector3 = field.vec(field.layout.landmarks.E_summit)
	var cfg: Dictionary = field.layout.summit
	var unsupported := 0
	for x in range(-41,42):
		for z in range(-18,19):
			var h: float = field.surface_height(summit.x+x,summit.z+cfg.plaza_center_z+z)
			if absf(h-summit.y)>0.01: unsupported += 1
	check(unsupported==0,"summit plinth supported across footprint")
	var ends: Array = field.layout.valley.bridge_route_endpoints
	var bridge: Vector3 = field.vec(field.layout.landmarks.D_bridge)
	for i in ends:
		var bank: Vector3 = field.routes[2].points[int(i)]
		check(absf(field.surface_height(bank.x,bank.z)-bridge.y)<0.35,"bridge approach meets deck")
	var min_width := INF
	var max_width := 0.0
	for point in field.river_points:
		var width: float = field.water_width(point.z)*scale_m
		min_width = minf(min_width,width)
		max_width = maxf(max_width,width)
	result["water_ribbon_width_m"]=[min_width,max_width]

func _covered(point: Vector2, faces: PackedVector3Array, bins: Dictionary) -> bool:
	for i: int in bins.get(Vector2i((point/8).floor()),[]):
		var a := Vector2(faces[i].x,faces[i].z)
		var ab := Vector2(faces[i+1].x,faces[i+1].z)-a
		var ac := Vector2(faces[i+2].x,faces[i+2].z)-a
		var area := ab.cross(ac)
		if absf(area)<0.0000001: continue
		var u := (point-a).cross(ac)/area
		var v := ab.cross(point-a)/area
		if u>=-0.001 and v>=-0.001 and u+v<=1.001: return true
	return false
