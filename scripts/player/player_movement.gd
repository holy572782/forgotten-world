extends Resource
## Prototype values from system specification section 3; not final balance.

@export var speed: float = 5.0
@export var acceleration: float = 22.0
@export var deceleration: float = 30.0
@export var gravity: float = 20.0
@export var air_control: float = 0.7
@export var max_slope_degrees: float = 40.0
## Provisional ground adhesion for the M01 ramp; not a step-climbing height.
@export var snap_length: float = 0.3
