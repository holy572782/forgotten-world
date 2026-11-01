extends CanvasLayer
## Test-map-only modes. Explicit buttons restart a trial; no in-game respawn system.
const EnemyScene = preload("res://scenes/enemies/practice_enemy.tscn")
const Work=preload("res://scripts/enemies/enemy_work_diagnostics.gd")
@export var performance_diagnostics: Work=Work.new()
@export_enum("Static", "Melee", "Ranged") var initial_mode := 0
@export var debug_unlimited_pursuit := false
@export var show_enemy_diagnostics := false
var active_enemy: CharacterBody3D
var mode := 0
var status: Label
var buttons: Array[Button] = []

func _ready() -> void:
	get_parent().get_node("Player/TargetDash").performance_diagnostics=performance_diagnostics
	var panel := VBoxContainer.new()
	panel.position = Vector2(300, 12)
	add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	for index in range(3):
		var button := Button.new()
		button.text = ["静止敵", "近接敵", "遠距離敵"][index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_mode.bind(index))
		row.add_child(button)
		buttons.append(button)
	status = Label.new()
	status.text = "静止敵：攻撃しません。近接敵・遠距離敵で戦闘を試せます"
	status.add_theme_font_size_override("font_size", 13)
	panel.add_child(status)
	buttons[0].set_pressed_no_signal(true)
	# Parent main finishes player/camera wiring before the first trial is reset.
	if initial_mode != 0: select_mode.call_deferred(initial_mode)

func select_mode(next: int) -> void:
	var main := get_parent()
	for effect in get_tree().get_nodes_in_group("enemy_defeat_visuals"):
		if main.is_ancestor_of(effect): effect.queue_free()
	var player: CharacterBody3D = main.get_node("Player")
	player.combat.cancel()
	player.combat.selected_target = null
	if is_instance_valid(active_enemy):
		active_enemy.clear_shots()
		active_enemy.hide() # Invalidate an old selection before detaching its Targetable.
		main.remove_child(active_enemy)
		active_enemy.queue_free()
	active_enemy = null
	mode = next
	for index in range(buttons.size()): buttons[index].set_pressed_no_signal(index == mode)
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
		active_enemy.performance_diagnostics=performance_diagnostics
		active_enemy.debug_unlimited_pursuit=debug_unlimited_pursuit
		active_enemy.show_attack_diagnostics=show_enemy_diagnostics
		active_enemy.position = Vector3(-2, 0, -2)
		main.add_child(active_enemy)
	status.text = ["静止敵：左クリック攻撃・連撃の確認用（敵は攻撃しません）", "近接敵：左クリック攻撃・右クリック／I 防御・方向入力で帰還", "遠距離敵：左クリック攻撃・右クリック／I 防御・移動で弾を回避"][mode]

func _process(_delta: float) -> void:
	if performance_diagnostics!=null: performance_diagnostics.update_report()
