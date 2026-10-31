extends RefCounted
## Optional instrumentation installed only in the isolated profiling copy.
static var enabled:=false
static var counts: Dictionary={}
static func reset() -> void: counts.clear()
static func hit(key: String, amount: float=1.0) -> void:
	if enabled: counts[key]=counts.get(key,0.0)+amount
static func ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	hit("ray")
	return space.intersect_ray(query)
static func shape(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, maximum: int=32) -> Array[Dictionary]:
	hit("shape")
	return space.intersect_shape(query,maximum)
static func cast(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> PackedFloat32Array:
	hit("cast")
	return space.cast_motion(query)
static func contacts(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, maximum: int=32) -> PackedVector3Array:
	hit("contacts")
	return space.collide_shape(query,maximum)
static func motion(body: PhysicsBody3D, transform: Transform3D, vector: Vector3, collision: KinematicCollision3D=null, margin: float=0.001, recovery: bool=false, maximum: int=1) -> bool:
	hit("motion")
	return body.test_move(transform,vector,collision,margin,recovery,maximum)
static func attack(script: Script, body: CharacterBody3D, at: Vector3, weapon: Resource, path: Resource, stop: float, motion_settings: Resource, from: Vector3, diagnostics: Dictionary) -> Dictionary:
	hit("attack_plans")
	var start:=Time.get_ticks_usec()
	var result: Dictionary=script.attack(body,at,weapon,path,stop,motion_settings,from,diagnostics)
	var elapsed:=Time.get_ticks_usec()-start
	hit("attack_us",elapsed)
	if enabled: counts["attack_max_us"]=maxf(counts.get("attack_max_us",0.0),elapsed)
	return result
static func find(route: RefCounted, actor: CharacterBody3D, at: Vector3) -> Array[Vector3]:
	hit("searches")
	var start:=Time.get_ticks_usec()
	var result: Array[Vector3]=route._find(actor,at)
	var elapsed:=Time.get_ticks_usec()-start
	hit("search_us",elapsed)
	if enabled: counts["search_max_us"]=maxf(counts.get("search_max_us",0.0),elapsed)
	return result
static func advance(route: RefCounted, actor: CharacterBody3D) -> void:
	hit("search_slices")
	var start:=Time.get_ticks_usec()
	route._advance_search(actor)
	var elapsed:=Time.get_ticks_usec()-start
	hit("search_us",elapsed)
	if enabled: counts["search_max_us"]=maxf(counts.get("search_max_us",0.0),elapsed)
