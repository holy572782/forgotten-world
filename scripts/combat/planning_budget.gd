extends RefCounted
## Shared budget for speculative plans, including route preflights. Actual
## collision/hit/launch validation is never replaced by a cached permission.
const MAX_CHECKS:=8
const MICROSECONDS:=1200
static var _frame:=-1
static var _checks:=0
static var _spent:=0
static var _depth:=0
static var _started:=0
static func _refresh() -> void:
	var frame:=Engine.get_process_frames()
	if frame!=_frame:
		_frame=frame
		_checks=0
		_spent=0

static func allowed() -> bool:
	_refresh()
	return _checks<MAX_CHECKS and _spent+(Time.get_ticks_usec()-_started if _depth>0 else 0)<MICROSECONDS

static func take() -> bool:
	if not allowed(): return false
	_checks+=1
	return true

static func begin() -> void:
	_refresh()
	if _depth==0: _started=Time.get_ticks_usec()
	_depth+=1

static func end() -> void:
	_depth=maxi(0,_depth-1)
	if _depth==0: _spent+=Time.get_ticks_usec()-_started
