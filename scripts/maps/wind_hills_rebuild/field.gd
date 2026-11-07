@tool
extends Node3D
## Stage 01: editable composition blockout, not accepted walking geometry.
@export_file("*.json") var layout_path := "res://resources/maps/wind_hills_rebuild/layout.json"
var layout: Dictionary
var routes: Array = []
var river_points: Array[Vector3] = []
var generation_ms := 0.0
var terrain_material: StandardMaterial3D
var stone: StandardMaterial3D
var path_material: StandardMaterial3D
var samples: Dictionary = {}

func _ready() -> void:
	if has_node("Terrain"): return
	var started := Time.get_ticks_usec()
	layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	scale = Vector3.ONE * float(layout.world_scale)
	for route in layout.routes:
		var points: Array[Vector3] = []
		for p in route.points: points.append(vec(p))
		routes.append({"id": route.id, "width": float(route.width), "points": points, "curve": smooth_points(points)})
	for p in layout.river: river_points.append(vec(p))
	river_points = smooth_points(river_points)
	terrain_material = material(Color.WHITE, true)
	stone = material(Color("cfc8b6"))
	path_material = material(Color("d9cba8"))
	_build_terrain()
	_build_paths()
	_build_landmarks()
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
	print("WindHills rebuild stage01: %.1f ms; composition only" % generation_ms)

func vec(p: Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])

func smooth_points(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(points.size()-1):
		var a := points[maxi(0,i-1)]
		var b := points[i]
		var c := points[i+1]
		var d := points[mini(points.size()-1,i+2)]
		for j in range(4):
			var t := j/4.0
			var p := b.cubic_interpolate(c,a,d,t)
			p.y = lerpf(b.y,c.y,t)
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

func route_sample(x: float, z: float) -> Dictionary:
	var best := {"distance": INF, "height": 0.0, "width": 5.4}
	var q := Vector2(x,z)
	for route in routes:
		for i in range(route.curve.size()-1):
			var a: Vector3 = route.curve[i]
			var b: Vector3 = route.curve[i+1]
			var delta := Vector2(b.x-a.x,b.z-a.z)
			var t := clampf((q-Vector2(a.x,a.z)).dot(delta)/delta.length_squared(),0,1)
			var d := q.distance_to(Vector2(a.x,a.z)+delta*t)
			if d < best.distance:
				best = {"distance":d,"height":lerpf(a.y,b.y,t),"width":route.width}
	return best

func river_sample(x: float, z: float) -> Dictionary:
	var best := {"distance": INF, "height": -30.0}
	var q := Vector2(x,z)
	for i in range(river_points.size()-1):
		var a := river_points[i]
		var b := river_points[i+1]
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf((q-Vector2(a.x,a.z)).dot(delta)/delta.length_squared(),0,1)
		var d := q.distance_to(Vector2(a.x,a.z)+delta*t)
		if d < best.distance: best = {"distance":d,"height":lerpf(a.y,b.y,t)}
	return best

func height_at(x: float, z: float) -> float:
	var valley := -36.0 + sin(x*0.035+z*0.015)*3.0
	var crest := clampf(-z/245.0,0,1)*60.0-20.0
	var axis := 10.0 + clampf(-z/245.0,0,1)*32.0 + sin(z*0.023)*9.0
	var ridge := (1.0-smoothstep(66,153,absf(x-axis)))*(1.0-smoothstep(266,335,-z))*(1.0-smoothstep(26,78,z))
	var h := lerpf(valley,crest,ridge)
	var left_base := 1.0-smoothstep(0.3,1.3,Vector2((x+116)/62,(z+120)/73).length())
	h = maxf(h,lerpf(valley,8,left_base))
	for t in layout.terraces:
		var dx: float = (x-t[0])/t[2]
		var dz: float = (z-t[1])/t[3]
		var angle := atan2(dz,dx)
		var edge := 1.0 + sin(angle*3.0+t[0])*0.08 + sin(angle*7.0+t[1])*0.04
		var radius := Vector2(dx,dz).length()/edge
		var weight := 1.0-smoothstep(0.70,1.18,radius)
		var top: float = t[4] + sin(x*0.065+z*0.031)*0.7 + sin(z*0.09)*0.4
		h = lerpf(h,maxf(h,top),weight)
	var road := route_sample(x,z)
	# A broad shoulder prevents a road cut from becoming a narrow trench.
	h = lerpf(h,minf(h,road.height+0.4),1.0-smoothstep(5,21,road.distance))
	h = lerpf(h,road.height,1.0-smoothstep(road.width*0.5+0.5,road.width*0.5+8,road.distance))
	# Broad real valley silhouette, including below the bridge proxy.
	var river := river_sample(x,z)
	var cut := 1.0-smoothstep(4.0,14.0,river.distance)
	h = lerpf(h,minf(h,river.height-1.6),cut)
	# Stable local rehearsal ground only; full-route collision is stage 02.
	if x >= -30 and x <= 0 and z >= -10 and z <= 22: h = 0.0
	return h

func vertex(x: int, z: int) -> Vector3:
	var key := Vector2i(x,z)
	if not samples.has(key): samples[key] = Vector3(x,height_at(x,z),z)
	return samples[key]

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
	# Explicitly local collision, not a misleading full-map traversal claim.
	var pad := StaticBody3D.new()
	pad.name = "EntranceRehearsalFloor"
	add_child(pad)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,1,32)
	shape.shape = box
	shape.position = Vector3(-15,-0.5,6)
	pad.add_child(shape)

