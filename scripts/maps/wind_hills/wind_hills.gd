@tool
extends Node3D
## Deterministic stage-A construction, once on scene entry (also visible in editor).
## All dimensions live in layout.json. No shared gameplay Resource is mutated.
const LAYOUT_PATH := "res://resources/maps/wind_hills/layout.json"
const EntranceGround = preload("res://scripts/maps/wind_hills/entrance_ground_materials.gd")
@export var entrance_ground: Resource = preload("res://resources/maps/wind_hills/entrance_ground.tres")
var entrance_materials: RefCounted
var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
var routes: Array = []
var grass: StandardMaterial3D
var stone: StandardMaterial3D
var paving: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var _vertices: Dictionary = {}

func _ready() -> void:
	if has_node("Terrain"): return
	rng.seed = 1062026
	for route in layout.routes:
		var points: Array[Vector3] = []
		for p in route.points: points.append(Vector3(p[0],p[1],p[2]))
		routes.append({"id":route.id,"width":float(route.width),"points":points})
	grass = material(Color.WHITE, true)
	stone = material(Color("d6cbb3"))
	paving = material(Color("c4b69b"))
	if entrance_ground.enabled:
		entrance_materials = EntranceGround.new(entrance_ground,grass,paving)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	_build_terrain(terrain)
	_build_roads()
	_build_ruins()
	_build_river()
	_build_distant()
	_build_scatter()
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0,0,12)
	add_child(spawn)
	for key in layout.landmarks:
		var marker := Marker3D.new()
		marker.name = key
		var p: Array = layout.landmarks[key]
		marker.position = Vector3(p[0],p[1],p[2])
		add_child(marker)
	if Engine.is_editor_hint() and entrance_materials!=null:
		print("WindHills B01 editor: ",entrance_materials.terrain_triangles," painted triangles / ",entrance_materials.tiles," slabs")

