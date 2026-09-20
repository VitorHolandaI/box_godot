extends Control

## Pedido do botao "Destravar personagem"; main.gd resolve local ou pela rede.
signal unstuck_requested

@onready var title: Label = $MenuPanel/Content/Title
@onready var status: Label = $MenuPanel/Content/Status

var is_open := false
var settings_panel: InGameSettingsPanel = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Com as configuracoes abertas o Esc volta ao menu da partida (a captura de
	# tecla ja consome o proprio Esc antes de chegar aqui).
	if is_settings_open():
		close_settings()
	elif is_open:
		close_menu()
	else:
		open_menu()
	get_viewport().set_input_as_handled()


func open_menu() -> void:
	is_open = true
	visible = true
	GameConfig.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkSession.is_offline():
		title.text = "JOGO PAUSADO"
		status.text = "A partida local esta parada."
		get_tree().paused = true
	else:
		title.text = "MENU DA PARTIDA"
		status.text = "A partida online continua acontecendo."


func close_menu() -> void:
	close_settings()
	get_tree().paused = false
	is_open = false
	visible = false
	GameConfig.menu_open = false
	# Devolve o cursor ao estado da camera (FPS prende, isometrica solta).
	for node in get_tree().get_nodes_in_group("player"):
		if node.get("is_local_controller") == true and node.has_method("_apply_mouse_capture"):
			node.call("_apply_mouse_capture")


## Graficos e teclas dos jogadores locais sem sair da partida.
## Uso: menu.open_settings()
func open_settings() -> void:
	if settings_panel == null:
		settings_panel = InGameSettingsPanel.new()
		var continue_button := $MenuPanel/Content/Continue as Button
		settings_panel.apply_styles($MenuPanel.get_theme_stylebox("panel"), {"normal": continue_button.get_theme_stylebox("normal"), "hover": continue_button.get_theme_stylebox("hover")})
		settings_panel.closed.connect(close_settings)
		add_child(settings_panel)
	else:
		settings_panel.refresh()
	settings_panel.visible = true
	$MenuPanel.visible = false


func close_settings() -> void:
	if settings_panel != null:
		settings_panel.visible = false
	$MenuPanel.visible = true


func is_settings_open() -> bool:
	return settings_panel != null and settings_panel.visible


func _on_settings_pressed() -> void:
	open_settings()


func _on_continue_pressed() -> void:
	close_menu()


func _on_unstuck_pressed() -> void:
	unstuck_requested.emit()
	close_menu()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	NetworkSession.leave_session()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	NetworkSession.leave_session()
	get_tree().quit()