func _ribbon(parent: Node3D, points: Array, width: float, m: Material, drape: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: Array[Vector3] = []
	for i in range(points.size()):
		var tangent: Vector3 = points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]
		sides.append(Vector3(-tangent.z,0,tangent.x).normalized()*width*0.5)
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var count := maxi(1,ceili(a.distance_to(b)))
		var columns := maxi(1,ceili(width))
		for j in range(count):
			var p := a.lerp(b,float(j)/count)
			var q := a.lerp(b,float(j+1)/count)
			var left := sides[i].lerp(sides[i+1],float(j)/count)
			var right := sides[i].lerp(sides[i+1],float(j+1)/count)
			for col in range(columns):
				var u := -1.0+2.0*col/columns
				var v := -1.0+2.0*(col+1)/columns
				var vertices: Array[Vector3] = [p+left*u,p+left*v,q+right*u,q+right*v]
				for k in range(4):
					if drape: vertices[k].y = surface_height(vertices[k].x,vertices[k].z)+0.10
				_triangle(st,vertices[0],vertices[2],vertices[1],Color.WHITE)
				_triangle(st,vertices[1],vertices[2],vertices[3],Color.WHITE)
	var mesh := st.commit()
	mesh.surface_set_material(0,m)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)

func _build_paths() -> void:
	var parent := group("RouteProxies")
	for route in routes:
		_ribbon(parent,route.curve,route.width,path_material,true)
	# Transverse bars locate provisional stair flights; no detailed stairs/colliders.
	var main: Array = routes[0].points
	for flight in layout.stairs:
		var a: Vector3 = main[int(flight.segment)]
		var b: Vector3 = main[int(flight.segment)+1]
		var start := a.lerp(b,flight.from)
		var end := a.lerp(b,flight.to)
		var count := maxi(2,ceili(start.distance_to(end)/1.1))
		for j in range(count):
			var p := start.lerp(end,float(j)/count)
			p.y = height_at(p.x,p.z)+0.22
			var node := block(parent,p,Vector3(6,0.18,0.4),stone)
			node.rotation.y = atan2(b.x-a.x,b.z-a.z)
	var river := group("RiverProxy")
	_ribbon(river,river_points,4.0,material(Color("72999f")),false)

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
	var top := vec(layout.landmarks.E_summit)
	block(parent,top+Vector3(0,-0.5,0),Vector3(49,1,24),stone)
	arch(parent,top+Vector3(4,0,-3),12,22,1.7,2.4)
	arch(parent,top+Vector3(-13,0,-4),6,12,1.1,2)
	arch(parent,top+Vector3(19,0,-4),5,14,1.1,2)
	for item in [[-23,16,1],[-19,12,-9],[25,13,3],[11,17,-10],[-6,13,-13]]:
		block(parent,top+Vector3(item[0],float(item[1])*0.5,item[2]),Vector3(1.6,item[1],1.6),stone)
	var left := vec(layout.landmarks.C_overlook)
	block(parent,left+Vector3(-7,1.5,0),Vector3(3,3,2),stone)
	block(parent,left+Vector3(8,1,2),Vector3(2,2,2),stone)
	var bridge := vec(layout.landmarks.D_bridge)
	block(parent,bridge+Vector3(0,-0.5,0),Vector3(23,1,5.5),stone)
	arch(parent,bridge+Vector3(0,-6,2.2),16,5.5,1,0.8)
	arch(parent,bridge+Vector3(0,-6,-2.2),16,5.5,1,0.8)

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
