@tool
extends Node3D
## Shared approved geometry. Only the exploration scene needs static physics.
@export_file("*.json") var layout_path := "res://resources/maps/wind_hills_rebuild/layout.json"
@export var exploration_physics := false
var layout: Dictionary
var routes: Array = []
var river_points: Array[Vector3] = []
var generation_ms := 0.0
var terrain_material: StandardMaterial3D
var stone: StandardMaterial3D
var path_material: StandardMaterial3D
var samples: Dictionary = {}
const CurveIndex = preload("res://scripts/maps/wind_hills_rebuild/curve_index.gd")
var roads := CurveIndex.new()
var channel := CurveIndex.new()

func _ready() -> void:
	if has_node("Terrain"): return
	var started := Time.get_ticks_usec()
	layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	scale = Vector3.ONE * float(layout.world_scale)
	for route in layout.routes:
		var points: Array[Vector3] = []
		for p in route.points: points.append(vec(p))
		routes.append({"id": route.id, "width": float(route.width), "points": points, "curve": smooth_points(points,route.id!="left")})
	for p in layout.river: river_points.append(vec(p))
	river_points = smooth_points(river_points)
	for route in routes:
		if route.id == "river":
			for approach in bridge_approaches(route.curve):
				roads.add_curve(approach,route.width,22)
		else:
			roads.add_curve(route.curve,route.width,22)
	channel.add_curve(river_points,layout.valley.water_width,maxf(layout.valley.west_reach,layout.valley.east_reach)+12.0)
	terrain_material = material(Color.WHITE, true)
	stone = material(Color("cfc8b6"))
	path_material = material(Color("d9cba8"))
	_grade_road_faces()
	_build_terrain()
	_build_paths()
	_build_landmarks()
	if exploration_physics:
		for visual: MeshInstance3D in get_node("ArchitectureProxies").find_children("*","MeshInstance3D",true,false):
			_solid_visual(visual)
	# Summit masonry owns its simplified colliders; the plaza rests on the terrain.
	_build_summit(get_node("ArchitectureProxies"))
	_build_background_proxies()
	var markers := group("Landmarks")
	for key in layout.landmarks:
		var marker := Marker3D.new()
		marker.name = key
		marker.position = vec(layout.landmarks[key])
		markers.add_child(marker)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = vec(layout.spawn)
	add_child(spawn)
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("WindHills rebuild: %.1f ms; exploration physics = %s" % [generation_ms, exploration_physics])

func vec(p: Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])

func smooth_points(points: Array[Vector3], grade_by_distance := false) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(points.size()-1):
		var a := points[maxi(0,i-1)]
		var b := points[i]
		var c := points[i+1]
		var d := points[mini(points.size()-1,i+2)]
		for j in range(4):
			var t := j/4.0
			var p := b.cubic_interpolate(c,a,d,t)
			var rise_t := t
			if grade_by_distance:
				rise_t = clampf(Vector2(p.x-b.x,p.z-b.z).length()/Vector2(c.x-b.x,c.z-b.z).length(),0,1)
			p.y = lerpf(b.y,c.y,rise_t)
			result.append(p)
	result.append(points[-1])
	return result

