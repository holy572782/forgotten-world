extends SceneTree
## Deterministically rasterize the original vector texture sources for Effekseer.
func _initialize() -> void:
	for part in ["outer", "inner"]:
		var svg := FileAccess.get_file_as_string("res://assets/source/effects/mage_circle/circle_%s.svg" % part)
		var image := Image.new()
		if image.load_svg_from_string(svg) != OK:
			quit(1)
			return
		if image.save_png("res://assets/effects/mage_circle/textures/circle_%s.png" % part) != OK:
			quit(1)
			return
	quit()
