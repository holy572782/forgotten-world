extends AnimatedSprite3D
const AttachmentDepth = preload("res://assets/shaders/actor_attachment_depth.gdshader")
## One animation clock: mirror the body's frame and sub-frame progress.
## No combat callbacks or independent timer. Texture canvas size never sets scale.
@onready var body: CharacterBody3D = get_parent()
@onready var action_sprite: AnimatedSprite3D = body.get_node("AnimatedSprite3D")

func _ready() -> void:
	visible = false
	process_priority = 10 # After body/damage presentation, including guard interruption.
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var depth_material := ShaderMaterial.new()
	depth_material.shader = AttachmentDepth
	var capsule: CapsuleShape3D = body.get_node("CollisionShape3D").shape
	depth_material.set_shader_parameter("body_radius",capsule.radius)
	depth_material.set_shader_parameter("body_height",capsule.height)
	material_override = depth_material
	action_sprite.attack_started.connect(_sync_from_body)
	action_sprite.frame_changed.connect(_sync_from_body)
	action_sprite.animation_changed.connect(_sync_from_body)
	action_sprite.attack_completed.connect(hide)

func _process(_delta: float) -> void:
	_sync_from_body()
	if visible: update_depth_occlusion()

func update_depth_occlusion() -> void:
	var camera := get_viewport().get_camera_3d()
	var blocked := false
	if camera != null:
		# Terrain only: a nearby enemy must occlude its own pixels, not the
		# entire blade. Respect the existing camera's transparent wall materials.
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position,body.global_position+Vector3.UP*0.015,1,[body.get_rid()])
		ray.hit_from_inside = true
		for index in range(16):
			var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): break
			var collider: Node3D = hit.collider
			var source: Node = collider.get_parent() if collider.get_parent() is MeshInstance3D else collider
			if collider.is_visible_in_tree() and _has_opaque_mesh(source):
				blocked = true
				break
			var excluded := ray.exclude
			excluded.append(hit.rid)
			ray.exclude = excluded
	material_override.set_shader_parameter("owner_floor_occluded",blocked)

func _has_opaque_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.is_visible_in_tree() and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var surface_material: Material = node.get_active_material(surface)
			if not surface_material is BaseMaterial3D or surface_material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or surface_material.albedo_color.a >= 0.999: return true
	for child in node.get_children():
		if not child is CollisionObject3D and _has_opaque_mesh(child): return true
	return false

func _sync_from_body() -> void:
	visible = false
	var combat: Node = body.combat
	if not is_instance_valid(combat) or combat.state != combat.State.Attack: return
	if not action_sprite._attacking or not action_sprite.visible: return
	var weapon: WeaponData = combat._active_weapon
	if weapon == null or weapon.attack_visual == null or not weapon.attack_visual.is_valid(): return
	var visual := weapon.attack_visual
	var next := action_sprite.animation
	if not String(next).begins_with("attack_") or not visual.attack_frames.has_animation(next): return
	if action_sprite.frame < 0 or action_sprite.frame >= visual.attack_frames.get_frame_count(next): return
	if sprite_frames != visual.attack_frames: sprite_frames = visual.attack_frames
	animation = next
	stop() # The body owns animation timing; never advance a second timer.
	set_frame_and_progress(action_sprite.frame,action_sprite.frame_progress)
	transform = action_sprite.transform
	billboard = action_sprite.billboard
	pixel_size = action_sprite.pixel_size
	offset = action_sprite.offset + visual.direction_offset(String(next).get_slice("_",1))
	var atlas := sprite_frames.get_frame_texture(animation,frame) as AtlasTexture
	material_override.set_shader_parameter("sprite_sheet",atlas.atlas)
	visible = true
