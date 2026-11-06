@tool
extends RefCounted
## Opaque StandardMaterial detail mixing: UV1 is blend weight, UV2 is texture UV.
## The mask is a code-native gradient, not an edited copy of either source image.
var settings: Resource
var grass: StandardMaterial3D
var paving: StandardMaterial3D
var tiles := 0
var terrain_triangles := 0

func _init(config: Resource, original_grass: StandardMaterial3D, original_paving: StandardMaterial3D) -> void:
	settings = config
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.01,0.99])
	gradient.colors = PackedColorArray([Color.BLACK,Color.WHITE])
	var mask := GradientTexture1D.new()
	mask.width = 256
	mask.gradient = gradient
	grass = _detail(original_grass,settings.grass_texture,mask)
	set_grass_scale(settings.grass_repeat_meters)
	paving = _detail(original_paving,settings.paving_texture,mask)

func _detail(original: StandardMaterial3D, texture: Texture2D, mask: Texture2D) -> StandardMaterial3D:
	var result: StandardMaterial3D = original.duplicate()
	result.detail_enabled = true
	result.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	result.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	result.detail_albedo = texture
	result.detail_mask = mask
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.texture_repeat = true
	return result

func set_grass_scale(meters: float) -> void:
	grass.uv2_scale = Vector3(1.0/meters,1.0/meters,1.0)

func intersects_chunk(x: float, z: float, size: float) -> bool:
	var start: Vector2 = settings.region_min-Vector2.ONE*settings.feather_meters
	var finish: Vector2 = settings.region_max+Vector2.ONE*settings.feather_meters
	return x+size>start.x and x<finish.x and z+size>start.y and z<finish.y

func weight_at(p: Vector3) -> float:
	var low: Vector2 = settings.region_min
	var high: Vector2 = settings.region_max
	var feather: float = settings.feather_meters
	if p.x<=low.x-feather or p.x>=high.x+feather or p.z<=low.y-feather or p.z>=high.y+feather: return 0.0
	var center := (low+high)*0.5
	var half := (high-low)*0.5
	# Wavy, feathered edges stay inside the authorized outer adjustment band.
	var edge_x := half.x+feather*(0.4+0.3*sin(p.z*0.17)+0.1*cos(p.z*0.39))
	var edge_z := half.y+feather*(0.4+0.3*sin(p.x*0.27))
	return (1.0-smoothstep(edge_x-feather,edge_x,absf(p.x-center.x)))*(1.0-smoothstep(edge_z-feather,edge_z,absf(p.z-center.y)))

func grass_weight(p: Vector3, normal: Vector3, road: Dictionary) -> float:
	# Terrain's existing road/cliff classification remains the first condition.
	if normal.y<0.90 or road.distance<road.width*0.5: return 0.0
	var shoulder := smoothstep(0.0,1.2,road.distance-road.width*0.5)
	return weight_at(p)*settings.grass_strength*shoulder*smoothstep(0.90,0.97,normal.y)

func mask_uv(weight: float) -> Vector2:
	# Avoid repeat wrapping at exactly UV=1; neither alpha nor a second floor is used.
	return Vector2(lerpf(0.01,0.99,clampf(weight,0,1)),0.5)

func slab_mesh(size: Vector3, p: Vector3, side_material: Material) -> ArrayMesh:
	var source := BoxMesh.new()
	source.size = size
	var arrays := source.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var top := SurfaceTool.new()
	var sides := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var variant := posmod(roundi(p.x*7.0+p.z*11.0),settings.stone_regions.size())
	var region: Rect2 = settings.stone_regions[variant]
	var weight: float = weight_at(p)*settings.paving_strength
	for i in range(0,indices.size(),3):
		var is_top := normals[indices[i]].y>0.99
		var surface := top if is_top else sides
		for j in range(3):
			var index := indices[i+j]
			var vertex := positions[index]
			surface.set_normal(normals[index])
			if is_top:
				surface.set_uv(mask_uv(weight))
				surface.set_uv2(region.position+Vector2(vertex.x/size.x+0.5,vertex.z/size.z+0.5)*region.size)
			else: surface.set_uv(uvs[index])
			surface.add_vertex(vertex)
	var result := top.commit()
	sides.commit(result)
	result.surface_set_material(0,paving)
	result.surface_set_material(1,side_material)
	result.custom_aabb = source.get_aabb()
	tiles += 1
	return result
