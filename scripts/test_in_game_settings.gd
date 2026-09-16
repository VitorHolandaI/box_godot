extends RefCounted

## Regressoes das configuracoes dentro da partida (pedido: Esc deveria mostrar
## opcoes e troca de teclas, nao so pausar).
## Uso: await InGameSettingsTests.new().run(test_root)

const IN_GAME_MENU_SCENE := preload("res://scenes/in_game_menu.tscn")


func run(test_root: Node) -> void:
	_test_capture_event_by_device(test_root)
	_test_binding_change_updates_input_map(test_root)
	await _test_escape_menu_opens_settings(test_root)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event


func _test_capture_event_by_device(test_root: Node) -> void:
	print("Testando captura de tecla/botao por dispositivo...")
	var keyboard: Dictionary = GameConfig.create_keyboard_config(0)
	var pad: Dictionary = GameConfig.create_gamepad_config(3)
	var captured_key: InputEvent = KeybindingEditor.capture_event(_key(KEY_J), keyboard)
	var escape_cancels: bool = KeybindingEditor.is_cancel(_key(KEY_ESCAPE), keyboard)
	var ignored_escape: InputEvent = KeybindingEditor.capture_event(_key(KEY_ESCAPE), keyboard)
	var button := InputEventJoypadButton.new()
	button.device = 3
	button.button_index = JOY_BUTTON_Y
	button.pressed = true
	var other_pad := InputEventJoypadButton.new()
	other_pad.device = 1
	other_pad.button_index = JOY_BUTTON_Y
	other_pad.pressed = true
	var captured_button: InputEvent = KeybindingEditor.capture_event(button, pad)
	var key_on_pad: InputEvent = KeybindingEditor.capture_event(_key(KEY_J), pad)
	var ok_key := captured_key is InputEventKey and (captured_key as InputEventKey).physical_keycode == KEY_J
	var ok_button := captured_button is InputEventJoypadButton and (captured_button as InputEventJoypadButton).button_index == JOY_BUTTON_Y
	if not ok_key or not escape_cancels or ignored_escape != null or not ok_button or KeybindingEditor.capture_event(other_pad, pad) != null or key_on_pad != null:
		_fail(test_root, "Captura: tecla=%s esc_cancela=%s esc_ignorado=%s botao=%s outro_controle=%s tecla_no_controle=%s." % [ok_key, escape_cancels, ignored_escape == null, ok_button, KeybindingEditor.capture_event(other_pad, pad), key_on_pad])
		return
	if KeybindingEditor.ACTION_LABELS.size() != GameConfig.ACTIONS.size():
		_fail(test_root, "Cada acao de GameConfig.ACTIONS precisa de rotulo; acoes=%d rotulos=%d." % [GameConfig.ACTIONS.size(), KeybindingEditor.ACTION_LABELS.size()])
		return
	print("PASS: Captura de tecla e botao por dispositivo validada.")


func _test_binding_change_updates_input_map(test_root: Node) -> void:
	print("Testando troca de tecla valendo na hora...")
	var previous: Array[Dictionary] = []
	for config in GameConfig.player_input_configs:
		previous.append(config.duplicate(true))
	var configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
	GameConfig.configure_local_players(configs)
	GameConfig.set_player_binding(0, "grenade", _key(KEY_K))
	var events := InputMap.action_get_events(GameConfig.action_name(0, "grenade"))
	var applied := events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == KEY_K
	var stored := (GameConfig.player_input_configs[0]["bindings"]["grenade"] as InputEventKey).physical_keycode == KEY_K
	GameConfig.configure_local_players(previous)
	if not applied or not stored:
		_fail(test_root, "Tecla nova deveria entrar no InputMap e na configuracao do jogador; mapa=%s guardada=%s." % [applied, stored])
		return
	print("PASS: Troca de tecla vale na hora.")


func _test_escape_menu_opens_settings(test_root: Node) -> void:
	print("Testando menu do Esc abrindo configuracoes e teclas...")
	var previous: Array[Dictionary] = []
	for config in GameConfig.player_input_configs:
		previous.append(config.duplicate(true))
	var configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0), GameConfig.create_keyboard_config(1)]
	GameConfig.configure_local_players(configs)
	var menu := IN_GAME_MENU_SCENE.instantiate() as Control
	test_root.add_child(menu)
	await test_root.get_tree().process_frame
	menu.call("open_menu")
	var has_button := menu.find_child("Settings", true, false) is Button
	menu.call("open_settings")
	var panel := menu.find_child("InGameSettingsPanel", true, false) as Control
	var shown := panel != null and panel.visible and not (menu.get_node("MenuPanel") as Control).visible
	var binding_buttons := 0
	var has_quality := false
	if panel != null:
		binding_buttons = panel.find_children("Bind_*", "Button", true, false).size()
		has_quality = panel.find_child("Quality", true, false) is OptionButton
	menu.call("close_settings")
	var back_to_menu := (menu.get_node("MenuPanel") as Control).visible and (panel == null or not panel.visible)
	menu.call("close_menu")
	menu.free()
	GameConfig.configure_local_players(previous)
	var expected_buttons := GameConfig.ACTIONS.size() * 2
	if not has_button or not shown or binding_buttons != expected_buttons or not has_quality or not back_to_menu:
		_fail(test_root, "Menu do Esc: botao=%s painel=%s teclas=%d (esperado %d) qualidade=%s volta=%s." % [has_button, shown, binding_buttons, expected_buttons, has_quality, back_to_menu])
		return
	print("PASS: Menu do Esc abre graficos e teclas de cada jogador.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
