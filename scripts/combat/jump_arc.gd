extends RefCounted
## Pure ballistic math / swept-body validation. No input, AI or damage ownership.
static func gravity(height: float, takeoff_speed: float) -> float:
	return takeoff_speed*takeoff_speed/(2.0*height)

static func flight_time(height: float, takeoff_speed: float, rise: float) -> float:
	if not is_finite(height) or not is_finite(takeoff_speed) or height<=0.0 or takeoff_speed<=0.0 or rise>height: return -1.0
	var g:=gravity(height,takeoff_speed)
	return (takeoff_speed+sqrt(maxf(0.0,takeoff_speed*takeoff_speed-2.0*g*rise)))/g

static func position_at(start: Vector3, direction: Vector3, horizontal_speed: float, takeoff_speed: float, g: float, time: float, duration: float=0.0, curve: int=0) -> Vector3:
	var horizontal_time:=time
	if duration>0.0 and curve!=0:
		var phase:=clampf(time/duration,0.0,1.0)
		horizontal_time=duration*(phase*phase if curve>0 else 1.0-(1.0-phase)*(1.0-phase))
	return start+direction*horizontal_speed*horizontal_time+Vector3.UP*(takeoff_speed*time-0.5*g*time*time)

static func clear(body: CharacterBody3D, start: Vector3, direction: Vector3, horizontal_speed: float, takeoff_speed: float, g: float, duration: float, curve: int=0) -> bool:
	# Chords deviate less than 0.5mm from the parabola, including fast settings.
	var acceleration:=Vector2(g,2.0*horizontal_speed/maxf(0.01,duration) if curve!=0 else 0.0).length()
	var interval:=minf(0.01,sqrt(0.004/maxf(0.01,acceleration)))
	var count:=maxi(1,ceili(duration/interval))
	var previous:=start
	for index in range(1,count+1):
		var next:=position_at(start,direction,horizontal_speed,takeoff_speed,g,duration*float(index)/count,duration,curve)
		if body.test_move(Transform3D(body.global_basis,previous),next-previous,null,body.safe_margin): return false
		previous=next
	return true
