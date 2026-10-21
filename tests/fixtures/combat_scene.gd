extends RefCounted
## Fixed combat test geometry, independent of the editable F5 practice layout.
static func create() -> Node3D:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	scene.get_node("PracticeSelector").initial_mode = 0 # Legacy combat trials use stationary targets.
	scene.get_node("TrainingEnemy").position = Vector3(-3,0,-2)
	scene.get_node("TrainingEnemySecond").position = Vector3(-8,0,-2)
	scene.get_node("TrainingEnemyThird").position = Vector3(-5.5,0,-4)
	var extra := scene.get_node_or_null("TrainingEnemy2")
	if extra != null: extra.free()
	return scene
