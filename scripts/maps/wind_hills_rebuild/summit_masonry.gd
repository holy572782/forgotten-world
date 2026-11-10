@tool
extends RefCounted
## One render surface and one continuous low-detail collision shell per member.
var surface: SurfaceTool
var shell: SurfaceTool
var stone: Material
var solid: bool
var rng := RandomNumberGenerator.new()
var palette := [Color("c0b596"),Color("c8bda3"),Color("b3ad9e"),Color("bdb4a9"),Color("c3b8a4"),Color("aaa5a0")]

func build(root: Node3D, cfg: Dictionary, material: Material, physics: bool) -> void:
	stone = material
	solid = physics
	rng.seed = 310937
	var index := 0
	for row in cfg.arches_xz_width_height_rim_depth_yaw:
		var bay := Node3D.new()
		bay.name = "Bay%02d" % index
		bay.position = Vector3(row[0],0,row[1])
		bay.rotation.y = deg_to_rad(row[6])
		root.add_child(bay)
		_bay(bay,index,row[2]*0.5,row[3],row[4],row[5])
		index += 1
	index = 0
	for row in cfg.piers_xz_height:
		_begin()
		_pier(row[2],1.75,1.9,index%3!=0)
		_finish(root,"Pier%02d"%index,Vector3(row[0],0,row[1]),0)
		index += 1
	index = 0
	for row in cfg.wall_fragments_xz_width_height_depth_yaw:
		_begin()
		_wall(row[2],row[3],row[4],index)
		_finish(root,"Wall%02d"%index,Vector3(row[0],0,row[1]),row[5])
		index += 1

func _begin() -> void:
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	shell = SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)

func _finish(parent: Node3D, label: String, position: Vector3, yaw: float) -> void:
	surface.index()
	var mesh := surface.commit()
	mesh.surface_set_material(0,stone)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var member: Node3D = visual
	if solid:
		var body := StaticBody3D.new()
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shell.commit().create_trimesh_shape()
		body.add_child(collider)
		body.add_child(visual)
		member = body
	member.name = label
	member.position = position
	member.rotation.y = deg_to_rad(yaw)
	parent.add_child(member)

func _face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var n := (c-a).cross(b-a)
	if n.length_squared()<0.000000001: return
	if n.dot(a-inside)<0:
		var swap := b
		b = c
		c = swap
		n = -n
	n = n.normalized()
	for v: Vector3 in [a,b,c]:
		tool.set_color(color)
		tool.set_normal(n)
		tool.add_vertex(v)

func _loft(tool: SurfaceTool, rings: Array, color: Color) -> void:
	var first: PackedVector3Array = rings.front()
	var last: PackedVector3Array = rings.back()
	var inside := Vector3.ZERO
	for i in first.size(): inside += first[i]+last[i]
	inside /= 2.0*first.size()
	for k in range(rings.size()-1):
		for i in first.size():
			var j := (i+1)%first.size()
			_face(tool,rings[k][i],rings[k][j],rings[k+1][j],inside,color)
			_face(tool,rings[k][i],rings[k+1][j],rings[k+1][i],inside,color)
	for i in range(1,first.size()-1):
		_face(tool,first[0],first[i],first[i+1],inside,color)
		_face(tool,last[0],last[i],last[i+1],inside,color)

func _tint() -> Color:
	return palette[rng.randi_range(0,palette.size()-1)]

