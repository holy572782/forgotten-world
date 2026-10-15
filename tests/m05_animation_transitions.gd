extends SceneTree
## Exhaust every authored source frame, including walk slot 3 -> shorter actions.
var failures: Array[String] = []
var invalid_transition_windows := 0
var transitions := 0
var sprite: AnimatedSprite3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	sprite = player.get_node("AnimatedSprite3D")
	sprite.set_process(false)
	sprite.stop()
	sprite.animation_changed.connect(_observe_transition)
	var animations := sprite.sprite_frames.get_animation_names()
	for source in animations:
		for slot in range(sprite.sprite_frames.get_frame_count(source)):
			for target in animations:
				sprite._select_animation(source)
				sprite.set_frame_and_progress(slot, 0.4)
				sprite._select_animation(target)
				var same_family: bool = String(source).get_slice("_", 0) == String(target).get_slice("_", 0)
				_check(sprite.frame == (slot if same_family else 0), "Transition frame/phase policy")
				_check_synced()
				transitions += 1
	# Exercise the actual jump selection and attack-start play() path separately.
	for source in [&"walk_down", &"walk_left", &"walk_right", &"walk_up"]:
		for slot in range(4):
			sprite._select_animation(source)
			sprite.set_frame_and_progress(slot, 0.4)
			player.velocity.y = 7.0
			sprite._process(0.0)
			_check(sprite.state == &"Jump" and sprite.frame == 0, "Walk slot -> actual jump")
			_check_synced()
			player.velocity.y = -1.0
			sprite._process(0.0)
			_check(sprite.state == &"Fall" and sprite.frame == 1, "Actual fall")
			_check_synced()
			for facing in [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
				sprite._select_animation(source)
				sprite.set_frame_and_progress(slot, 0.4)
				player.facing_world = facing
				_check(sprite.request_attack_preview(), "Walk slot -> actual attack accepted")
				_check(sprite.frame == 0, "Attack starts at first frame")
				_check_synced()
				sprite.pause()
				sprite._on_animation_finished()
				_check(sprite.state == &"Fall", "Attack returns to airborne state")
				_check_synced()
	_check(invalid_transition_windows > 0, "Reproduces Godot's transient out-of-range notification")
	print("TRANSITIONS=", transitions, " TRANSIENT_WINDOWS=", invalid_transition_windows)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS M05 frame transitions: all source slots/targets, transient guard, jump/fall, attack start/return, sheet and shadow sync")
	player.free()
	quit(0 if failures.is_empty() else 1)

func _observe_transition() -> void:
	if sprite.frame >= sprite.sprite_frames.get_frame_count(sprite.animation):
		invalid_transition_windows += 1
		_check(sprite.get_node("Shadow").animation != sprite.animation, "Do not publish transient invalid frame to shadow")

func _check_synced() -> void:
	var texture: AtlasTexture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_check(texture != null, "Final texture exists")
	if texture == null: return
	_check(sprite.material_override.get_shader_parameter("sprite_sheet") == texture.atlas, "Final shader sheet matches")
	_check(sprite.get_node("Shadow").animation == sprite.animation and sprite.get_node("Shadow").frame == sprite.frame, "Final shadow animation/frame matches")

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
