extends AnimatedSprite3D
## Read the existing enemy state/elapsed time; never drive AI or damage.
const Controller = preload("res://scripts/player/player_controller.gd")
const Motion = preload("res://scripts/combat/attack_motion_settings.gd")
const Depth = preload("res://assets/shaders/player_depth.gdshader")
const SIDES := ["down", "right", "up", "left"]
@onready var actor: CharacterBody3D = get_parent()
var visual: Resource

func _ready() -> void:
	visual = actor.settings.visual
	if visual == null:
		hide()
		set_process(false)
		return # Custom legacy fixtures can retain their capsule presentation.
	actor.get_node("Body").hide()
	pixel_size = visual.pixel_size
	offset = visual.sprite_offset
	var material := ShaderMaterial.new()
	material.shader = Depth
	var capsule: CapsuleShape3D = actor.get_node("CollisionShape3D").shape
	material.set_shader_parameter("body_radius", capsule.radius)
	material.set_shader_parameter("body_height", capsule.height)
	material_override = material
	_process(0.0)

func attack_phase() -> float:
	var duration: float = maxf(0.001, maxf(actor.active_attack.attack_seconds, actor.active_attack.hit_delay_seconds))
	return clampf(actor.elapsed / duration, 0.0, 1.0)

func attack_ratios() -> PackedFloat32Array:
	return actor.active_attack.weapon.motion.frame_time_ratios if actor.active_attack != null and actor.active_attack.weapon != null else PackedFloat32Array()

func _process(_delta: float) -> void:
	if visual == null or actor.active_attack == null: return
	var camera := get_viewport().get_camera_3d()
	var basis := camera.global_basis if camera != null else Basis.IDENTITY
	var side: String = SIDES[Controller.direction_sector(actor.facing, basis, 4)]
	var attacking: bool = actor.state == actor.State.ATTACK
	var posed: bool = attacking or actor.state in [actor.State.WINDUP, actor.State.DASH_APPROACH]
	var frames: SpriteFrames = visual.attack_frames if posed else visual.walk_frames
	var next := StringName(("attack_" if posed else "walk_") + side)
	if frames == null or not frames.has_animation(next): return
	if sprite_frames != frames: sprite_frames = frames
	if animation != next: animation = next
	if attacking:
		stop()
		var sampled := Motion.sample(Motion.weights(frames, next, attack_ratios()), attack_phase())
		set_frame_and_progress(int(sampled.x), sampled.y)
	elif not posed and actor.state != actor.State.DEAD and actor.velocity.length_squared() > 0.0001:
		play()
	else:
		stop()
		frame = 0
	var atlas := frames.get_frame_texture(animation, frame) as AtlasTexture
	material_override.set_shader_parameter("sprite_sheet", atlas.atlas)
	# No death sheet was supplied: hold the idle image at its foot pivot.
	# AI/HP/collision death handling remains owned by the existing enemy.
	var shadow: AnimatedSprite3D = $Shadow
	shadow.sprite_frames = frames
	shadow.animation = animation
	shadow.set_frame_and_progress(frame, frame_progress)
	shadow.pixel_size = pixel_size
	shadow.offset = offset
