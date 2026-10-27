extends CanvasLayer
## Detached, collision-free view projection. Only this defeated body overlays terrain.
const Controller = preload("res://scripts/player/player_controller.gd")
const Flash = preload("res://assets/shaders/defeat_sprite_flash.gdshader")
var settings: Resource
var visual: Resource
var sprite: Sprite2D
var origin := Vector3.ZERO
var hit_direction := Vector3.RIGHT
var facing := Vector3.FORWARD
var world_pixel_size := Vector2.ONE
var elapsed := 0.0
var first_draw := true
var flash_remaining := 0.0
var flash_strength := 0.0
var flash_color := Color.WHITE
var offscreen := false
var finished_once := false
var last_rect := Rect2()
signal finished(reason: String)

func configure(actor: CharacterBody3D, source: Node, value: Resource) -> void:
	settings = value.duplicate()
	visual = actor.settings.visual
	origin = actor.global_position
	facing = actor.facing
	var body: AnimatedSprite3D = actor.get_node("AnimatedSprite3D")
	world_pixel_size = Vector2(body.pixel_size*absf(body.global_basis.get_scale().x),body.pixel_size*absf(body.global_basis.get_scale().y))
	hit_direction = origin-source.global_position if source is Node3D else facing
	if is_instance_valid(source) and source.get("combat") != null and source.combat.get("strike_facing") != null and source.combat.state == source.combat.State.Attack:
		hit_direction = source.combat.strike_facing
	hit_direction.y = 0.0
	if hit_direction.is_zero_approx(): hit_direction = facing
	hit_direction = hit_direction.normalized()
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(body.offset.x,-body.offset.y)
	var material := ShaderMaterial.new()
	material.shader = Flash
	sprite.material = material
	add_child(sprite)
	var feedback: Node = actor.get_node("HitFeedback")
	if feedback.flashes.has(body):
		flash_remaining = feedback.remaining
		flash_strength = feedback.flashes[body].get_shader_parameter("flash_strength")
		flash_color = feedback.flashes[body].get_shader_parameter("flash_color")

func _ready() -> void:
	add_to_group("enemy_defeat_visuals")
	if settings == null or sprite == null or visual == null:
		_finish.call_deferred("unavailable")
		return
	_place()

func _finish(reason: String) -> void:
	if finished_once: return
	finished_once = true
	finished.emit(reason)
	queue_free()

func _exit_distance(at: Vector2, direction: Vector2, bounds: Rect2) -> float:
	var x := INF
	var y := INF
	if absf(direction.x) > 0.0001: x = ((bounds.end.x if direction.x > 0.0 else bounds.position.x)-at.x)/direction.x
	if absf(direction.y) > 0.0001: y = ((bounds.end.y if direction.y > 0.0 else bounds.position.y)-at.y)/direction.y
	return maxf(0.0,minf(x,y)) + 2.0

func _place() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		sprite.hide()
		return # The bounded lifetime also covers missing/removed cameras.
	if camera.is_position_behind(origin):
		offscreen = true
		_finish("offscreen")
		return
	sprite.show()
	var side: String = ["down","right","up","left"][Controller.direction_sector(facing,camera.global_basis,4)]
	var frames: SpriteFrames = visual.idle_frames if visual.idle_frames != null else visual.walk_frames
	var animation := StringName(("idle_" if visual.idle_frames != null else "walk_")+side)
	if frames == null or not frames.has_animation(animation):
		_finish("unavailable")
		return
	sprite.texture = frames.get_frame_texture(animation,0)
	var at := camera.unproject_position(origin)
	var right := camera.unproject_position(origin+camera.global_basis.x)-at
	var up := camera.unproject_position(origin+camera.global_basis.y)-at
	var pixels_per_metre := maxf(0.001,right.length())
	sprite.scale = Vector2(world_pixel_size.x*pixels_per_metre,world_pixel_size.y*up.length())
	var direction := camera.unproject_position(origin+hit_direction)-at
	if direction.length_squared() < 0.001: direction = at-get_viewport().get_visible_rect().get_center()
	if direction.length_squared() < 0.001: direction = Vector2.RIGHT
	direction = direction.normalized()
	var margin := clampf(settings.offscreen_margin_pixels,0.0,128.0)
	var half := sprite.texture.get_size()*sprite.scale*0.5 + sprite.offset.abs()*sprite.scale + Vector2.ONE*margin
	var viewport_rect := get_viewport().get_visible_rect()
	var target_rect := viewport_rect.grow_individual(half.x,half.y,half.x,half.y)
	var duration := clampf(settings.flyoff_duration,0.2,1.5)
	var speed := maxf(clampf(settings.minimum_fly_speed,1.0,60.0)*pixels_per_metre,_exit_distance(at,direction,target_rect)/duration)
	var lift := sin(PI*clampf(elapsed/duration,0.0,1.0))*clampf(settings.lift_height,0.0,3.0)*up.length()
	sprite.position = at + direction*speed*elapsed + Vector2.UP*lift
	var local := sprite.get_rect()
	last_rect = Rect2(sprite.position+local.position*sprite.scale,local.size*sprite.scale)
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("flash_color",flash_color)
	material.set_shader_parameter("flash_strength",flash_strength if flash_remaining > 0.0 else 0.0)
	offscreen = not viewport_rect.grow(margin).intersects(last_rect)
	if offscreen: _finish("offscreen")

func _process(delta: float) -> void:
	if settings == null or finished_once: return
	if first_draw: first_draw = false
	else:
		elapsed += delta
		flash_remaining = maxf(0.0,flash_remaining-delta)
	if elapsed >= maxf(clampf(settings.flyoff_duration,0.2,1.5)+0.1,clampf(settings.maximum_lifetime,0.8,5.0)):
		_finish("timeout")
	else: _place()
