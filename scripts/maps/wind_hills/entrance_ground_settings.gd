@tool
extends Resource
## B01 visual-only settings. Coordinates and collision stay in the stage-A layout.
@export var enabled := true
@export_range(2.0,8.0,0.25) var grass_repeat_meters := 4.0
@export_range(0.0,1.0,0.01) var grass_strength := 0.55
@export_range(0.0,1.0,0.01) var paving_strength := 0.80
@export var region_min := Vector2(-20,-50)
@export var region_max := Vector2(20,20)
@export_range(1.0,4.0,0.25) var feather_meters := 4.0
@export var grass_texture: Texture2D
@export var paving_texture: Texture2D
## Four joint-free interiors, normalized in the unchanged source texture.
@export var stone_regions: Array[Rect2] = [Rect2(0.25,0.24,0.19,0.10),Rect2(0.36,0.40,0.20,0.11),Rect2(0.18,0.60,0.20,0.10),Rect2(0.70,0.80,0.19,0.12)]
