extends Resource
## M05 prototype values. Shared configuration, never runtime health/gauge state.
@export_range(1.0, 10000.0) var max_hp: float = 100.0
@export_range(0.0, 10000.0) var initial_hp: float = 100.0
@export_range(1.0, 100.0) var gauge_max: float = 100.0
@export_range(0.0, 100.0) var initial_gauge: float = 100.0
@export_range(0.01, 10.0) var gauge_recovery_seconds: float = 1.2
