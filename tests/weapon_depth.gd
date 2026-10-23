extends SceneTree
## Frozen production sprites in a minimal 3D render fixture. No simulated hit claims.
class DisplayCombat extends Node:
	enum State { Idle, Attack, Guard }
	var state := State.Attack
	var _active_weapon: WeaponData = preload("res://resources/weapons/one_handed_sword.tres")
	func is_busy() -> bool:
		return state != State.Idle

var failures: Array[String] = []
var world: Node3D
var player: CharacterBody3D
var sprite: AnimatedSprite3D
var sword: AnimatedSprite3D
var camera: Camera3D
var ground: MeshInstance3D
var blocker: MeshInstance3D
var material: Material
var metrics: Array[Dictionary] = []
var assertions := 0
var effect_fixture := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)

func _box(size: Vector3, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = Color(0.2,0.38,0.4)
	node.material_override = surface
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(node)
	node.position = at
	return node

func _image() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _mask(label: String = "") -> Dictionary:
	sword.set_process(false)
	if sword.material_override == material: sword.update_depth_occlusion()
	sword.visible = false
	var absent := await _image()
	sword.visible = true
	var present := await _image()
	var before := absent.get_data()
	var after := present.get_data()
	var mask: Dictionary = {}
	var stride := 4 if present.get_format() == Image.FORMAT_RGBA8 else 3
	for pixel in range(present.get_width()*present.get_height()):
		var index := pixel*stride
		if before[index] != after[index] or before[index+1] != after[index+1] or before[index+2] != after[index+2]: mask[pixel] = true
	if not label.is_empty() and "--capture" in OS.get_cmdline_user_args():
		present.save_png("res://.godot/"+("effect_depth_" if effect_fixture else "weapon_depth_")+label+".png")
	return mask

func _pose(side: String, index: int) -> void:
	sword.material_override = material
	sword.set_process(true)
	sprite.animation = StringName("attack_"+side)
	sprite.set_frame_and_progress(index,0.5)
	sword._sync_from_body()
	sword.set_process(false)

func _run() -> void:
	root.size = Vector2i(960,720)
	Engine.max_fps = 60
	world = Node3D.new()
	root.add_child(world)
	ground = _box(Vector3(30,0.2,30),Vector3(0,-0.1,0))
	blocker = _box(Vector3(10,5,0.3),Vector3(0,1.8,3))
	blocker.material_override.albedo_color = Color(0.6,0.2,0.15)
	blocker.hide()
	player = load("res://scenes/player/player.tscn").instantiate()
	player.set_physics_process(false)
	world.add_child(player)
	player.set_physics_process(false) # Script auto-processing is registered on tree entry.
	var combat := DisplayCombat.new()
	player.add_child(combat)
	player.combat = combat
	sprite = player.get_node("AnimatedSprite3D")
	sprite.set_process(false)
	sprite.stop()
	sprite._attacking = true
	sprite.get_node("Shadow").hide()
	effect_fixture = "--effect" in OS.get_cmdline_user_args()
	combat._active_weapon = combat._active_weapon.duplicate()
	combat._active_weapon.attack_visual = combat._active_weapon.attack_visual.duplicate()
	if effect_fixture: combat._active_weapon.attack_visual.attack_frames = null
	else:
		combat._active_weapon.attack_visual.weapon_effect = null
		combat._active_weapon.attack_visual.slash_effect = null
	sword = player.get_node("SlashEffect" if effect_fixture else "WeaponSwing")
	for node_name in ["WeaponSwing","WeaponEffect","SlashEffect"]:
		var attachment := player.get_node(node_name)
		if attachment != sword:
			attachment.set_process(false)
			attachment.hide() # Isolate the tested layer in difference masks.
	material = sword.material_override
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,6,8)
	camera.look_at(Vector3(0,0.9,0))
	camera.current = true
	var diagnose := "--diagnose" in OS.get_cmdline_user_args()
	for side in ["down","left","right","up"]:
		if "--quick" in OS.get_cmdline_user_args() and side != "down": continue
		for frame in range(3):
			if "--quick" in OS.get_cmdline_user_args() and frame != 0: continue
			_pose(side,frame)
			if side == "down" and frame == 0:
				print("SETTINGS ",{"body_position":sprite.global_position,"sword_position":sword.global_position,"parent":str(sword.get_parent().get_path()),"billboard":sword.billboard,"pixel_size":sword.pixel_size,"scale":sword.scale,"offset":sword.offset,"alpha_cut":sword.alpha_cut,"render_priority":sword.render_priority,"no_depth_test":sword.no_depth_test})
			sword.material_override = material
			sword.no_depth_test = false
			ground.hide()
			var reference := await _mask("reference_"+side+str(frame))
			ground.show()
			var fixed := await _mask("fixed_"+side+str(frame))
			sword.material_override = null
			var legacy := await _mask("legacy_"+side+str(frame) if diagnose else "")
			metrics.append({"side":side,"frame":frame,"reference":reference.size(),"fixed":fixed.size(),"legacy":legacy.size()})
			if not diagnose:
				_check(reference.size() > 10,"Reference blade exists "+side+str(frame))
				_check(fixed == reference,"Floor retains complete blade silhouette "+side+str(frame)+": "+str(fixed.size())+"/"+str(reference.size()))
	# Deliberate diagnostic only. Always restore depth testing/material afterwards.
	_pose("down",1) # Revised sheet's lower-right pose (formerly column zero).
	blocker.show()
	sword.material_override = null
	sword.no_depth_test = true
	var through_wall := await _mask("diagnostic_no_depth")
	sword.no_depth_test = false
	sword.material_override = material
	var hidden := await _mask("opaque_wall")
	if not diagnose:
		_check(through_wall.size() > 10,"No-depth diagnostic reproduces wall leak")
		_check(hidden.is_empty(),"Opaque foreground wall hides entire sword")
	blocker.hide()
	if not diagnose:
		# A close wall does not cover the below-feet canvas on screen. The terrain
		# ray must still prevent a blade appearing on the ground in front of it.
		blocker.position = Vector3(0,1.8,0.35)
		var solid := StaticBody3D.new()
		solid.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = blocker.mesh.size
		shape.shape = box_shape
		solid.add_child(shape)
		blocker.add_child(solid)
		blocker.show()
		await physics_frame
		await physics_frame
		var close_wall := await _mask("close_wall")
		_check(close_wall.is_empty(),"Close terrain wall prevents lower-canvas floor leakage")
		blocker.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blocker.material_override.albedo_color.a = 0.3
		var faded_wall := await _mask("faded_wall")
		_check(not sword.material_override.get_shader_parameter("owner_floor_occluded") and faded_wall.size() > 10,"Existing transparent wall treatment keeps sword visible")
		blocker.material_override.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		blocker.material_override.albedo_color.a = 1.0
		blocker.hide()
		solid.free()
		# A wall covering only the blade must still clip it, even with owner visible.
		blocker.mesh = blocker.mesh.duplicate()
		blocker.mesh.size = Vector3(0.5,3,0.2)
		blocker.position = Vector3(0.75,1.5,3)
		var clear := await _mask()
		blocker.show()
		var partial := await _mask("partial_wall")
		print("PARTIAL clear=",clear.size()," wall=",partial.size())
		_check(partial.size() > 0 and partial.size() < clear.size(),"Side wall occludes only overlapping blade pixels")
		blocker.hide()
		# Foreground and background opaque enemy geometry follow world depth.
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.45
		capsule.height = 2.5
		blocker.mesh = capsule
		blocker.position = Vector3(0.75,1.25,2.5)
		blocker.show()
		var front := await _mask("enemy_front")
		blocker.position = Vector3(0,1.25,1.2)
		var centre_front := await _mask("enemy_centre_front")
		blocker.position = Vector3(0.75,1.25,-2.5)
		var back := await _mask("enemy_back")
		print("ENEMY clear=",clear.size()," front=",front.size()," back=",back.size())
		_check(front.size() < clear.size(),"Nearer enemy occludes overlapping blade")
		_check(centre_front == clear,"Enemy covering owner feet cannot hide non-overlapping blade")
		_check(back == clear,"Farther enemy cannot hide blade behind it")
		blocker.hide()
		# Raised floor, cliff overhang and camera orbit retain the same silhouette.
		for yaw in [0.0,90.0,180.0,270.0]:
			player.position.y = 0.6
			ground.position.y = 0.5
			camera.position = Vector3(0,6.6,8).rotated(Vector3.UP,deg_to_rad(yaw))
			camera.look_at(Vector3(0,1.5,0))
			_pose("down",1)
			ground.hide()
			var above_void := await _mask()
			ground.show()
			var on_step := await _mask("raised_"+str(int(yaw)))
			ground.mesh = ground.mesh.duplicate()
			ground.mesh.size = Vector3(2,0.2,2)
			var on_edge := await _mask("edge_"+str(int(yaw)))
			ground.mesh.size = Vector3(30,0.2,30)
			_check(above_void.size() > 10 and on_step == above_void and on_edge == above_void,"Raised floor/cliff silhouette yaw="+str(yaw))
		_check(not sword.no_depth_test and sword.material_override == material,"Depth diagnostic fully restored")
	FileAccess.open("res://.godot/"+("effect_depth_metrics.json" if effect_fixture else "weapon_depth_metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print(JSON.stringify(metrics))
	print("WALL diagnostic=",through_wall.size()," final=",hidden.size())
	if failures.is_empty(): print("WEAPON DEPTH ","DIAGNOSE" if diagnose else "PASS",": ",assertions," assertions")
	else:
		for failure in failures: push_error(failure)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
