extends RefCounted
## Execution only. Owners retain attack/guard/combo decisions.
const Arc=preload("res://scripts/combat/jump_arc.gd")
const Terrain=preload("res://scripts/combat/elevation_path.gd")
var data: Dictionary={}
var elapsed:=0.0
var falling:=false
var vertical_speed:=0.0
var fall_time:=0.0
var failed:=false
var active:=false

func begin(plan: Dictionary) -> void:
	data=plan.duplicate()
	elapsed=0.0
	falling=false
	failed=false
	active=true
	fall_time=0.0

func step(body: CharacterBody3D, delta: float) -> int:
	var before:=body.global_position
	var next: Vector3
	if falling:
		fall_time+=delta
		vertical_speed=maxf(-10.0,vertical_speed-20.0*delta)
		next=before+Vector3.UP*vertical_speed*delta
	else:
		elapsed=minf(elapsed+delta,data.duration)
		next=Arc.position_at(data.start,data.direction,data.speed,data.takeoff,data.gravity,elapsed,data.duration,data.curve)
	var collision:=body.move_and_collide(next-before)
	body.velocity=(body.global_position-before)/maxf(delta,0.0001)
	if collision!=null or (not falling and elapsed>=data.duration):
		if body.velocity.y<=0.01 and Terrain.supported(body,body.global_position,0.025):
			body.move_and_collide(Vector3.DOWN*0.01)
			active=false
			return -1 if failed else 1
		falling=true
		failed=true
		vertical_speed=minf(0.0,body.velocity.y)
	if fall_time>=2.0:
		active=false
		body.velocity=Vector3.ZERO
		return -1
	return 0
