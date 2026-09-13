extends Control

const ACTIONS := [
	["up", "Mover para cima"],
	["down", "Mover para baixo"],
	["left", "Mover para esquerda"],
	["right", "Mover para direita"],
	["jump", "Pular"],
	["sprint", "Correr"],
	["attack", "Atirar / atacar"],
	["knife", "Equipar faca"],
	["pistol", "Equipar pistola"],
	["reload", "Recarregar"],
]

@onready var selection: VBoxContainer = $MenuPanel/Selection
@onready var setup: VBoxContainer = $MenuPanel/Setup
@onready var settings: VBoxContainer = $MenuPanel/Settings
@onready var menu_panel: PanelContainer = $MenuPanel
@onready var controller_status: Label = $MenuPanel/Selection/ControllerStatus
@onready var network_mode: OptionButton = $MenuPanel/Selection/NetworkMode/Mode
@onready var server_address_row: HBoxContainer = $MenuPanel/Selection/ServerAddress
@onready var server_address: LineEdit = $MenuPanel/Selection/ServerAddress/Address
@onready var server_browser: VBoxContainer = $MenuPanel/Selection/ServerBrowser
@onready var server_list: VBoxContainer = $MenuPanel/Selection/ServerBrowser/ServerScroll/ServerList
@onready var server_address_input: LineEdit = $MenuPanel/Selection/ServerBrowser/AddServer/Address
@onready var server_port_input: LineEdit = $MenuPanel/Selection/ServerBrowser/AddServer/Port
@onready var server_browser_message: Label = $MenuPanel/Selection/ServerBrowser/Message
@onready var refresh_servers_button: Button = $MenuPanel/Selection/ServerBrowser/Header/Refresh
@onready var add_server_button: Button = $MenuPanel/Selection/ServerBrowser/AddServer/Add
@onready var local_player_buttons: Array[Button] = [$MenuPanel/Selection/TwoPlayers, $MenuPanel/Selection/ThreePlayers, $MenuPanel/Selection/FourPlayers]
@onready var setup_title: Label = $MenuPanel/Setup/SetupTitle
@onready var players_scroll: ScrollContainer = $MenuPanel/Setup/PlayersScroll
@onready var players_grid: GridContainer = $MenuPanel/Setup/PlayersScroll/PlayersGrid
@onready var message: Label = $MenuPanel/Setup/Message
@onready var start_button: Button = $MenuPanel/Setup/Actions/Start
@onready var resolution_select: OptionButton = $MenuPanel/Settings/ResolutionRow/Resolution
@onready var quality_select: OptionButton = $MenuPanel/Settings/QualityRow/Quality
@onready var fullscreen_toggle: CheckButton = $MenuPanel/Settings/Fullscreen
@onready var quality_description: Label = $MenuPanel/Settings/QualityDescription
@onready var settings_message: Label = $MenuPanel/Settings/Message

var player_configs: Array[Dictionary] = []
var capture_player := -1
var capture_action := ""
var capture_button: Button
var selected_mode := "local"
var server_refresh_elapsed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot or NetworkSession.is_server():
		return
	NetworkSession.join_accepted.connect(_on_join_accepted)
	NetworkSession.join_failed.connect(_on_join_failed)
	NetworkSession.server_list_changed.connect(_render_server_list)
	network_mode.add_item("Jogar local")
	network_mode.add_item("Multiplayer")
	network_mode.item_selected.connect(_on_network_mode_selected)
	refresh_servers_button.pressed.connect(_refresh_servers)
	add_server_button.pressed.connect(_save_server)
	quality_select.item_selected.connect(_on_quality_selected)
	get_viewport().size_changed.connect(_layout_menu)
	server_address_row.visible = false
	selection.visible = true
	setup.visible = false
	settings.visible = false
	_configure_settings()
	_update_network_mode_ui()
	_refresh_servers()
	_update_controller_status()
	_layout_menu.call_deferred()


func _process(_delta: float) -> void:
	if selection.visible:
		_update_controller_status()
		if selected_mode == "server":
			server_refresh_elapsed += _delta
			if server_refresh_elapsed >= 5.0:
				_refresh_servers()
				server_refresh_elapsed = 0.0