func material(color: Color, vertex := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = vertex
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

func group(label: String) -> Node3D:
	var n := Node3D.new()
	n.name = label
	add_child(n)
	return n

func bridge_approaches(curve: Array) -> Array:
	var ends: Array = layout.valley.bridge_route_endpoints
	return [curve.slice(0,int(ends[0])*4+1),curve.slice(int(ends[1])*4)]

func central_shelves(x: float, z: float, axis: float, underlying: float) -> float:
	var depth := -z
	var lateral := x-axis
	var width := lerpf(83,60,clampf(depth/245.0,0,1))
	var footprint := (1.0-smoothstep(0.72,1.13,absf(lateral)/width))*smoothstep(-8,22,depth)*(1.0-smoothstep(226,251,depth))
	if footprint <= 0: return underlying
	var top := 0.55*sin(x*0.085+z*0.031)+0.32*cos(z*0.13-x*0.04)
	for shelf in layout.shelves:
		var advance: float = depth-shelf[0]
		if advance < -40: continue
		if advance > 40:
			top += float(shelf[1])
			continue
		# Change the face direction and expose short spurs as each rim crosses the ridge.
		var phase: float = shelf[5]
		var edge: float = lateral*shelf[4]+shelf[3]*sin(lateral*0.048+phase)
		edge += 2.6*sin(lateral*0.145-phase)+1.1*cos(lateral*0.29+phase)
		var run: float = shelf[2]*(1.0+0.28*sin(lateral*0.085+phase))
		# One talus fan spreads part of each bed into a shallow grass slope.
		# Its position changes from ledge to ledge, leaving separate rock noses.
		var fan := (lateral-38*sin(phase*2.2))/18.0
		run *= 1.0+2.6*exp(-fan*fan)
		top += float(shelf[1])*smoothstep(-run*0.5,run*0.5,advance-edge)
	return lerpf(underlying,top,footprint)

func water_width(z: float) -> float:
	var bend := 1.0+0.14*sin((z+65)*0.066)+0.10*sin((z+65)*0.109)
	return layout.valley.water_width*bend*(1.0-0.40*smoothstep(110,270,-z))

func valley_height(z: float, original: float, river: Dictionary) -> float:
	var west: bool = river.offset_x < 0
	var reach: float = layout.valley.west_reach if west else layout.valley.east_reach
	reach += 7*sin(z*0.041) + 3*cos(z*0.073)
	var d: float = river.distance
	if d >= reach: return original
	var half_width := water_width(river.center_z)*0.5
	var bank := -1.8 + 2.65*smoothstep(half_width-1.6,half_width+0.8,d)
	bank += (2.6 if west else 3.8)*smoothstep(half_width+2,half_width+10,d)
	bank += (3.8 if west else 6.0)*smoothstep(half_width+13,half_width+20,d)
	# The low water meadow eases into a higher, asymmetrical outer valley wall.
	return lerpf(river.height+bank,original,smoothstep(half_width+6,reach,d))

func height_at(x: float, z: float) -> float:
	var valley := -36.0 + sin(x*0.035+z*0.015)*3.0
	var crest := clampf(-z/245.0,0,1)*60.0-20.0
	var axis := 10.0 + clampf(-z/245.0,0,1)*32.0 + sin(z*0.023)*9.0
	var ridge := (1.0-smoothstep(66,153,absf(x-axis)))*(1.0-smoothstep(266,335,-z))*(1.0-smoothstep(26,78,z))
	var h := lerpf(valley,crest,ridge)
	var left_base := 1.0-smoothstep(0.3,1.3,Vector2((x+116)/62,(z+120)/73).length())
	h = maxf(h,lerpf(valley,8,left_base))
	# The upstream meander cuts a high catchment before entering the east valley.
	var catchment := smoothstep(146,252,-z)*smoothstep(72,150,x)
	var upstream := 11.0+5*cos(x*0.048+z*0.03)+4*sin(z*0.057)
	h = maxf(h,lerpf(valley,upstream,catchment))
	for t in layout.terraces:
		var dx: float = (x-t[0])/t[2]
		var dz: float = (z-t[1])/t[3]
		if absf(dx)>1.35 or absf(dz)>1.35: continue
		var angle := atan2(dz,dx)
		var edge := 1.0 + sin(angle*3.0+t[0])*0.08 + sin(angle*7.0+t[1])*0.04
		var radius := Vector2(dx,dz).length()/edge
		var weight := 1.0-smoothstep(0.70,1.18,radius)
		var top: float = t[4] + sin(x*0.065+z*0.031)*0.7 + sin(z*0.09)*0.4
		h = lerpf(h,maxf(h,top),weight)
	h = central_shelves(x,z,axis,h)
	var lookout := vec(layout.road_lookout)
	var lookout_radius := Vector2((x-lookout.x)/12,(z-lookout.z)/8).length()
	h = lerpf(h,lookout.y,1.0-smoothstep(0.62,1.3,lookout_radius))
	var summit := vec(layout.landmarks.E_summit)
	var plaza: Array = layout.summit.plaza
	var outside_plaza := Vector2(maxf(0,absf(x-summit.x)-plaza[0]*0.5),maxf(0,absf(z-summit.z-layout.summit.plaza_center_z)-plaza[1]*0.5))
	var river := channel.sample(x,z)
	h = valley_height(z,h,river)
	var road := roads.sample(x,z)
	if road.distance < 22:
		var shoulder: float = maxf(0,road.distance-road.width*0.5)
		# Reach plaza level just before the oblique lip. A sharp cross-slope here
		# exceeded the floor angle even when the road's longitudinal grade was safe.
		var grade_y := minf(summit.y,road.height+2.2*smoothstep(42,57,road.height))
		var graded := lerpf(h,minf(h,grade_y+0.6+shoulder*0.44),1.0-smoothstep(5,19,road.distance))
		graded = lerpf(graded,grade_y,1.0-smoothstep(1,8,shoulder))
		# Stop grading in the streambed beneath the bridge.
		h = lerpf(h,graded,smoothstep(water_width(river.center_z)*0.5+0.4,9.5,river.distance))
	# Support every corner of the plinth after the valley and road have been shaped.
	var apron_distance := outside_plaza.length()
	var plaza_blend := 1.0-smoothstep(3,12,apron_distance)
	# Let the last approach rise at its designed grade up to the front lip.
	if z > summit.z+layout.summit.plaza_center_z+plaza[1]*0.5:
		plaza_blend *= smoothstep(3.5,13,road.distance)
	h = lerpf(h,summit.y,plaza_blend)
	var overlook := vec(layout.landmarks.C_overlook)
	var overlook_distance := Vector2(x-overlook.x,z-overlook.z).length()
	h = lerpf(h,overlook.y,1.0-smoothstep(3.5,12.0,overlook_distance))
	# Preserve the level starting meadow around the gate.
	if x >= -30 and x <= 0 and z >= -10 and z <= 22: h = 0.0
	return h

func vertex(x: int, z: int) -> Vector3:
	var key := Vector2i(x,z)
	if not samples.has(key): samples[key] = Vector3(x,height_at(x,z),z)
	return samples[key]

func _grade_road_faces() -> void:
	# A tight inside bend can sample two different branches of the elevation
	# profile on a single grid face. Constrain the actual 2-D floor gradient.
	var step := int(layout.terrain.step)
	var cells := {}
	for route in routes:
		var sections: Array = bridge_approaches(route.curve) if route.id=="river" else [route.curve]
		for section in sections:
			for i in range(section.size()-1):
				var a: Vector3 = section[i]
				var b: Vector3 = section[i+1]
				var start := Vector2(a.x,a.z)
				var end := Vector2(b.x,b.z)
				var reach: float = route.width*0.5+step*0.95
				var low := ((start.min(end)-Vector2.ONE*reach)/step).floor()
				var high := ((start.max(end)+Vector2.ONE*reach)/step).ceil()
				for x in range(int(low.x),int(high.x)):
					for z in range(int(low.y),int(high.y)):
						var center := Vector2(x+0.5,z+0.5)*step
						if center.distance_to(Geometry2D.get_closest_point_to_segment(center,start,end)) <= reach:
							cells[Vector2i(x,z)*step] = true
	var ids := {}
	var keys: Array[Vector2i] = []
	var heights := PackedFloat64Array()
	var movable := PackedFloat64Array()
	var triangles: Array[Vector3i] = []
	var summit := vec(layout.landmarks.E_summit)
	var bridge := vec(layout.landmarks.D_bridge)
	var plaza: Array = layout.summit.plaza
	for cell: Vector2i in cells:
		var corners := PackedInt32Array()
		for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
			var key := cell+offset*step
			if not ids.has(key):
				ids[key]=keys.size()
				keys.append(key)
				var abutment := absf(absf(key.x-bridge.x)-10.0)<=1.0 and absf(key.y-bridge.z)<=3
				heights.append(bridge.y if abutment else vertex(key.x,key.y).y)
				var on_plaza: bool = absf(key.x-summit.x)<=plaza[0]*0.5 and absf(key.y-summit.z-layout.summit.plaza_center_z)<=plaza[1]*0.5
				var under_deck := absf(key.x-bridge.x)<11 and absf(key.y-bridge.z)<3
				movable.append(0.0 if on_plaza or under_deck or abutment else 1.0)
			corners.append(ids[key])
		triangles.append(Vector3i(corners[0],corners[1],corners[2]))
		triangles.append(Vector3i(corners[3],corners[2],corners[1]))
	var allowed := step*tan(deg_to_rad(34.0))
	for iteration in range(36):
		var largest := 0.0
		for t in triangles:
			var dh := Vector2(heights[t.y]-heights[t.x],heights[t.z]-heights[t.x])
			var excess := dh.length()-allowed
			if excess <= 0.001: continue
			var dir := dh.normalized()
			var center_weight := -dir.x-dir.y
			var weight := center_weight*center_weight*movable[t.x]+dir.x*dir.x*movable[t.y]+dir.y*dir.y*movable[t.z]
			if weight < 0.0001: continue
			var correction := excess/weight
			heights[t.x]-=correction*center_weight*movable[t.x]
			heights[t.y]-=correction*dir.x*movable[t.y]
			heights[t.z]-=correction*dir.y*movable[t.z]
			largest=maxf(largest,excess)
		if largest<0.002: break
	for i in range(keys.size()):
		samples[keys[i]]=Vector3(keys[i].x,heights[i],keys[i].y)

func surface_height(x: float, z: float) -> float:
	var step := int(layout.terrain.step)
	var gx := floori(x/step)*step
	var gz := floori(z/step)*step
	var u := (x-gx)/step
	var v := (z-gz)/step
	var a := vertex(gx,gz).y
	var b := vertex(gx+step,gz).y
	var c := vertex(gx,gz+step).y
	var d := vertex(gx+step,gz+step).y
	if u+v <= 1: return a+u*(b-a)+v*(c-a)
	return d+(1-u)*(c-d)+(1-v)*(b-d)

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c-a).cross(b-a).normalized()
	for p in [a,b,c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(p)

func _build_terrain() -> void:
	var parent := group("Terrain")
	var cfg: Dictionary = layout.terrain
	var step := int(cfg.step)
	var chunk := int(cfg.chunk)
	for x0 in range(int(cfg.min_x),int(cfg.max_x),chunk):
		for z0 in range(int(cfg.min_z),int(cfg.max_z),chunk):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for x in range(x0,mini(x0+chunk,int(cfg.max_x)),step):
				for z in range(z0,mini(z0+chunk,int(cfg.max_z)),step):
					var a := vertex(x,z)
					var b := vertex(x+step,z)
					var c := vertex(x,z+step)
					var d := vertex(x+step,z+step)
					for tri in [[a,b,c],[b,d,c]]:
						var n: Vector3 = (tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
						var center: Vector3 = (tri[0]+tri[1]+tri[2])/3.0
						var color := Color("91a471").lerp(Color("b1b182"),0.5+0.5*sin(center.x*0.018+center.z*0.027))
						if n.y < 0.79: color = Color("8c91a1").lerp(Color("aaa29e"),n.y)
						_triangle(st,tri[0],tri[1],tri[2],color)
			var mesh := st.commit()
			mesh.surface_set_material(0,terrain_material)
			var node := MeshInstance3D.new()
			node.name = "Chunk_%d_%d" % [x0-int(cfg.min_x),z0-int(cfg.min_z)]
			node.mesh = mesh
			parent.add_child(node)
			if exploration_physics:
				_solid_visual(node)

func _solid_visual(visual: MeshInstance3D) -> void:
	# The existing camera fader discovers only the meshes owned by the hit body.
	var parent := visual.get_parent()
	var body := StaticBody3D.new()
	var original_name := visual.name
	var local_transform := visual.transform
	parent.remove_child(visual)
	body.name = original_name
	body.collision_mask = 0
	body.transform = local_transform
	parent.add_child(body)
	visual.name = "Surface"
	visual.transform = Transform3D.IDENTITY
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	if visual.mesh is BoxMesh:
		var box := BoxShape3D.new()
		box.size = visual.mesh.size
		collider.shape = box
	else:
		collider.shape = visual.mesh.create_trimesh_shape()
	body.add_child(collider)

func _ground_quad(st: SurfaceTool, corners: Array[Vector3], lift: float) -> void:
	# Clip the road to each actual terrain triangle. On steep brows a quad draped
	# at just its corners would cut into the ridge or bridge the hollow.
	var polygon := PackedVector2Array()
	var bounds := Rect2(Vector2(corners[0].x,corners[0].z),Vector2.ZERO)
	for p in corners:
		var uv := Vector2(p.x,p.z)
		polygon.append(uv)
		bounds = bounds.expand(uv)
	var step := int(layout.terrain.step)
	for x in range(floori(bounds.position.x/step)*step,ceili(bounds.end.x/step)*step,step):
		for z in range(floori(bounds.position.y/step)*step,ceili(bounds.end.y/step)*step,step):
			var a := Vector2(x,z)
			var b := Vector2(x+step,z)
			var c := Vector2(x,z+step)
			var d := Vector2(x+step,z+step)
			for cell in [PackedVector2Array([a,b,c]),PackedVector2Array([b,d,c])]:
				for patch in Geometry2D.intersect_polygons(polygon,cell):
					var vertices: Array[Vector3] = []
					for uv in patch:
						vertices.append(Vector3(uv.x,surface_height(uv.x,uv.y)+lift,uv.y))
					if Geometry2D.is_polygon_clockwise(patch): vertices.reverse()
					for k in range(1,vertices.size()-1):
						if (vertices[k]-vertices[0]).cross(vertices[k+1]-vertices[0]).length_squared()>0.00000001:
							_triangle(st,vertices[0],vertices[k],vertices[k+1],Color.WHITE)

func _emit_ribbon(st: SurfaceTool, points: Array, width: float, drape: bool, lift := 0.035) -> void:
	var sides: Array[Vector3] = []
	for i in range(points.size()):
		var tangent: Vector3 = points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]
		var local_width := width if drape else water_width(points[i].z)
		sides.append(Vector3(-tangent.z,0,tangent.x).normalized()*local_width*0.5)
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var count := maxi(1,ceili(a.distance_to(b)))
		for j in range(count):
			var p := a.lerp(b,float(j)/count)
			var q := a.lerp(b,float(j+1)/count)
			var left := sides[i].lerp(sides[i+1],float(j)/count)
			var right := sides[i].lerp(sides[i+1],float(j+1)/count)
			if drape:
				_ground_quad(st,[p-left,q-right,q+right,p+left],lift)
			else:
				_triangle(st,p-left,q-right,p+left,Color.WHITE)
				_triangle(st,p+left,q-right,q+right,Color.WHITE)

func _finish_mesh(parent: Node3D, label: String, st: SurfaceTool, m: Material) -> void:
	var mesh := st.commit()
	mesh.surface_set_material(0,m)
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	parent.add_child(node)

func _build_paths() -> void:
	var parent := group("RouteProxies")
	for route in routes:
		var road_surface := SurfaceTool.new()
		road_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sections: Array = bridge_approaches(route.curve) if route.id=="river" else [route.curve]
		for section in sections: _emit_ribbon(road_surface,section,route.width,true)
		_finish_mesh(parent,route.id,road_surface,path_material)
	# Each tread marker shares the curved centerline and the actual road grade.
	var main: Array = routes[0].curve
	var flights := SurfaceTool.new()
	flights.begin(Mesh.PRIMITIVE_TRIANGLES)
	for flight in layout.stairs:
		var first := int(flight.segment)*4
		var count := maxi(2,ceili(main[first].distance_to(main[first+4])*(flight.to-flight.from)/1.1))
		for j in range(count):
			var t := 4*lerpf(flight.from,flight.to,float(j)/count)
			var i := first+floori(t)
			var a: Vector3 = main[i]
			var b: Vector3 = main[i+1]
			var p := a.lerp(b,t-floorf(t))
			var half_step := (b-a).normalized()*0.22
			_emit_ribbon(flights,[p-half_step,p+half_step],5.5,true,0.095)
	_finish_mesh(parent,"StairFlights",flights,stone)
	var river := group("RiverProxy")
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_ribbon(water,river_points,layout.valley.water_width,false)
	_finish_mesh(river,"Water",water,material(Color("72999f")))

func block(parent: Node3D, p: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = m
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = p
	parent.add_child(node)
	return node

func arch(parent: Node3D, base: Vector3, width: float, height: float, thickness: float, depth: float) -> void:
	var radius := width*0.5
	var rise := minf(radius,height*0.75)
	var spring := height-rise
	for sign_x in [-1,1]:
		block(parent,base+Vector3(sign_x*(radius+thickness*0.5),spring*0.5,0),Vector3(thickness,spring,depth),stone)
	# Deliberately plain arch silhouette; voussoirs/weathering belong to stage 03.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(12):
		var a := PI*float(i)/12
		var b := PI*float(i+1)/12
		var inner_a := Vector2(cos(a),sin(a))*radius
		var inner_b := Vector2(cos(b),sin(b))*radius
		var outer_a := Vector2(cos(a),sin(a))*(radius+thickness)
		var outer_b := Vector2(cos(b),sin(b))*(radius+thickness)
		var v: Array[Vector3] = []
		for dz in [-depth*0.5,depth*0.5]:
			for pt in [inner_a,inner_b,outer_a,outer_b]: v.append(base+Vector3(pt.x,spring+pt.y*rise/radius,dz))
		for face in [[0,1,2],[1,3,2],[4,6,5],[5,6,7],[0,4,1],[1,4,5],[2,3,6],[3,7,6]]:
			_triangle(st,v[face[0]],v[face[2]],v[face[1]],Color.WHITE)
	var mesh := st.commit()
	mesh.surface_set_material(0,stone)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	parent.add_child(visual)

func _build_landmarks() -> void:
	var parent := group("ArchitectureProxies")
	var gate := vec(layout.landmarks.A_gate)
	arch(parent,gate,6,10.2,1.35,2.0)
	block(parent,gate+Vector3(-9,1.7,0),Vector3(9,3.4,1.7),stone)
	block(parent,gate+Vector3(9,1.1,0),Vector3(9,2.2,1.7),stone)
	var left := vec(layout.landmarks.C_overlook)
	for remnant in [[Vector2(-7,0),Vector3(3,3,2)],[Vector2(2,7),Vector3(2,2,2)]]:
		var offset: Vector2 = remnant[0]
		var size: Vector3 = remnant[1]
		var at := Vector3(left.x+offset.x,0,left.z+offset.y)
		at.y = surface_height(at.x,at.z)+size.y*0.5-0.18
		block(parent,at,size,stone)
	var bridge := vec(layout.landmarks.D_bridge)
	block(parent,bridge+Vector3(0,-0.5,0),Vector3(23,1,5.5),stone)
	arch(parent,bridge+Vector3(0,-6,2.2),16,5.5,1,0.8)
	arch(parent,bridge+Vector3(0,-6,-2.2),16,5.5,1,0.8)

func _build_summit(parent: Node3D) -> void:
	var summit := Node3D.new()
	summit.name = "Summit"
	summit.position = vec(layout.landmarks.E_summit)
	parent.add_child(summit)
	var cfg: Dictionary = layout.summit
	block(summit,Vector3(0,-0.36,cfg.plaza_center_z),Vector3(cfg.plaza[0],0.8,cfg.plaza[1]),stone).name = "PlazaSurface"
	var builder := preload("res://scripts/maps/wind_hills_rebuild/summit_masonry.gd").new()
	builder.build(summit,cfg,material(Color.WHITE,true),exploration_physics)

func _build_background_proxies() -> void:
	var parent := group("DistantCompositionProxies")
	# Just low-poly silhouette placeholders for region F; no stage-04 finish.
	for layer in range(2):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var z := -470.0-layer*210.0
		for i in range(25):
			var x := -880.0+i*72.0
			var y1 := 42.0 + 18*sin(i*1.7+layer) + 10*cos(i*0.7)
			var y2 := 42.0 + 18*sin((i+1)*1.7+layer) + 10*cos((i+1)*0.7)
			var a := Vector3(x,-45,z+130+sin(i)*48)
			var b := Vector3(x+72,-45,z+130+sin(i+1)*48)
			var c := Vector3(x,y1,z+sin(i)*32)
			var d := Vector3(x+72,y2,z+sin(i+1)*32)
			_triangle(st,a,c,b,Color.WHITE)
			_triangle(st,b,c,d,Color.WHITE)
		var mesh := st.commit()
		mesh.surface_set_material(0,material(Color("b5c3cf") if layer==0 else Color("c5d0dd")))
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	var aqueduct := vec(layout.landmarks.F_aqueduct)
	_proxy_mesa(parent,aqueduct+Vector3(30,0,-5),Vector2(100,30))
	for i in range(5): arch(parent,aqueduct+Vector3(i*15,0,0),11,20+sin(i)*2,2,3)
	var tower := vec(layout.landmarks.F_tower)
	_proxy_mesa(parent,tower+Vector3(8,0,-10),Vector2(65,45))
	block(parent,tower+Vector3(0,20,0),Vector3(7,40,7),stone)
	block(parent,tower+Vector3(19,7,0),Vector3(5,14,5),stone)
	var far_stone := material(Color("a8b3c5"))
	for child in parent.get_children():
		if child is MeshInstance3D and child.mesh.surface_get_material(0)==stone:
			child.material_override = far_stone

func _proxy_mesa(parent: Node3D, center: Vector3, extent: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a := TAU*i/8
		var b := TAU*(i+1)/8
		var p := center+Vector3(cos(a)*extent.x*0.5,0,sin(a)*extent.y*0.5)
		var q := center+Vector3(cos(b)*extent.x*0.5,0,sin(b)*extent.y*0.5)
		var r := Vector3(center.x+cos(a)*extent.x*1.4,-45,center.z+sin(a)*extent.y*3)
		var s := Vector3(center.x+cos(b)*extent.x*1.4,-45,center.z+sin(b)*extent.y*3)
		_triangle(st,center,p,q,Color.WHITE)
		_triangle(st,p,r,q,Color.WHITE)
		_triangle(st,q,r,s,Color.WHITE)
	var mesh := st.commit()
	mesh.surface_set_material(0,material(Color("afbfcf")))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
