extends RefCounted
## Terrain grading only needs curve segments inside the maximum shaping distance.
## The same ordered segments are tested on either side of cell boundaries.
const CELL := 24.0
var cells: Dictionary = {}

class Segment:
	var start: Vector2
	var delta: Vector2
	var inverse_length_squared: float
	var start_y: float
	var rise: float
	var width: float

func add_curve(points: Array, width: float, reach: float) -> void:
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var segment := Segment.new()
		segment.start = Vector2(a.x,a.z)
		var end := Vector2(b.x,b.z)
		segment.delta = end-segment.start
		if segment.delta.length_squared() < 0.000001: continue
		segment.inverse_length_squared = 1.0/segment.delta.length_squared()
		segment.start_y = a.y
		segment.rise = b.y-a.y
		segment.width = width
		var first := Vector2i(((segment.start.min(end)-Vector2.ONE*reach)/CELL).floor())
		var last := Vector2i(((segment.start.max(end)+Vector2.ONE*reach)/CELL).floor())
		for x in range(first.x,last.x+1):
			for z in range(first.y,last.y+1):
				var key := Vector2i(x,z)
				if not cells.has(key): cells[key] = []
				cells[key].append(segment)

func sample(x: float, z: float) -> Dictionary:
	var point := Vector2(x,z)
	var nearest_squared := INF
	var nearest_y := 0.0
	var nearest_x := x
	var nearest_z := z
	var width := 0.0
	for segment: Segment in cells.get(Vector2i((point/CELL).floor()),[]):
		var t := clampf((point-segment.start).dot(segment.delta)*segment.inverse_length_squared,0,1)
		var on_line := segment.start+segment.delta*t
		var squared := point.distance_squared_to(on_line)
		if squared < nearest_squared:
			nearest_squared = squared
			nearest_y = segment.start_y+segment.rise*t
			nearest_x = on_line.x
			nearest_z = on_line.y
			width = segment.width
	return {"distance":sqrt(nearest_squared),"height":nearest_y,"offset_x":x-nearest_x,"center_z":nearest_z,"width":width}
