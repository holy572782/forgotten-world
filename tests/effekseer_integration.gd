extends SceneTree
## Run with a real renderer: native playback and rendered output are both checked.

var failures: Array[String] = []
var checks: int = 0
var finished_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(960, 600)
	_check(ClassDB.class_exists("EffekseerEmitter3D"), "3D emitter is registered")
	_check(ClassDB.class_exists("EffekseerEmitter2D"), "2D emitter is registered")
	_check(Engine.has_singleton("EffekseerSystem"), "Effekseer runtime singleton is registered")
	_check("res://addons/effekseer/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled"), "import/editor plugin enabled")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "existing renderer retained")
	if not failures.is_empty():
		quit(1)
		return
	var scene: Node3D = load("res://scenes/tests/effekseer_preview.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("ReplayTimer").stop()
	var emitter: EffekseerEmitter3D = scene.get_node("Emitter")
	_check(emitter.effect != null, "efkefc imported as EffekseerEffect")
	_check(not emitter.effect.get_subresources().is_empty(), "texture dependency imported")
	_check(emitter.is_playing(), "autoplay starts the effect")
	emitter.finished.connect(func(): finished_count += 1)
	emitter.stop()
	await _frames(4)
	_check(not emitter.is_playing(), "stop ends playback")
	await RenderingServer.frame_post_draw
	var baseline: Image = root.get_texture().get_image()
	scene.replay()
	await create_timer(0.6).timeout
	_check(emitter.is_playing(), "replay starts native effect")
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	var changed := 0
	# Ignore the fixed instruction panel; require particles in the scene area.
	for y in range(160, rendered.get_height(), 2):
		for x in range(0, rendered.get_width(), 2):
			var a := baseline.get_pixel(x, y)
			var b := rendered.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
				changed += 1
	_check(changed > 20, "particles visibly render in Compatibility (changed samples: %d)" % changed)
	rendered.save_png("res://.godot/effekseer_preview.png")
	var deadline := Time.get_ticks_msec() + 10000
	while emitter.is_playing() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not emitter.is_playing() and finished_count == 1, "natural completion emits finished once")
	var transient := EffekseerEmitter3D.new()
	transient.effect = emitter.effect
	transient.autofree = true
	scene.add_child(transient)
	var weak: WeakRef = weakref(transient)
	deadline = Time.get_ticks_msec() + 10000
	while weak.get_ref() != null and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(weak.get_ref() == null, "autofree releases a completed emitter")
	scene.queue_free()
	await _frames(4)
	print("Effekseer integration: %s (%d checks, changed samples %d)" % ["PASS" if failures.is_empty() else "FAIL", checks, changed])
	quit(0 if failures.is_empty() else 1)
