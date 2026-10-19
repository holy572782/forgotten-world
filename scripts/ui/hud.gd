extends CanvasLayer
## Read-only presentation. Components own all mutations and emit value changes.
@export var player: CharacterBody3D
@export var camera_rig: Node3D
@onready var panel: PanelContainer = $Root/Panel
@onready var hp_label: Label = $Root/Panel/Margin/Rows/HPLabel
@onready var hp_bar: ProgressBar = $Root/Panel/Margin/Rows/HPBar
@onready var gauge_label: Label = $Root/Panel/Margin/Rows/GaugeLabel
@onready var gauge_bar: ProgressBar = $Root/Panel/Margin/Rows/GaugeBar
@onready var debug_label: Label = $Root/Panel/Margin/Rows/Debug
var stock: AttackStockComponent

func _ready() -> void:
	# Every Control ignores mouse input so left-click preview works over the HUD.
	_ignore_mouse($Root)
	# M06: only right-click is consumed over the panel; retain M05 preview input.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.gui_input.connect(_panel_input)
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()
	if not is_instance_valid(player):
		set_process(false)
		return
	var health: HealthComponent = player.get_node("HealthComponent")
	stock = player.get_node("AttackStockComponent")
	health.hp_changed.connect(_on_hp_changed)
	stock.stock_changed.connect(_on_stock_changed)
	_on_hp_changed(health.current_hp, health.max_hp)
	_on_stock_changed(stock.current, stock.maximum)

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		panel.accept_event()

func _layout_panel() -> void:
	panel.size.x = minf(280.0, maxf(0.0, get_viewport().get_visible_rect().size.x - 24.0))

func _on_hp_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "HP  %d / %d" % [ceili(current), ceili(maximum)]

func _on_stock_changed(current: int, maximum: int) -> void:
	# Keep long future capacities within the panel; the number always shows all stock.
	var icons := "◆".repeat(current) + "◇".repeat(maximum - current) if maximum <= 5 else ""
	gauge_label.text = "ATTACK  %s  %d/%d" % [icons, current, maximum]

func _process(_delta: float) -> void:
	var sprite = player.get_node("AnimatedSprite3D")
	var speed := player.velocity
	var yaw := rad_to_deg(camera_rig.rotation.y) if is_instance_valid(camera_rig) else 0.0
	gauge_bar.max_value = 1.0
	gauge_bar.value = stock.recovery_progress
	var detail := ""
	if is_instance_valid(player.combat):
		var c = player.combat
		var names := ["FREE", "APPROACH", "ATTACK", "RETURN"]
		detail = "\n%s%s | Hit %d/%d | Queue %d\nRegen %.0f%% | Return %.2fm" % [names[c.state], " WAIT" if c._waiting else "", c.combo_hits, c.equipped_weapon.max_combo_hits, int(c.queued), stock.recovery_progress * 100.0, c.return_error]
	debug_label.text = "FPS: %d | %s | Ground: %s\nSpeed: %.1f | Yaw: %.1f%s" % [Engine.get_frames_per_second(), sprite.state, str(player.is_on_floor()), speed.length(), yaw, detail]