func material(color: Color, vertex := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	result.vertex_color_use_as_albedo = vertex
	result.vertex_color_is_srgb = true
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return result

func route_sample(x: float, z: float) -> Dictionary:
	var best := {"distance":INF,"height":0.0,"width":6.0}
	var q := Vector2(x,z)
	for route in routes:
		var pts: Array = route.points
		for i in range(pts.size()-1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i+1]
			var start := Vector2(a.x,a.z)
			var delta := Vector2(b.x-a.x,b.z-a.z)
			var t := clampf((q-start).dot(delta)/delta.length_squared(),0,1)
			var d := q.distance_to(start+delta*t)
			if d < best.distance:
				var rise_t := t
				if route.id == "main":
					for flight in layout.stairs:
						if int(flight.segment)==i: rise_t = clampf((t-flight.start)/(flight.end-flight.start),0,1)
				best = {"distance":d,"height":lerpf(a.y,b.y,rise_t),"width":route.width}
	return best

func height_at(x: float, z: float) -> float:
	var h := -19.0 + sin(x*0.046+z*0.021)*2.0 + cos(z*0.055)*1.5
	# A broad hillside joins the terraces; cliffs do not fall to the valley at every tier.
	var crest := clampf(-z/230.0,0,1)*44.0-5.0
	var hill := (1.0-smoothstep(0.35,1.0,absf((x-10.0)/110.0)))*(1.0-smoothstep(240,285,-z))*(1.0-smoothstep(20,50,z))
	h = maxf(h,lerpf(-19.0,crest,hill))
	for t in layout.terraces:
		var distance := Vector2((x-t[0])/t[2],(z-t[1])/t[3]).length()
		var ripple := sin(x*0.19+z*0.13)*0.025
		var weight := 1.0-smoothstep(0.84+ripple,1.08+ripple,distance)
		h = maxf(h,lerpf(-20.0,float(t[4]),weight))
	for plaza in [Vector3(0,2,-45),Vector3(15,18,-125)]:
		var d := Vector2(x-plaza.x,z-plaza.z).length()
		h = lerpf(h,plaza.y,1.0-smoothstep(12.0,17.0,d))
	var road := route_sample(x,z)
	var half: float = road.width*0.5
	# Wide flat cross-section, with a continuous shoulder back into the hill.
	h = lerpf(h,road.height,1.0-smoothstep(half+0.8,half+6.0,road.distance))
	# Cut a real channel under the independently colliding bridge deck.
	var river_x := 95.0+5.0*sin((z+65.0)*0.035)
	var channel := 1.0-smoothstep(2.8,5.5,absf(x-river_x))
	if z > -154 and z < 12: h = lerpf(h,minf(h,-13.3),channel)
	return h

func _vertex(x: int, z: int) -> Vector3:
	var key := Vector2i(x,z)
	if not _vertices.has(key): _vertices[key] = Vector3(x,height_at(x,z),z)
	return _vertices[key]

func _build_terrain(parent: Node3D) -> void:
	# 20m independent bodies keep M04 occlusion local; 1m sampling shares seams.
	for x0 in range(-130,130,20):
		for z0 in range(-260,40,20):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var local_materials: bool = entrance_materials!=null and entrance_materials.intersects_chunk(x0,z0,20)
			var base_surface := SurfaceTool.new()
			var painted_surface := SurfaceTool.new()
			var painted_count := 0
			var base_count := 0
			if local_materials:
				base_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				painted_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for x in range(x0,x0+20):
				for z in range(z0,z0+20):
					var a := _vertex(x,z)
					var b := _vertex(x+1,z)
					var c := _vertex(x,z+1)
					var d := _vertex(x+1,z+1)
					for triangle in [[a,b,c],[b,d,c]]:
						var normal: Vector3 = (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
						var center: Vector3 = (triangle[0]+triangle[1]+triangle[2])/3.0
						var road := route_sample(center.x,center.z)
						var color := Color("b5c27d").lerp(Color("c9c68c"),0.5+0.5*sin(center.x*0.10+center.z*0.07))
						if normal.y < 0.80: color = Color("8c93a5").lerp(Color("b3a8af"),clampf(normal.y,0,1))
						elif road.distance < road.width*0.5: color = Color("c8ba98")
						var weights: Array[float] = []
						var painted := false
						if local_materials:
							for v in triangle:
								var weight: float = entrance_materials.grass_weight(v,normal,road)
								weights.append(weight)
								painted = painted or weight>0
						for v in triangle:
							surface.set_normal(normal)
							surface.set_color(color)
							surface.add_vertex(v)
						if local_materials:
							var display := painted_surface if painted else base_surface
							for index in range(3):
								var v: Vector3 = triangle[index]
								display.set_normal(normal)
								display.set_color(color)
								if painted:
									display.set_uv(entrance_materials.mask_uv(weights[index]))
									display.set_uv2(Vector2(v.x,v.z))
								display.add_vertex(v)
							if painted: painted_count += 1
							else: base_count += 1
			var mesh := surface.commit()
			mesh.surface_set_material(0,grass)
			var body := StaticBody3D.new()
			body.name = "Chunk_%s_%s" % [x0+130,z0+260]
			body.collision_layer = 1
			body.collision_mask = 0
			parent.add_child(body)
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			if painted_count>0:
				var display_mesh := ArrayMesh.new()
				if base_count>0:
					base_surface.commit(display_mesh)
					display_mesh.surface_set_material(0,grass)
				painted_surface.commit(display_mesh)
				display_mesh.surface_set_material(display_mesh.get_surface_count()-1,entrance_materials.grass)
				visual.mesh = display_mesh
				entrance_materials.terrain_triangles += painted_count
			body.add_child(visual)
			var collision := CollisionShape3D.new()
			collision.shape = mesh.create_trimesh_shape()
			body.add_child(collision)
	_vertices.clear()

func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material, collision := true) -> Node3D:
	var node: Node3D = StaticBody3D.new() if collision else Node3D.new()
	if collision:
		node.collision_layer = 1
		node.collision_mask = 0
	parent.add_child(node)
	node.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	node.add_child(visual)
	if collision:
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = size
		shape.shape = cube
		node.add_child(shape)
	return node

func _build_roads() -> void:
	var road_root := Node3D.new()
	road_root.name = "RoadDetails"
	add_child(road_root)
	# Thin stone patches follow the real heightfield, with no second floor collider.
	for route in routes:
		for i in range(route.points.size()-1):
			var a: Vector3 = route.points[i]
			var b: Vector3 = route.points[i+1]
			var length := a.distance_to(b)
			for j in range(int(length/1.4)):
				if j%9 > 5: continue
				var t := float(j)*1.4/length
				var on_stairs := false
				if route.id == "main":
					for flight in layout.stairs:
						if int(flight.segment)==i and t>=flight.start-0.02 and t<=flight.end+0.02: on_stairs = true
				if on_stairs: continue
				var p := a.lerp(b,t)
				if absf(p.x-95)<7 and absf(p.z+65)<5: continue
				var forward := (b-a).normalized()
				var side := Vector3(-forward.z,0,forward.x).normalized()
				for lane in [-1,0,1]:
					var q: Vector3 = p+side*lane*0.9
					q.y = height_at(q.x,q.z)+0.012
					var tile := box(road_root,q,Vector3(0.80,0.025,1.12),paving,false)
					if entrance_materials!=null and entrance_materials.weight_at(q)>0:
						var visual: MeshInstance3D = tile.get_child(0)
						visual.mesh = entrance_materials.slab_mesh(Vector3(0.80,0.025,1.12),q,paving)
						visual.material_override = null
					tile.rotation.y = atan2(-forward.x,-forward.z)
					var next := q+Vector3(forward.x,0,forward.z).normalized()*0.5
					tile.rotation.x = atan2(height_at(next.x,next.z)-q.y,0.5)
	for flight in layout.stairs:
		var points: Array = routes[int(flight.route)].points
		var a: Vector3 = points[int(flight.segment)].lerp(points[int(flight.segment)+1],flight.start)
		var b: Vector3 = points[int(flight.segment)].lerp(points[int(flight.segment)+1],flight.end)
		a.y = points[int(flight.segment)].y
		b.y = points[int(flight.segment)+1].y
		var count := ceili((b.y-a.y)/0.15)
		var direction := Vector3(b.x-a.x,0,b.z-a.z).normalized()
		var tread := Vector2(b.x-a.x,b.z-a.z).length()/count
		for step in range(count):
			var p := a.lerp(b,(step+0.5)/count)
			# The tread intersects the continuous ramp; discrepancy <= 7.5cm.
			var block := box(road_root,p-Vector3.UP*0.075,Vector3(5.6,0.15,tread-0.018),stone,false)
			block.rotation.y = atan2(-direction.x,-direction.z)

func arch(parent: Node3D, at: Vector3, width: float, opening: float, depth: float, yaw := 0.0) -> void:
	var group := Node3D.new()
	parent.add_child(group)
	group.position = at
	group.rotation.y = yaw
	var radius := width*0.5
	var thickness := 0.8
	var spring := opening-radius
	for side in [-1,1]:
		box(group,Vector3(side*(radius+thickness*0.5),spring*0.5,0),Vector3(thickness,spring,depth),stone)
		box(group,Vector3(side*(radius+thickness*0.5),0.15,0),Vector3(1.25,0.3,depth+0.5),stone)
	for i in range(13):
		var angle := (i+0.5)*PI/13.0
		var center := Vector3(cos(angle)*(radius+thickness*0.5),spring+sin(angle)*(radius+thickness*0.5),0)
		var voussoir := box(group,center,Vector3(2*(radius+thickness)*sin(PI/26.0)+0.02,thickness,depth),stone)
		voussoir.rotation.z = angle-PI*0.5

func _build_ruins() -> void:
	var ruins := Node3D.new()
	ruins.name = "Ruins"
	add_child(ruins)
	arch(ruins,Vector3.ZERO,4.4,5.8,1.25)
	for side in [-1,1]:
		box(ruins,Vector3(side*3.15,4.1,0),Vector3(1.25,8.2,1.5),stone)
		for j in range(3):
			box(ruins,Vector3(side*(4.3+j*0.85),0.7+0.1*j,0),Vector3(0.82,1.4+0.2*j,1.0),stone)
	# Small landmarks stay beside the route, never across the walkable centre.
	for p in [Vector3(-6,2,-45),Vector3(7,18,-125),Vector3(-8,30,-175)]:
		arch(ruins,p,3.4,4.8,0.9,0.15)
	for x in [18.0,42.0]:
		for z in [-221.0,-231.0,-241.0]:
			arch(ruins,Vector3(x,44,z),5.0,10.4,1.2,PI*0.5)
	arch(ruins,Vector3(30,44,-239),8.0,12.5,1.4)
	# Low, broken perimeter walls leave broad entrances.
	for x in [18.0,42.0]:
		box(ruins,Vector3(x,44.8,-244),Vector3(8,1.6,1.2),stone)
	for p in [Vector3(-96,16,-107),Vector3(120,-7,-94),Vector3(8,2,-47)]:
		box(ruins,p+Vector3(0,1.15,0),Vector3(1,2.3,0.7),stone)
	for i in range(20):
		var p := Vector3(rng.randf_range(-100,65),0,rng.randf_range(-220,-10))
		if route_sample(p.x,p.z).distance < 6: continue
		p.y = height_at(p.x,p.z)
		box(ruins,p+Vector3(0,0.7,0),Vector3(rng.randf_range(2,6),1.4,0.9),stone)
	_tree(ruins,Vector3(-96,16,-98))
	_tree(ruins,Vector3(16,2,-52))

func _tree(parent: Node3D, p: Vector3) -> void:
	var trunk_mat := material(Color("867c64"))
	var leaves := material(Color("879a69"))
	box(parent,p+Vector3(0,2.3,0),Vector3(0.7,4.6,0.7),trunk_mat)
	for i in range(4):
		var crown := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radial_segments = 8
		mesh.rings = 4
		crown.mesh = mesh
		crown.material_override = leaves
		crown.position = p+Vector3(i*1.0-1.5,4.8+sin(i),0)
		crown.scale = Vector3(3.3,1.3,2.3)
		parent.add_child(crown)

func _build_river() -> void:
	var river := Node3D.new()
	river.name = "RiverAndBridge"
	add_child(river)
	var water := material(Color("81b8c0")) # Opaque first pass: stable depth, no refraction.
	for z in range(-154,12,2):
		var x := 95.0+5.0*sin((z+65.0)*0.035)
		box(river,Vector3(x,-11.7,z),Vector3(5,0.08,2.2),water,false)
	# Deck replaces the cut-out terrain. West/east abutments meet at exactly -8m.
	box(river,Vector3(95,-8.4,-65),Vector3(12,0.8,4.6),stone)
	for z in [-67.65,-62.35]:
		box(river,Vector3(95,-7.7,z),Vector3(12,0.6,0.55),stone)
	for x in [89.0,101.0]:
		box(river,Vector3(x,-10.8,-65),Vector3(1.3,4.8,5.7),stone)
	# Arched ribs run below the deck; full geometry is visible from the valley.
	for z in [-67.0,-63.0]:
		for i in range(15):
			var angle := (i+0.5)*PI/15.0
			var rib := box(river,Vector3(95+5.1*cos(angle),-13.0+3.9*sin(angle),z),Vector3(1.18,0.7,0.6),stone)
			rib.rotation.z = atan2(3.9*cos(angle),-5.1*sin(angle))

func _build_distant() -> void:
	var distant := Node3D.new()
	distant.name = "DistantNonWalkable"
	add_child(distant)
	# A lower valley apron hides the rectangular sampling boundary in distant views.
	var apron := SurfaceTool.new()
	apron.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(-490,490,20):
		for z in range(-500,200,20):
			if x>=-130 and x<130 and z>=-260 and z<40: continue
			var points: Array[Vector3] = []
			for q in [Vector2(x,z),Vector2(x+20,z),Vector2(x,z+20),Vector2(x+20,z+20)]:
				var edge := Vector2(clampf(q.x,-130,130),clampf(q.y,-260,40))
				var distance := edge.distance_to(q)
				var basin := -35.0+sin(q.x*0.026+q.y*0.013)*5.0
				var h := lerpf(height_at(edge.x,edge.y),basin,smoothstep(0,100,distance))
				points.append(Vector3(q.x,h,q.y))
			for tri in [[0,1,2],[1,3,2]]:
				var normal := (points[tri[2]]-points[tri[0]]).cross(points[tri[1]]-points[tri[0]]).normalized()
				for index in tri:
					apron.set_normal(normal)
					apron.add_vertex(points[index])
	var basin_mesh := MeshInstance3D.new()
	basin_mesh.mesh = apron.commit()
	basin_mesh.material_override = material(Color("9eae9a"))
	distant.add_child(basin_mesh)
	for i in range(25):
		var mountain := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = rng.randf_range(3,14)
		mesh.bottom_radius = rng.randf_range(65,125)
		mesh.height = rng.randf_range(40,100)
		mesh.radial_segments = 7
		mountain.mesh = mesh
		mountain.material_override = material(Color("b2c3cc") if i<17 else Color("dfddd1"))
		mountain.position = Vector3(-680+i*57,-10,-370-rng.randf_range(40,200))
		distant.add_child(mountain)
	for i in range(6):
		arch(distant,Vector3(-220+i*20,6,-345),17,25,4)

func _build_scatter() -> void:
	# One draw batch, no collider per rock/tuft. Decoration stays clear of roads.
	var instances := MultiMeshInstance3D.new()
	instances.name = "SmallRocks"
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radial_segments = 5
	mesh.rings = 2
	mesh.material = material(Color.WHITE,true)
	batch.mesh = mesh
	var placements: Array[Transform3D] = []
	for i in range(1600):
		var x := rng.randf_range(-125,125)
		var z := rng.randf_range(-250,30)
		var road := route_sample(x,z)
		if road.distance < road.width*0.5+1.2: continue
		var h := height_at(x,z)
		if h < -10: continue
		var size := rng.randf_range(0.18,0.7)
		placements.append(Transform3D(Basis.IDENTITY.scaled(Vector3(size*1.7,size,size)),Vector3(x,h,z)))
	batch.instance_count = placements.size()
	for i in range(placements.size()):
		batch.set_instance_transform(i,placements[i])
		batch.set_instance_color(i,Color("b7b2a1"))
	instances.multimesh = batch
	add_child(instances)
