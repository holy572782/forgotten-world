extends Node3D
## Isolated F6 preview; gameplay uses no sample effect automatically.

@onready var emitter: EffekseerEmitter3D = $Emitter

func _ready() -> void:
	$ReplayTimer.timeout.connect(replay)
	$Instructions/Panel/Content/Replay.pressed.connect(replay)

func replay() -> void:
	emitter.stop()
	emitter.play()
