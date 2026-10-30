extends "res://tests/mage_fire_feedback.gd"
## Actual physics-clock commitment/cadence and rendered victim coverage.
var launches: Array[Dictionary] = []
var warning_ticks: Array[int] = []
var result_metrics: Dictionary = {}

func _released(shot: CharacterBody3D) -> void:
	launches.append({"tick":Engine.get_physics_frames(),"direction":shot.direction,"position":shot.global_position})

func _warning() -> void:
	warning_ticks.append(Engine.get_physics_frames())

func _caster() -> void:
	for audio in get_nodes_in_group("projectile_launch_audio"): audio.free()
	await _clear_impacts()
	await _fresh(1,Vector3(5,0,0))
	launches.clear()
	warning_ticks.clear()
	ai.projectile_released.connect(_released)
	ai.attack_warning_started.connect(_warning)

func _coverage(shown: Image, hidden: Image) -> Vector2:
	var visual: AnimatedSprite3D=player.get_node("AnimatedSprite3D")
	var texture: Texture2D=visual.sprite_frames.get_frame_texture(visual.animation,visual.frame)
	var pixels:=texture.get_image()
	var camera: Camera3D=main.get_node("CameraRig").camera
	var changed:=0
	var samples:=0
	for y in range(1,pixels.get_height()-1):
		for x in range(1,pixels.get_width()-1):
			var source:=pixels.get_pixel(x,y)
			if source.a<0.9 or pixels.get_pixel(x-1,y).a<0.9 or pixels.get_pixel(x+1,y).a<0.9: continue
			var local:=Vector2(float(x)+0.5-pixels.get_width()*0.5+visual.offset.x,pixels.get_height()*0.5-float(y)-0.5+visual.offset.y)*visual.pixel_size
			var world:=player.global_position+camera.global_basis.x*local.x+camera.global_basis.y*local.y
			var at:=Vector2i(camera.unproject_position(world))
			if not Rect2i(Vector2i.ZERO,hidden.get_size()).has_point(at): continue
			var base:=hidden.get_pixelv(at)
			if absf(base.r-source.r)+absf(base.g-source.g)+absf(base.b-source.b)>0.04: continue
			samples+=1
			var color:=shown.get_pixelv(at)
			if absf(base.r-color.r)+absf(base.g-color.g)+absf(base.b-color.b)>0.12: changed+=1
	return Vector2(float(changed)/maxi(1,samples),samples)

