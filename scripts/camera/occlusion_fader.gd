extends RefCounted
## Owns temporary, per-instance material overrides. Never edits shared resources.
var entries: Dictionary = {}
var unsupported: Dictionary = {}

func update(space: PhysicsDirectSpaceState3D, eye: Vector3, feet: Vector3, settings: Resource, excluded: Array[RID], delta: float) -> void:
	var visible_blockers: Dictionary = {}
	for height in settings.occlusion_heights:
		var ray := PhysicsRayQueryParameters3D.create(eye, feet + Vector3.UP * height, settings.terrain_mask, excluded.duplicate())
		ray.hit_from_inside = true
		# Excluding each hit body discovers multiple walls on the same sightline.
		for index in range(settings.max_occluders_per_ray):
			var hit := space.intersect_ray(ray)
			if hit.is_empty(): break
			_collect_meshes(hit.collider, visible_blockers)
			var omit := ray.exclude
			omit.append(hit.rid)
			ray.exclude = omit
	for id in visible_blockers:
		if not entries.has(id): _begin(visible_blockers[id])
		if entries.has(id): entries[id].hold = settings.occlusion_release_delay
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		var mesh: MeshInstance3D = entry.ref.get_ref()
		if not is_instance_valid(mesh):
			entries.erase(id)
			continue
		var blocked := visible_blockers.has(id)
		if not blocked: entry.hold = maxf(0.0, entry.hold - delta)
		var goal: float = settings.occluded_opacity if blocked or entry.hold > 0 else 1.0
		entry.opacity = move_toward(entry.opacity, goal, (1.0 - settings.occluded_opacity) * delta / maxf(settings.fade_time, 0.001))
		for i in range(entry.materials.size()):
			var material: BaseMaterial3D = entry.materials[i]
			material.albedo_color.a = entry.alphas[i] * entry.opacity
		if is_equal_approx(entry.opacity, 1.0) and not blocked and entry.hold <= 0:
			_restore(id)

func _collect_meshes(node: Node, found: Dictionary) -> void:
	if node.is_in_group("camera_occlusion_exempt"): return
	if node is MeshInstance3D and node.is_visible_in_tree(): found[node.get_instance_id()] = node
	for child in node.get_children():
		# Do not fade an independently owned nested physics body.
		if not child is CollisionObject3D: _collect_meshes(child, found)

func _begin(mesh: MeshInstance3D) -> void:
	if not mesh.mesh: return
	if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: return
	var id := mesh.get_instance_id()
	if unsupported.has(id): return
	var materials: Array[BaseMaterial3D] = []
	var originals: Array[Material] = []
	var alphas: Array[float] = []
	for surface in range(mesh.mesh.get_surface_count()):
		var source := mesh.get_active_material(surface)
		if source != null and (not source is BaseMaterial3D or source.next_pass != null):
			unsupported[id] = true
			push_warning("Camera fade requires BaseMaterial3D without next_pass: " + str(mesh.get_path()))
			return
		var copy: BaseMaterial3D = source.duplicate() if source else StandardMaterial3D.new()
		alphas.append(copy.albedo_color.a)
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		materials.append(copy)
		originals.append(mesh.get_surface_override_material(surface))
	var shadow_proxy := _make_shadow_proxy(mesh)
	# Retain materials until after the helper's rendering instance is freed.
	var shadow_materials: Array[Material] = []
	if shadow_proxy:
		for surface in range(mesh.mesh.get_surface_count()):
			shadow_materials.append(shadow_proxy.get_active_material(surface))
	entries[id] = {"ref": weakref(mesh), "override": mesh.material_override, "originals": originals, "materials": materials, "alphas": alphas, "shadow": mesh.cast_shadow, "shadow_proxy": shadow_proxy, "shadow_materials": shadow_materials, "opacity": 1.0, "hold": 0.0}
	mesh.material_override = null
	for surface in range(materials.size()): mesh.set_surface_override_material(surface, materials[surface])
	# The original materials cast unchanged shadows through the separate proxy.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _make_shadow_proxy(source: MeshInstance3D) -> MeshInstance3D:
	if source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return null
	var proxy := MeshInstance3D.new()
	proxy.name = "OcclusionShadow"
	proxy.mesh = source.mesh
	proxy.layers = source.layers
	proxy.extra_cull_margin = source.extra_cull_margin
	proxy.custom_aabb = source.custom_aabb
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Exclude the helper from future occlusion collection; it has no collision.
	proxy.add_to_group("camera_occlusion_exempt")
	for surface in range(source.mesh.get_surface_count()):
		var material := source.get_active_material(surface)
		if source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			material = material.duplicate() if material else StandardMaterial3D.new()
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		proxy.set_surface_override_material(surface, material)
	# Identity child transform follows the original mesh, including parent rotation.
	source.add_child(proxy)
	return proxy

func _restore(id: int) -> void:
	var entry: Dictionary = entries[id]
	if is_instance_valid(entry.shadow_proxy): entry.shadow_proxy.free()
	var mesh: MeshInstance3D = entry.ref.get_ref()
	if is_instance_valid(mesh):
		mesh.material_override = entry.override
		for surface in range(entry.originals.size()): mesh.set_surface_override_material(surface, entry.originals[surface])
		mesh.cast_shadow = entry.shadow
	entries.erase(id)

func restore_all() -> void:
	for id in entries.keys(): _restore(id)
	unsupported.clear()
