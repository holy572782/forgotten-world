extends AnimatedSprite3D
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
	action_sprite.attack_started.connect(_sync_from_body)
	action_sprite.frame_changed.connect(_sync_from_body)
	action_sprite.animation_changed.connect(_sync_from_body)
	action_sprite.attack_completed.connect(hide)

func _process(_delta: float) -> void:
	_sync_from_body()

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
	visible = true
