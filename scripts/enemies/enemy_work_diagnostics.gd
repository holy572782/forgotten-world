extends Resource
## Test-map diagnostics, shared by the selector, enemy and player target preview.
## Disabling a proof never grants movement or attack permission.
@export var local_astar_enabled:=true
@export var attack_planning_enabled:=true
@export var terrain_search_enabled:=true
@export var details_enabled:=true
@export var capture_timings:=false
@export var print_report:=false
@export_multiline var last_report:=""
var timings: Dictionary={}
var context: Dictionary={}
var _report_at:=0

static func for_body(body: Node) -> Resource:
	if "performance_diagnostics" in body: return body.performance_diagnostics
	if "combat" in body and is_instance_valid(body.combat): return body.combat.performance_diagnostics
	return null

static func start(body: Node) -> int:
	var config:=for_body(body)
	return Time.get_ticks_usec() if config!=null and config.capture_timings else 0

static func finish(body: Node, key: String, started: int) -> void:
	if started==0: return
	var config:=for_body(body)
	if config==null: return
	var elapsed:=Time.get_ticks_usec()-started
	var entry: Dictionary=config.timings.get(key,{"calls":0,"total_us":0,"max_us":0})
	entry.calls+=1
	entry.total_us+=elapsed
	entry.max_us=maxi(entry.max_us,elapsed)
	config.timings[key]=entry

func reset() -> void:
	timings.clear()
	_report_at=Time.get_ticks_usec()

func report() -> Dictionary:
	return {"fps":Engine.get_frames_per_second(),"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"render_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"context":context.duplicate(),"enabled":{"A_astar":local_astar_enabled,"B_attack":attack_planning_enabled,"C_terrain":terrain_search_enabled,"D_details":details_enabled},"timings":timings.duplicate(true)}

func update_report() -> void:
	if not capture_timings or Time.get_ticks_usec()-_report_at<1000000: return
	last_report=JSON.stringify(report(),"  ")
	if print_report: print("ENEMY WORK ",JSON.stringify(report()))
	reset()
