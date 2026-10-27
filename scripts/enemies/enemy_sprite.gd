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
	actor.attack_warning_started.connect(_process.bind(0.0))
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
	var warning: bool = actor.state == actor.State.WINDUP
	var posed: bool = attacking or warning
	var moving: bool = actor.velocity.length_squared() > 0.0001
	if actor.state in [actor.State.DASH_APPROACH, actor.State.DASH_RETURN]:
		var destination: Vector3 = actor.dash_destination if actor.state == actor.State.DASH_APPROACH else actor.attack_anchor
		moving = actor.global_position.distance_to(destination) > 0.001 and not actor.locomotion_held()
	var idle: bool = not posed and not moving and visual.idle_frames != null
	var frames: SpriteFrames = visual.attack_frames if posed else (visual.idle_frames if idle else visual.walk_frames)
	var family := "attack_" if posed else ("idle_" if idle else "walk_")
	if warning and visual.warning_frames != null:
		frames = visual.warning_frames
		family = "warning_"
	var next := StringName(family + side)
	if frames == null or not frames.has_animation(next): return
	if sprite_frames != frames: sprite_frames = frames
	if animation != next: animation = next
	speed_scale = maxf(0.1, visual.idle_fps) / maxf(0.001, frames.get_animation_speed(next)) if idle else 1.0
	if attacking:
		stop()
		var sampled := Motion.sample(Motion.weights(frames, next, attack_ratios()), attack_phase())
		set_frame_and_progress(int(sampled.x), sampled.y)
	elif not posed and actor.state != actor.State.DEAD and (moving or (idle and frames.get_frame_count(next) > 1)):
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