func _input(event: InputEvent) -> void:
	if capture_player < 0:
		return

	var config: Dictionary = player_configs[capture_player]
	var captured_event: InputEvent
	if config["device_type"] == "keyboard":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_cancel_capture()
				accept_event()
				return
			var key_event := InputEventKey.new()
			key_event.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			captured_event = key_event
		elif event is InputEventMouseButton and event.pressed:
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = event.button_index
			captured_event = mouse_event
	elif event is InputEventJoypadButton and event.pressed and event.device == config["device_id"]:
		var joy_event := InputEventJoypadButton.new()
		joy_event.device = event.device
		joy_event.button_index = event.button_index
		captured_event = joy_event

	if captured_event != null:
		var bindings: Dictionary = config["bindings"]
		bindings[capture_action] = captured_event
		capture_button.text = captured_event.as_text()
		capture_player = -1
		capture_action = ""
		capture_button = null
		message.text = "Configuracao atualizada."
		accept_event()


func _show_setup(player_count: int) -> void:
	selection.visible = false
	setup.visible = true
	settings.visible = false
	setup_title.text = "CONFIGURAR JOGADOR" if selected_mode == "server" else "CONFIGURAR %d JOGADOR%s" % [player_count, "" if player_count == 1 else "ES"]
	player_configs.clear()
	var joypads := Input.get_connected_joypads()
	for slot in player_count:
		if slot > 0 and slot - 1 < joypads.size():
			player_configs.append(GameConfig.create_gamepad_config(joypads[slot - 1]))
		else:
			player_configs.append(GameConfig.create_keyboard_config(slot))
	_rebuild_player_cards()
	message.text = "Clique em uma acao e pressione a tecla ou botao desejado."
	start_button.text = "INICIAR PARTIDA" if selected_mode == "local" else "ENTRAR NA SALA"
	start_button.disabled = false
	_layout_menu()


func _configure_settings() -> void:
	resolution_select.clear()
	for resolution in GameConfig.SUPPORTED_RESOLUTIONS:
		resolution_select.add_item("%d x %d" % [resolution.x, resolution.y])
		if resolution == GameConfig.graphics_resolution:
			resolution_select.select(resolution_select.item_count - 1)
	quality_select.clear()
	quality_select.add_item("Baixo")
	quality_select.add_item("Medio")
	quality_select.add_item("Alto")
	quality_select.select(int(GameConfig.graphics_quality))
	fullscreen_toggle.button_pressed = GameConfig.graphics_fullscreen
	_update_quality_description(int(GameConfig.graphics_quality))


func _layout_menu() -> void:
	if not is_inside_tree():
		return
	var available_size := get_viewport_rect().size - Vector2(32.0, 32.0)
	var panel_size := Vector2(minf(1080.0, available_size.x), minf(680.0, available_size.y))
	menu_panel.offset_left = -panel_size.x * 0.5
	menu_panel.offset_top = -panel_size.y * 0.5
	menu_panel.offset_right = panel_size.x * 0.5
	menu_panel.offset_bottom = panel_size.y * 0.5
	players_grid.columns = 1 if panel_size.x < 900.0 else 2
	players_scroll.custom_minimum_size = Vector2(0.0, maxf(panel_size.y - 180.0, 260.0))
	for card in players_grid.get_children():
		card.custom_minimum_size.x = minf(430.0, panel_size.x - 64.0)


func _rebuild_player_cards() -> void:
	for child in players_grid.get_children():
		child.free()
	for slot in player_configs.size():
		_create_player_card(slot)