func _ring(w: float,d: float,y: float,center: Vector2,tilt: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for v: Vector2 in [Vector2(-0.72,-1),Vector2(0.72,-1),Vector2(1,-0.72),Vector2(1,0.72),Vector2(0.72,1),Vector2(-0.72,1),Vector2(-1,0.72),Vector2(-1,-0.72)]:
		points.append(Vector3(center.x+v.x*w*0.5,y+tilt*(v.x+0.4*v.y),center.y+v.y*d*0.5))
	return points

func _course(y: float,h: float,w: float,d: float,center:=Vector2.ZERO,tilt:=0.0) -> void:
	var bevel := minf(0.065,h*0.18)
	_loft(surface,[_ring(w*.94,d*.94,y,center,0),_ring(w,d,y+bevel,center,0),
		_ring(w,d,y+h-bevel,center,tilt),_ring(w*.94,d*.94,y+h,center,tilt)],_tint())

func _pier(h: float,w: float,d: float,broken: bool) -> void:
	var base := minf(h*.17,1.35)
	var cap := minf(.9,h*.13)
	_course(0,base*.36,w*1.5,d*1.34)
	_course(base*.36,base*.64,w*1.26,d*1.18)
	var count := maxi(2,roundi((h-base-cap)/1.25))
	var rise := (h-base-cap)/count
	for i in count:
		var y := base+i*rise
		_course(y,rise,w,d)
		# Engaged shafts run up both faces to carry the projecting archivolts.
		for z in [-1,1]:
			for x in [-1,1]:
				_course(y,rise,w*.26,d*.25,Vector2(x*w*.32,z*d*.48))
	_course(h-cap,cap*.4,w*1.18,d*1.22)
	var tilt := cap*.30 if broken else 0.0
	if broken:
		_course(h-cap*.6,cap*.55,w*1.04,d*1.03,Vector2.ZERO,tilt*.35)
		_course(h-cap*.07,cap*.48,w*.62,d*.81,Vector2(-w*.18,-d*.045),tilt*.7)
	else:
		_course(h-cap*.6,cap*.6,w*1.38,d*1.30)
	if solid:
		_loft(shell,[_ring(w*1.5,d*1.34,0,Vector2.ZERO,0),_ring(w*1.5,d*1.34,base*.36,Vector2.ZERO,0),
			_ring(w,d*1.14,base,Vector2.ZERO,0),_ring(w,d*1.14,h-cap,Vector2.ZERO,0),
			_ring(w*1.25,d*1.3,h,Vector2.ZERO,tilt)],Color.WHITE)

func _arc(r: float,spring: float,side: int,t: float,offset: float) -> Vector2:
	var shift := r*.45
	var radius := r+shift+offset
	var angle := t*acos(shift/radius)
	return Vector2(side*(radius*cos(angle)-shift),spring+radius*sin(angle))

# Sweep the moulding as a single stepped cross-section. Both archivolts and
# the recessed band between them share edges with the body of the voussoir.
func _arch_section(r: float,spring: float,side: int,t: float,rim: float,depth: float,detail: bool,crown: float) -> PackedVector3Array:
	var face := PackedVector3Array()
	var outline := [Vector2(0,.5),Vector2(1,.5),Vector2(1,-.5),Vector2(0,-.5)]
	if detail:
		outline = [Vector2(0,.43),Vector2(.07,.53),Vector2(.15,.60),Vector2(.26,.60),
			Vector2(.32,.48),Vector2(.72,.48),Vector2(.80,.55),Vector2(.97,.55),Vector2(1,.49),
			Vector2(1,-.49),Vector2(.97,-.55),Vector2(.80,-.55),Vector2(.72,-.48),Vector2(.32,-.48),
			Vector2(.26,-.60),Vector2(.15,-.60),Vector2(.07,-.53),Vector2(0,-.43)]
	for v: Vector2 in outline:
		var xy := _arc(r,spring,side,t,lerpf(-crown*.18,rim+crown*.28,v.x))
		face.append(Vector3(xy.x,xy.y,v.y*(depth+crown*.38)))
	return face

func _wedge(tool: SurfaceTool,r: float,spring: float,side: int,a: float,b: float,rim: float,depth: float,detail: bool,crown:=0.0) -> void:
	var first := _arch_section(r,spring,side,a,rim,depth,detail,crown)
	var last := _arch_section(r,spring,side,b,rim,depth,detail,crown)
	var color := _tint() if detail else Color.WHITE
	var center := (first[0]+first[first.size()/2]+last[0]+last[last.size()/2])*.25
	for i in first.size():
		var j := (i+1)%first.size()
		# Winding follows the cross section even across the recessed channels.
		if side>0:
			_tri(tool,first[i],last[i],first[j],color)
			_tri(tool,last[i],last[j],first[j],color)
		else:
			_tri(tool,first[i],first[j],last[i],color)
			_tri(tool,last[i],first[j],last[j],color)
	# Close each end with strips across its thickness.
	var half := first.size()/2
	for k in range(half-1):
		for end: PackedVector3Array in [first,last]:
			_face(tool,end[k],end[k+1],end[-1-k],center,color)
			_face(tool,end[k+1],end[-2-k],end[-1-k],center,color)

func _tri(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	var normal := (c-a).cross(b-a).normalized()
	for v: Vector3 in [a,b,c]:
		tool.set_color(color)
		tool.set_normal(normal)
		tool.add_vertex(v)

func _bay(parent: Node3D,index: int,r: float,h: float,rim: float,depth: float) -> void:
	var spring := h-r*sqrt(1.9)
	for side: int in [-1,1]:
		var ruined := index in [2,4,8]
		var short_side := ruined and side==(1 if index==4 else -1)
		_begin()
		_pier(spring*(.62 if short_side else 1.0),rim,depth,short_side)
		_finish(parent,"East" if side==1 else "West",Vector3(side*(r+rim*.5),0,0),0)
	_begin()
	for side: int in [-1,1]:
		var extent := 1.0
		if index in [2,4,8]: extent = 0.0 if side==(1 if index==4 else -1) else .57
		var count := 11 if index==0 else 7
		for i in ceili(extent*count):
			var a := float(i)/count
			var b := minf(extent,float(i+1)/count)
			var crown := 1.0 if index==0 and i==count-1 else 0.0
			_wedge(surface,r,spring,side,a+.001,b if b==1.0 else b-.001,rim,depth*rng.randf_range(.98,1.02),true,crown)
		if solid and extent>0:
			for i in 5:
				_wedge(shell,r,spring,side,extent*i/5,extent*(i+1)/5,rim,depth,false)
	_finish(parent,"Vault",Vector3.ZERO,0)

func _wall(w: float,h: float,d: float,index: int) -> void:
	var courses := maxi(3,roundi(h/.8))
	var rise := h/courses
	for i in courses:
		var loss := maxf(0,float(i)/courses-.35)*w
		var left := -w*.5+loss*(.24 if index%2 else 1.12)
		var right := w*.5-loss*(1.0 if index%2 else .20)
		var x := left
		while x<right-.01:
			var length := minf(right-x,rng.randf_range(1.25,2.4))
			if right-x-length<.55: length=right-x
			var tilt := rng.randf_range(-.15,.15) if i==courses-1 else 0.0
			_course(i*rise,rise,length,d*rng.randf_range(.97,1.04),Vector2(x+length*.5,0),tilt)
			x+=length
		if solid:
			var center := Vector2((left+right)*.5,0)
			_loft(shell,[_ring(right-left,d,i*rise,center,0),_ring(right-left,d,(i+1)*rise,center,0)],Color.WHITE)
