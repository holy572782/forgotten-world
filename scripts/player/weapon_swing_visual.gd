extends Sprite3D
## Texture-only presentation. Damage remains on TargetDash's existing hit frame.
@onready var body: CharacterBody3D = get_parent()
@onready var action_sprite: AnimatedSprite3D = body.get_node("AnimatedSprite3D")

func _ready() -> void:
	visible = false
	process_priority = 10 # After body/damage presentation, including guard interruption.
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	visible = false
	var combat: Node = body.combat
	if not is_instance_valid(combat) or combat.state != combat.State.Attack: return
	if not action_sprite._attacking or not action_sprite.visible: return
	var weapon: WeaponData = combat._active_weapon
	if weapon == null or weapon.swing_texture == null: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	texture = weapon.swing_texture
	pixel_size = weapon.swing_pixel_size
	offset = Vector2(texture.get_width()*0.5-weapon.swing_grip_pixel.x,weapon.swing_grip_pixel.y-texture.get_height()*0.5)
	var total := action_sprite.sprite_frames.get_frame_count(action_sprite.animation)
	var progress := clampf((action_sprite.frame+action_sprite.frame_progress)/float(total),0.0,1.0)
	var half_angle := deg_to_rad(clampf(weapon.sweep_angle_degrees,1.0,180.0)*0.5)
	var direction: Vector3 = combat.strike_facing.rotated(Vector3.UP,lerpf(-half_angle,half_angle,progress))
	# The hand follows the world-space swing; the unmodified 16px blade faces camera.
	global_position = body.global_position + Vector3.UP*0.95 + direction*0.35
	var in_view := Vector2(direction.dot(camera.global_basis.x),direction.dot(camera.global_basis.y))
	var blade_direction := Vector2(-weapon.swing_grip_pixel.x,weapon.swing_grip_pixel.y).angle()
	global_basis = camera.global_basis * Basis(Vector3.BACK,in_view.angle()-blade_direction)
	visible = true