func _create_player_card(slot: int) -> void:
	var config: Dictionary = player_configs[slot]
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.add_theme_constant_override("separation", 6)
	players_grid.add_child(card)

	var title := Label.new()
	title.text = "JOGADOR %d" % (slot + 1)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.72, 0.83, 0.59))
	card.add_child(title)

	var device_selector := OptionButton.new()
	device_selector.custom_minimum_size = Vector2(0, 38)
	device_selector.add_item("Teclado")
	device_selector.set_item_metadata(0, {"type": "keyboard", "id": -1})
	var selected_item := 0
	for joypad_id in Input.get_connected_joypads():
		device_selector.add_item(Input.get_joy_name(joypad_id))
		var item_index := device_selector.item_count - 1
		device_selector.set_item_metadata(item_index, {"type": "gamepad", "id": joypad_id})
		if config["device_type"] == "gamepad" and config["device_id"] == joypad_id:
			selected_item = item_index
	device_selector.select(selected_item)
	device_selector.item_selected.connect(_on_device_selected.bind(slot, device_selector))
	card.add_child(device_selector)

	var bindings_grid := GridContainer.new()
	bindings_grid.columns = 2
	bindings_grid.add_theme_constant_override("h_separation", 8)
	bindings_grid.add_theme_constant_override("v_separation", 4)
	card.add_child(bindings_grid)

	var bindings: Dictionary = config["bindings"]
	for action_data in ACTIONS:
		var action: String = action_data[0]
		var action_label := Label.new()
		action_label.text = action_data[1]
		action_label.custom_minimum_size = Vector2(185, 30)
		bindings_grid.add_child(action_label)

		var binding_button := Button.new()
		binding_button.custom_minimum_size = Vector2(220, 30)
		var binding := bindings.get(action) as InputEvent
		binding_button.text = binding.as_text() if binding != null else "Nao definido"
		var uses_analog: bool = config["device_type"] == "gamepad" and action in ["up", "down", "left", "right"]
		binding_button.disabled = uses_analog
		if uses_analog:
			binding_button.text = "Analogico esquerdo"
		else:
			binding_button.pressed.connect(_begin_capture.bind(slot, action, binding_button))
		bindings_grid.add_child(binding_button)


func _on_device_selected(item_index: int, slot: int, selector: OptionButton) -> void:
	var metadata: Dictionary = selector.get_item_metadata(item_index)
	if metadata["type"] == "keyboard":
		player_configs[slot] = GameConfig.create_keyboard_config(slot)
	else:
		player_configs[slot] = GameConfig.create_gamepad_config(metadata["id"])
	_rebuild_player_cards()


func _begin_capture(slot: int, action: String, button: Button) -> void:
	capture_player = slot
	capture_action = action
	capture_button = button
	button.text = "Pressione agora..."
	message.text = "Esc cancela o remapeamento."


func _cancel_capture() -> void:
	if capture_button != null:
		var bindings: Dictionary = player_configs[capture_player]["bindings"]
		var binding := bindings.get(capture_action) as InputEvent
		capture_button.text = binding.as_text() if binding != null else "Nao definido"
	capture_player = -1
	capture_action = ""
	capture_button = null
	message.text = "Remapeamento cancelado."


func _start_game() -> void:
	if capture_player >= 0:
		message.text = "Termine ou cancele o remapeamento atual."
		return
	GameConfig.configure_local_players(player_configs)
	if selected_mode == "local":
		NetworkSession.leave_session()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	start_button.disabled = true
	message.text = "Conectando ao servidor..."
	var port := NetworkSession.parse_server_port_value(server_port_input.text.strip_edges())
	if port < 0:
		start_button.disabled = false
		message.text = "Porta invalida; use um numero entre 1024 e 65535."
		return
	var save_error := GameConfig.save_server(server_address.text, port)
	if save_error != OK:
		start_button.disabled = false
		message.text = "Nao foi possivel salvar o servidor: %s" % error_string(save_error)
		return
	var error: Error = NetworkSession.join_server(
		server_address.text.strip_edges(),
		player_configs.size(),
		port
	)
	if error != OK:
		start_button.disabled = false
		message.text = "Endereco invalido ou falha ao iniciar conexao: %s" % error_string(error)


func _update_controller_status() -> void:
	var connected := Input.get_connected_joypads().size()
	controller_status.text = "Controles conectados: %d\nCada jogador podera escolher seu dispositivo e comandos." % connected


func _on_network_mode_selected(index: int) -> void:
	selected_mode = "local" if index == 0 else "server"
	_update_network_mode_ui()
	if selected_mode == "server":
		_refresh_servers()


func _update_network_mode_ui() -> void:
	var multiplayer_selected := selected_mode == "server"
	server_address_row.visible = false
	server_browser.visible = multiplayer_selected
	for button in local_player_buttons:
		button.visible = not multiplayer_selected
	$MenuPanel/Selection/OnePlayer.text = "ENTRAR NA SALA" if multiplayer_selected else "1 JOGADOR"