func _reload_cast() -> void:
	var profile: Resource=load("res://.godot/mage_cast_saved.tres")
	_check(profile.commit_projectile_on_windup and is_equal_approx(profile.recovery_seconds,10.0) and is_equal_approx(profile.minimum_attack_interval,10.0),"Committed cast and ten-second interval survive reload")
	_check(is_equal_approx(profile.magic_visual.hit_effect_scale,0.3) and profile.magic_visual.launch_sound.resource_path.ends_with("mz_fire3.ogg") and is_equal_approx(profile.magic_visual.launch_pitch_scale,1.0),"Large impact and Fire3 settings survive reload")
	print("MAGE CAST RELOAD ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		_reload_cast()
		return
	Engine.max_fps=30 if "--fps30" in OS.get_cmdline_user_args() else 60
	root.size=Vector2i(1152,720)
	main=preload("res://tests/fixtures/combat_scene.gd").create()
	root.add_child(main)
	player=main.get_node("Player")
	combat=player.combat
	sprite=player.get_node("AnimatedSprite3D")
	health=player.get_node("HealthComponent")
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"): child.position=Vector3(12,0,10)
	await _ticks(4)
	_check(FileAccess.get_sha256("res://assets/audio/sfx/mz_fire3.ogg")==FileAccess.get_sha256("res://RPGツクールMZのaudio/se/Fire3.ogg"),"Fire3 is the unchanged selected SE")
	for distance in [7.0,11.0]:
		await _caster()
		await _windup()
		_check(ai.get_node("CastingCircle").is_presenting() and get_nodes_in_group("projectile_launch_audio").is_empty(),"Magic circle precedes the release, with no premature Fire3")
		player.reset_motion(ai.global_position+Vector3.LEFT*distance)
		await _state(ai.State.ATTACK)
		_check(launches.size()==1 and ai.shots.size()==1 and is_instance_valid(ai.shots[0]),"Committed warning releases outside start range / leash: "+str(distance))
		if not launches.is_empty():
			var toward: Vector3=(player.global_position+Vector3.UP*0.9-launches[0].position).normalized()
			_check(launches[0].direction.dot(toward)>0.999,"Release aims at actual current position without increasing projectile range")
		var sounds:=get_nodes_in_group("projectile_launch_audio")
		_check(sounds.size()==1,"Exactly one launch audio per generated projectile")
		if sounds.size()==1:
			var audio: AudioStreamPlayer=sounds[0]
			_check(audio.playing and audio.stream.resource_path.ends_with("mz_fire3.ogg") and is_equal_approx(audio.pitch_scale,1.0),"Actual launch plays Fire3 at normal pitch")
			ai.health.damage(100,player)
			_check(is_instance_valid(audio) and audio.playing,"Caster death / bolt removal does not truncate Fire3")
			await _seconds(audio.stream.get_length()+0.1)
			_check(not is_instance_valid(audio),"Completed launch audio cleans itself up")
	# A target that was never in range must not start the warning at all.
	await _caster()
	player.reset_motion(ai.global_position+Vector3.LEFT*7.0)
	ai.settings.chase_speed=0.0
	ai._set_state(ai.State.CHASE)
	ai.set_physics_process(true)
	await _seconds(0.3)
	_check(warning_ticks.is_empty() and launches.is_empty(),"Commitment never expands the six-meter start eligibility")
	# A sight-blocking wall still cancels; no Fire3 on an ungenerated bolt.
	await _caster()
	await _windup()
	var wall:=_block((ai.global_position+player.global_position)*0.5+Vector3.UP,Vector3(0.2,2.0,3.0))
	await _seconds(1.1)
	_check(launches.is_empty() and get_nodes_in_group("projectile_launch_audio").is_empty(),"Occlusion does not create wall-through releases or false Fire3")
	wall.free()
	await _caster()
	await _windup()
	health.damage(1000,ai)
	await _seconds(1.1)
	_check(launches.is_empty() and get_nodes_in_group("projectile_launch_audio").is_empty(),"Player death cancels the pending release")
	# The actual ten-second recovery is measured with the physics clock.
	await _caster()
	await _windup()
	await _state(ai.State.ATTACK)
	ai.clear_shots()
	await _state(ai.State.RECOVERY)
	var end_tick:=Engine.get_physics_frames()
	while float(Engine.get_physics_frames()-end_tick)/60.0<9.8:
		await _ticks(1)
	_check(warning_ticks.size()==1 and launches.size()==1,"No second warning or shot during the first 9.8 seconds after attack end")
	await _state(ai.State.WINDUP,80)
	var wait_time:=float(warning_ticks[-1]-end_tick)/60.0
	_check(absf(wait_time-10.0)<0.08,"Next warning begins ten seconds after attack end: "+str(wait_time))
	await _state(ai.State.ATTACK)
	var shot_interval:=float(launches[-1].tick-launches[0].tick)/60.0
	_check(launches.size()==2 and shot_interval>=11.0,"One warning and one new projectile after recovery; no rapid repeat")
	result_metrics["recovery_seconds"]=wait_time
	result_metrics["shot_interval"]=shot_interval
	# Retain single-projectile cap and avoid a launch cue on a suppressed spawn.
	await _caster()
	var held:=_shot(origin+Vector3(2,3,0),Vector3.UP,0.0)
	await _windup()
	await _state(ai.State.ATTACK)
	_check(is_instance_valid(held) and launches.is_empty() and get_nodes_in_group("projectile_launch_audio").is_empty(),"Existing live projectile cap suppresses both another bolt and Fire3")
	ai.clear_shots()
	# Render original FireOne1 at the new size over normal and held-guard bodies.
	for guarding in [false,true]:
		await _caster()
		if guarding:
			_press("guard",true)
			await _phase(combat.State.Guard)
			player.facing_world=Vector3.RIGHT
		_shot(origin+Vector3(0.7,0.9,0),Vector3.LEFT,30.0)
		await _ticks(4)
		var effects:=get_nodes_in_group("fire_hit_presentations")
		_check(effects.size()==1,"Real hit starts one large fire effect")
		if effects.size()!=1: continue
		var effect: Node3D=effects[0]
		_check(is_equal_approx(effect.emitter.scale.x,0.3) and is_equal_approx(effect.config.hit_effect_scale,0.3),"Mage impact is five times the previous native scale; collision is unchanged")
		var best:=0.0
		var best_samples:=0
		for sample in range(5):
			await _seconds(0.25 if sample==0 else 0.15)
			effect.emitter.paused=true
			await _ticks(2)
			var shown:=await _image()
			effect.emitter.hide()
			await _ticks(2)
			var hidden:=await _image()
			var covered:=_coverage(shown,hidden)
			if covered.x>best:
				best=covered.x
				best_samples=int(covered.y)
				shown.save_png("res://.godot/mage_large_impact_guard_%s.png" % str(guarding))
			effect.emitter.show()
			effect.emitter.paused=false
		_check(best>=0.7 and best_samples>30,"Flames obscure most of the visible protagonist; Guard=%s coverage=%s" %[guarding,best])
		result_metrics["coverage_guard_"+str(guarding)]={"fraction":best,"samples":best_samples}
		if guarding: _press("guard",false)
	_check(ResourceSaver.save(ai.settings.attack,"res://.godot/mage_cast_saved.tres")==OK,"Commitment, cadence, Fire3 and enlarged impact save")
	FileAccess.open("res://.godot/mage_cast_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(result_metrics,"  "))
	main.queue_free()
	await _ticks(4)
	for failure in failures: push_error(failure)
	print("MAGE CAST %s: %d assertions; fps cap=%d; metrics=%s" %["PASS" if failures.is_empty() else "FAIL",assertions,Engine.max_fps,result_metrics])
	quit(0 if failures.is_empty() else 1)
