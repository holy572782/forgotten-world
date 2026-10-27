extends Resource
## Presentation only: sheet size and equipment never determine attack reach.
const WeaponVisual = preload("res://scripts/player/weapon_attack_visual_data.gd")
@export var walk_frames: SpriteFrames
@export var attack_frames: SpriteFrames
@export var weapon_visual: WeaponVisual
@export_range(0.001, 0.1) var pixel_size := 0.0375
@export var sprite_offset := Vector2(0, 23)
@export_group("Weapon grip correction (pixels)")
@export var weapon_offsets_down := PackedVector2Array()
@export var weapon_offsets_left := PackedVector2Array()
@export var weapon_offsets_right := PackedVector2Array()
@export var weapon_offsets_up := PackedVector2Array()

func weapon_offset(side: String, frame: int) -> Vector2:
	var values: PackedVector2Array = get("weapon_offsets_" + side)
	return values[clampi(frame, 0, values.size() - 1)] if not values.is_empty() else Vector2.ZERO
