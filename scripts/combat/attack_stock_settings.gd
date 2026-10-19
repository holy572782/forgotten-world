extends Resource
@export_range(1, 99) var maximum: int = 3
@export_range(0, 99) var initial: int = 3
@export_range(0.01, 10.0) var recovery_seconds: float = 1.5
