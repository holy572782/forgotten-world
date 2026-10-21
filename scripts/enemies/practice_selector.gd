extends CanvasLayer
## Test-map-only modes. Explicit buttons restart a trial; no in-game respawn system.
const EnemyScene = preload("res://scenes/enemies/practice_enemy.tscn")
var active_enemy: CharacterBody3D
var mode := 0
var status: Label

func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(300, 12)
	add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	for index in range(3):
		var button := Button.new()
		button.text = ["Static / M07", "M09 Melee", "M09 Ranged"][index]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_mode.bind(index))
		row.add_child(button)
	status = Label.new()
	status.text = "M09 practice: choose one trial (button also resets it)"
	status.add_theme_font_size_override("font_size", 13)
	panel.add_child(status)

func select_mode(next: int) -> void:
	var main := get_parent()
	var player: CharacterBody3D = main.get_node("Player")
	player.combat.cancel()
	if is_instance_valid(active_enemy):
		active_enemy.clear_shots()
		main.remove_child(active_enemy)
		active_enemy.queue_free()
	active_enemy = null
	mode = next
	for child in main.get_children():
		if child is StaticBody3D and child.has_node("Targetable"):
			child.visible = mode == 0
			child.collision_layer = 4 if mode == 0 else 0
			child.get_node("Targetable").set_available(false)
			child.get_node("HealthComponent").heal(1000)
	player.get_node("HealthComponent").heal(1000)
	player.reset_motion(main.get_node("TestArena/PlayerSpawn").global_position)
	var stock: AttackStockComponent = player.get_node("AttackStockComponent")
	stock.set_recovery_allowed(true)
	stock.advance(stock.settings.recovery_seconds * stock.maximum)
	main.get_node("CameraRig").snap_to_target()
	if mode != 0:
		active_enemy = EnemyScene.instantiate()
		active_enemy.name = "M09PracticeEnemy"
		active_enemy.settings = load("res://resources/enemies/melee_practice.tres" if mode == 1 else "res://resources/enemies/ranged_practice.tres")
		active_enemy.player = player
		active_enemy.position = Vector3(-2, 0, -2)
		main.add_child(active_enemy)
	status.text = ["Static targets: existing M07 combo trial", "Melee: sector = hit range; I guard / direction to return", "Ranged: slow straight shot; WASD to sidestep / I guard"][mode]
