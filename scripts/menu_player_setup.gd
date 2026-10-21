# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name MenuPlayerSetup
extends VBoxContainer

## Cartoes de configuracao dos jogadores locais: dispositivo (teclado/controle)
## e remapeamento de teclas. Uso:
##   setup.configure(2)
##   GameConfig.configure_local_players(setup.configs())

signal capture_changed(message: String)

var player_configs: Array[Dictionary] = []

var _title: Label
var _grid: GridContainer
var _message: Label
var _capture_slot := -1
var _capture_action := ""
var _capture_button: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_title = MenuTheme.title_label("CONFIGURAR JOGADORES", 26)
	add_child(_title)
	add_child(MenuTheme.muted_label("Escolha o dispositivo. Clique em um comando para remapear. Movimento no controle usa o analogico esquerdo."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 30)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.columns = 2
	scroll.add_child(_grid)
	_message = Label.new()
	_message.custom_minimum_size = Vector2(0.0, 28.0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", MenuTheme.WARNING)
	add_child(_message)
	Input.joy_connection_changed.connect(_on_joypad_connection_changed)


## Monta um cartao por jogador local, casando controle quando houver.
func configure(player_count: int) -> void:
	_title.text = "CONFIGURAR %d JOGADOR%s" % [player_count, "" if player_count == 1 else "ES"]
	player_configs.clear()
	var joypads := Input.get_connected_joypads()
	for slot in player_count:
		if slot > 0 and slot - 1 < joypads.size():
			player_configs.append(GameConfig.create_gamepad_config(joypads[slot - 1]))
		else:
			player_configs.append(GameConfig.create_keyboard_config(slot))
	_message.text = "Clique em uma acao e pressione a tecla ou botao desejado."
	_rebuild()


func configs() -> Array[Dictionary]:
	return player_configs


func is_capturing() -> bool:
	return _capture_slot >= 0


func _input(event: InputEvent) -> void:
	if _capture_slot < 0:
		return
	var config: Dictionary = player_configs[_capture_slot]
	if KeybindingEditor.is_cancel(event, config):
		_cancel_capture()
		accept_event()
		return
	var captured := KeybindingEditor.capture_event(event, config)
	if captured == null:
		return
	(player_configs[_capture_slot]["bindings"] as Dictionary)[_capture_action] = captured
	_capture_button.text = KeybindingEditor.event_text(captured)
	_capture_slot = -1
	_capture_action = ""
	_capture_button = null
	_message.text = "Configuracao atualizada."
	accept_event()


## O rebuild libera o proprio OptionButton que emitiu o sinal, entao ele sai da
## arvore agora e so morre no fim do frame (ver in_game_settings_panel.refresh).
func _rebuild() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for slot in player_configs.size():
		_create_card(slot)


func _create_card(slot: int) -> void:
	var config: Dictionary = player_configs[slot]
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(430.0, 0.0)
	card.add_theme_constant_override("separation", 6)
	_grid.add_child(card)
	card.add_child(MenuTheme.section_label("JOGADOR %d" % (slot + 1)))

	var device_selector := OptionButton.new()
	device_selector.name = "Device_%d" % slot
	device_selector.custom_minimum_size = Vector2(0.0, 38.0)
	var devices := GameConfig.selectable_devices(slot, player_configs, GameConfig.connected_joypads())
	for index in devices.size():
		var device: Dictionary = devices[index]
		device_selector.add_item(String(device["name"]))
		device_selector.set_item_metadata(index, device)
		if String(config["device_type"]) == String(device["type"]) and int(config["device_id"]) == int(device["id"]):
			device_selector.select(index)
	device_selector.item_selected.connect(_on_device_selected.bind(slot, device_selector))
	card.add_child(device_selector)

	var bindings_grid := GridContainer.new()
	bindings_grid.columns = 2
	bindings_grid.add_theme_constant_override("h_separation", 8)
	bindings_grid.add_theme_constant_override("v_separation", 4)
	card.add_child(bindings_grid)
	for action_data in KeybindingEditor.ACTION_LABELS:
		var action: String = action_data[0]
		var action_label := Label.new()
		action_label.text = action_data[1]
		action_label.custom_minimum_size = Vector2(185.0, 30.0)
		bindings_grid.add_child(action_label)
		var binding_button := Button.new()
		binding_button.custom_minimum_size = Vector2(220.0, 30.0)
		binding_button.text = KeybindingEditor.binding_text(config, action)
		binding_button.disabled = KeybindingEditor.uses_analog(config, action)
		if not binding_button.disabled:
			binding_button.pressed.connect(_begin_capture.bind(slot, action, binding_button))
		bindings_grid.add_child(binding_button)


func _on_device_selected(item_index: int, slot: int, selector: OptionButton) -> void:
	var metadata: Dictionary = selector.get_item_metadata(item_index)
	if String(metadata["type"]) == "keyboard":
		player_configs[slot] = GameConfig.create_keyboard_config(slot)
	else:
		var config := GameConfig.create_gamepad_config(int(metadata["id"]))
		config["device_name"] = String(metadata["name"])
		player_configs[slot] = config
	_rebuild.call_deferred()


func _on_joypad_connection_changed(device_id: int, connected: bool) -> void:
	if not connected:
		for slot in GameConfig.slots_using_joypad(player_configs, device_id):
			player_configs[slot] = GameConfig.create_keyboard_config(slot)
		_message.text = "Controle %d foi desconectado." % (device_id + 1)
	if visible and not player_configs.is_empty():
		_rebuild.call_deferred()


func _begin_capture(slot: int, action: String, button: Button) -> void:
	_capture_slot = slot
	_capture_action = action
	_capture_button = button
	button.text = "Pressione agora..."
	_message.text = "Esc cancela o remapeamento."
	capture_changed.emit(_message.text)


func _cancel_capture() -> void:
	if _capture_button != null:
		var bindings: Dictionary = player_configs[_capture_slot]["bindings"]
		var binding := bindings.get(_capture_action) as InputEvent
		_capture_button.text = binding.as_text() if binding != null else "Nao definido"
	_capture_slot = -1
	_capture_action = ""
	_capture_button = null
	_message.text = "Remapeamento cancelado."