func _refresh_servers() -> void:
	if selected_mode != "server":
		return
	server_browser_message.text = "Descobrindo servidores na rede local..."
	var error := NetworkSession.refresh_server_list()
	if error != OK:
		server_browser_message.text = "Falha ao consultar servidores: %s" % error_string(error)


func _save_server() -> void:
	var port := NetworkSession.parse_server_port_value(server_port_input.text.strip_edges())
	var error := GameConfig.save_server(server_address_input.text, port)
	if error != OK:
		server_browser_message.text = "Servidor invalido. Informe IP e porta entre 1024 e 65535."
		return
	server_address.text = server_address_input.text.strip_edges()
	server_browser_message.text = "Servidor salvo. Consultando status..."
	_refresh_servers()


func _render_server_list() -> void:
	for child in server_list.get_children():
		child.free()
	var servers := NetworkSession.get_server_list()
	if servers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Nenhuma sala encontrada. Adicione um IP abaixo."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		server_list.add_child(empty_label)
		return
	for server in servers:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 38
		var status := "ONLINE" if bool(server.get("online", false)) else "SEM RESPOSTA"
		var ping := "%d ms" % int(server.get("ping_ms", -1)) if int(server.get("ping_ms", -1)) >= 0 else "--"
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s | %s | %d/%d jogadores | ping %s\n%s" % [
			String(server.get("name", server.get("address", "Servidor"))),
			status,
			int(server.get("active_players", 0)),
			int(server.get("max_players", 4)),
			ping,
			String(server.get("mission", "Desconhecida")),
		]
		row.add_child(label)
		var join_button := Button.new()
		join_button.text = "ENTRAR"
		join_button.disabled = not bool(server.get("online", false)) or int(server.get("active_players", 0)) >= int(server.get("max_players", 4))
		join_button.pressed.connect(_select_server.bind(server))
		row.add_child(join_button)
		server_list.add_child(row)


func _select_server(server: Dictionary) -> void:
	server_address.text = String(server.get("address", ""))
	server_port_input.text = str(int(server.get("port", NetworkSession.DEFAULT_PORT)))
	_show_setup(1)


func _on_settings_pressed() -> void:
	selection.visible = false
	setup.visible = false
	settings.visible = true
	settings_message.text = ""
	_configure_settings()
	_layout_menu()


func _on_settings_back_pressed() -> void:
	settings.visible = false
	selection.visible = true


func _on_apply_settings_pressed() -> void:
	var resolution_index := resolution_select.selected
	if resolution_index < 0 or resolution_index >= GameConfig.SUPPORTED_RESOLUTIONS.size():
		settings_message.text = "Resolucao selecionada invalida."
		return
	var resolution: Vector2i = GameConfig.SUPPORTED_RESOLUTIONS[resolution_index]
	var error: Error = GameConfig.apply_graphics_settings(
		resolution,
		quality_select.selected,
		fullscreen_toggle.button_pressed
	)
	if error != OK:
		settings_message.text = "Falha ao salvar configuracao: %s" % error_string(error)
		return
	settings_message.text = "Configuracao aplicada e salva."
	_layout_menu.call_deferred()


func _on_quality_selected(index: int) -> void:
	_update_quality_description(index)


func _update_quality_description(index: int) -> void:
	if index == GameConfig.GraphicsQuality.LOW:
		quality_description.text = "Sem MSAA e sombras; floresta reduzida."
	elif index == GameConfig.GraphicsQuality.MEDIUM:
		quality_description.text = "MSAA 2x, sombras e floresta media."
	else:
		quality_description.text = "MSAA 4x, sombras e floresta completa."


func _on_join_accepted() -> void:
	return


func _on_join_failed(error_message: String) -> void:
	start_button.disabled = false
	message.text = error_message


func _on_one_player_pressed() -> void:
	_show_setup(1)


func _on_two_players_pressed() -> void:
	_show_setup(2)


func _on_three_players_pressed() -> void:
	_show_setup(3)


func _on_four_players_pressed() -> void:
	_show_setup(4)


func _on_back_pressed() -> void:
	_cancel_capture()
	setup.visible = false
	selection.visible = true


func _on_start_pressed() -> void:
	_start_game()


func _on_quit_pressed() -> void:
	get_tree().quit()
