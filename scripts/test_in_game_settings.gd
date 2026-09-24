# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes das configuracoes dentro da partida (pedido: Esc deveria mostrar
## opcoes e troca de teclas, nao so pausar).
## Uso: await InGameSettingsTests.new().run(test_root)

const IN_GAME_MENU_SCENE := preload("res://scenes/in_game_menu.tscn")


func run(test_root: Node) -> void:
	_test_official_server_seed(test_root)
	_test_device_list_hides_pad_in_use(test_root)
	_test_device_change_rewrites_input_map(test_root)
	_test_look_stick_deadzone_and_ramp(test_root)
	_test_look_stick_turns_and_clamps_pitch(test_root)
	_test_virtual_cursor_moves_and_stays_on_screen(test_root)
	_test_gamepad_shoots_on_the_right_trigger(test_root)
	_test_gamepad_player_ignores_the_mouse(test_root)
	_test_capture_event_by_device(test_root)
	_test_binding_change_updates_input_map(test_root)
	await _test_escape_menu_opens_settings(test_root)
	await _test_device_rebuild_keeps_the_emitter_alive(test_root)


func _test_official_server_seed(test_root: Node) -> void:
	print("Testando servidor oficial salvo so na primeira abertura...")
	var first_open: Array[Dictionary] = GameConfig.saved_servers_with_official_default([], false)
	var already_present: Array[Dictionary] = GameConfig.saved_servers_with_official_default([GameConfig.OFFICIAL_SERVER], false)
	var removed_by_player: Array[Dictionary] = GameConfig.saved_servers_with_official_default([], true)
	var official: Dictionary = GameConfig.OFFICIAL_SERVER
	var seeded_once: bool = first_open.size() == 1 and first_open[0] == official
	var avoids_duplicate: bool = already_present.size() == 1 and already_present[0] == official
	if not seeded_once or not avoids_duplicate or not removed_by_player.is_empty():
		_fail(test_root, "Servidor oficial: primeira=%s duplicado=%s removido=%s." % [first_open, already_present, removed_by_player])
		return
	print("PASS: Servidor oficial entra uma vez e respeita a remocao do jogador.")


func _test_device_list_hides_pad_in_use(test_root: Node) -> void:
	print("Testando lista de dispositivos sem o controle de outro jogador...")
	var configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0), GameConfig.create_gamepad_config(0)]
	var connected: Array[Dictionary] = [{"id": 0, "name": "Generic X-Box pad"}, {"id": 1, "name": "Controle emprestado"}]
	var for_keyboard_player: Array[Dictionary] = GameConfig.selectable_devices(0, configs, connected)
	var for_pad_player: Array[Dictionary] = GameConfig.selectable_devices(1, configs, connected)
	var offered_to_keyboard := _device_keys(for_keyboard_player)
	var offered_to_pad := _device_keys(for_pad_player)
	var hides_taken_pad := offered_to_keyboard == ["keyboard:-1", "gamepad:1"]
	var keeps_own_pad := offered_to_pad == ["keyboard:-1", "gamepad:0", "gamepad:1"]
	var shows_real_name := for_pad_player.size() > 1 and String(for_pad_player[1].get("name", "")) == "Generic X-Box pad"
	if not hides_taken_pad or not keeps_own_pad or not shows_real_name:
		_fail(test_root, "Dispositivos: teclado_ve=%s controle_ve=%s nome=%s." % [offered_to_keyboard, offered_to_pad, shows_real_name])
		return
	print("PASS: Controle em uso some da lista dos outros jogadores.")


func _device_keys(devices: Array[Dictionary]) -> Array[String]:
	var keys: Array[String] = []
	for device in devices:
		keys.append("%s:%d" % [String(device.get("type", "")), int(device.get("id", -1))])
	return keys


func _test_device_change_rewrites_input_map(test_root: Node) -> void:
	print("Testando troca de dispositivo valendo na hora...")
	var previous: Array[Dictionary] = []
	for config in GameConfig.player_input_configs:
		previous.append(config.duplicate(true))
	var configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0), GameConfig.create_keyboard_config(1)]
	GameConfig.configure_local_players(configs)
	var moved_to_pad := GameConfig.set_player_device(1, "gamepad", 0, "Generic X-Box pad")
	var jump_on_pad := InputMap.action_get_events(GameConfig.action_name(1, "jump"))
	var uses_pad := jump_on_pad.size() == 1 and jump_on_pad[0] is InputEventJoypadButton and (jump_on_pad[0] as InputEventJoypadButton).device == 0
	var named := String(GameConfig.player_input_configs[1].get("device_name", "")) == "Generic X-Box pad"
	var stolen := GameConfig.set_player_device(0, "gamepad", 0, "Generic X-Box pad")
	var slot_zero_intact := String(GameConfig.player_input_configs[0].get("device_type", "")) == "keyboard"
	var released: Array[int] = GameConfig.release_unplugged_joypad(0)
	var back_to_keyboard := String(GameConfig.player_input_configs[1].get("device_type", "")) == "keyboard"
	var jump_after_unplug := InputMap.action_get_events(GameConfig.action_name(1, "jump"))
	var keys_again := jump_after_unplug.size() == 1 and jump_after_unplug[0] is InputEventKey
	GameConfig.configure_local_players(previous)
	if not moved_to_pad or not uses_pad or not named or stolen or not slot_zero_intact or released != [1] or not back_to_keyboard or not keys_again:
		_fail(test_root, "Troca de dispositivo: trocou=%s no_mapa=%s nome=%s roubou=%s slot0=%s soltos=%s voltou=%s teclas=%s." % [moved_to_pad, uses_pad, named, stolen, slot_zero_intact, released, back_to_keyboard, keys_again])
		return
	print("PASS: Trocar de dispositivo reescreve o InputMap e o desplugue volta pro teclado.")


func _test_look_stick_deadzone_and_ramp(test_root: Node) -> void:
	print("Testando zona morta e rampa do analogico direito...")
	var idle: Vector2 = PlayerCharacter.look_stick_vector(Vector2(0.12, -0.08), 0.2)
	var half: Vector2 = PlayerCharacter.look_stick_vector(Vector2(0.6, 0.0), 0.2)
	var full: Vector2 = PlayerCharacter.look_stick_vector(Vector2(1.0, 0.0), 0.2)
	var over: Vector2 = PlayerCharacter.look_stick_vector(Vector2(0.9, 0.9), 0.2)
	var ignores_drift := idle == Vector2.ZERO
	# (0.6 - 0.2) / 0.8 = 0.5, ao quadrado = 0.25: perto do centro a mira e fina.
	var ramps := is_equal_approx(snappedf(half.x, 0.001), 0.25) and half.y == 0.0
	var reaches_one := is_equal_approx(snappedf(full.length(), 0.001), 1.0)
	var never_passes_one := over.length() <= 1.0001
	if not ignores_drift or not ramps or not reaches_one or not never_passes_one:
		_fail(test_root, "Analogico: parado=%s meio=%s cheio=%s diagonal=%s." % [idle, half, full, over])
		return
	print("PASS: Analogico direito ignora drift, sobe suave e nao passa de 1.")


func _test_look_stick_turns_and_clamps_pitch(test_root: Node) -> void:
	print("Testando o analogico direito girando a camera...")
	# Analogico para a direita gira para a direita (yaw cai), igual ao mouse.
	var turned: Vector2 = PlayerCharacter.look_stick_step(0.0, 0.0, Vector2(1.0, 0.0), 2.0, 0.5)
	var looked_down: Vector2 = PlayerCharacter.look_stick_step(0.0, 0.0, Vector2(0.0, 1.0), 2.0, 0.5)
	var pinned: Vector2 = PlayerCharacter.look_stick_step(0.0, 0.0, Vector2(0.0, -1.0), 20.0, 1.0)
	var turns_right := is_equal_approx(snappedf(turned.x, 0.001), -1.0) and turned.y == 0.0
	var tilts_down := is_equal_approx(snappedf(looked_down.y, 0.001), -1.0)
	var clamped := is_equal_approx(snappedf(pinned.y, 0.001), snappedf(PlayerCharacter.AIM_PITCH_LIMIT, 0.001))
	if not turns_right or not tilts_down or not clamped:
		_fail(test_root, "Camera do analogico: direita=%s baixo=%s teto=%s (limite %f)." % [turned, looked_down, pinned, PlayerCharacter.AIM_PITCH_LIMIT])
		return
	print("PASS: Analogico direito gira a camera e respeita o limite de pitch.")


func _test_gamepad_player_ignores_the_mouse(test_root: Node) -> void:
	print("Testando jogador de controle sem o cursor do mouse...")
	var configs: Array[Dictionary] = [GameConfig.create_gamepad_config(0), GameConfig.create_keyboard_config(1)]
	var pad_player := GameConfig.slot_uses_gamepad(configs, 0)
	var keyboard_player := GameConfig.slot_uses_gamepad(configs, 1)
	var out_of_range := GameConfig.slot_uses_gamepad(configs, 7)
	if not pad_player or keyboard_player or out_of_range:
		_fail(test_root, "Dispositivo do slot: controle=%s teclado=%s fora=%s." % [pad_player, keyboard_player, out_of_range])
		return
	print("PASS: Slot de controle e reconhecido e o de teclado nao.")


func _test_virtual_cursor_moves_and_stays_on_screen(test_root: Node) -> void:
	print("Testando cursor virtual do analogico direito...")
	var screen := Vector2(800.0, 600.0)
	var center := screen * 0.5
	var moved: Vector2 = PlayerCharacter.moved_cursor(center, Vector2(1.0, 0.0), 200.0, 0.5, screen)
	var up: Vector2 = PlayerCharacter.moved_cursor(center, Vector2(0.0, -1.0), 200.0, 0.5, screen)
	var off_right: Vector2 = PlayerCharacter.moved_cursor(center, Vector2(1.0, 1.0), 100000.0, 1.0, screen)
	var off_left: Vector2 = PlayerCharacter.moved_cursor(center, Vector2(-1.0, -1.0), 100000.0, 1.0, screen)
	# Analogico para a direita leva o cursor para a direita, para cima sobe (y cai).
	var goes_right := moved == Vector2(500.0, 300.0)
	var goes_up := up == Vector2(400.0, 200.0)
	var stays_on_screen := off_right == screen and off_left == Vector2.ZERO
	if not goes_right or not goes_up or not stays_on_screen:
		_fail(test_root, "Cursor virtual: direita=%s cima=%s canto+=%s canto-=%s." % [moved, up, off_right, off_left])
		return
	print("PASS: Cursor virtual segue o analogico e nao sai da tela.")


func _test_gamepad_shoots_on_the_right_trigger(test_root: Node) -> void:
	print("Testando gatilho direito como tiro padrao do controle...")
	var pad: Dictionary = GameConfig.create_gamepad_config(0)
	var attack: InputEvent = (pad["bindings"] as Dictionary).get("attack")
	var on_trigger := attack is InputEventJoypadMotion and (attack as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT and (attack as InputEventJoypadMotion).axis_value > 0.0
	var pulled := InputEventJoypadMotion.new()
	pulled.device = 0
	pulled.axis = JOY_AXIS_TRIGGER_RIGHT
	pulled.axis_value = 0.9
	var resting := InputEventJoypadMotion.new()
	resting.device = 0
	resting.axis = JOY_AXIS_TRIGGER_RIGHT
	resting.axis_value = 0.05
	var stick_drift := InputEventJoypadMotion.new()
	stick_drift.device = 0
	stick_drift.axis = JOY_AXIS_LEFT_X
	stick_drift.axis_value = 0.9
	var captured: InputEvent = KeybindingEditor.capture_event(pulled, pad)
	var captures_trigger := captured is InputEventJoypadMotion and (captured as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT
	var ignores_resting := KeybindingEditor.capture_event(resting, pad) == null
	var ignores_stick := KeybindingEditor.capture_event(stick_drift, pad) == null
	if not on_trigger or not captures_trigger or not ignores_resting or not ignores_stick:
		_fail(test_root, "Gatilho: padrao=%s captura=%s ignora_solto=%s ignora_analogico=%s." % [attack, captures_trigger, ignores_resting, ignores_stick])
		return
	print("PASS: Tiro do controle nasce no gatilho direito e o gatilho e remapeavel.")


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
	var device_selectors := 0
	if panel != null:
		binding_buttons = panel.find_children("Bind_*", "Button", true, false).size()
		has_quality = panel.find_child("Quality", true, false) is OptionButton
		device_selectors = panel.find_children("Device_*", "OptionButton", true, false).size()
	menu.call("close_settings")
	var back_to_menu := (menu.get_node("MenuPanel") as Control).visible and (panel == null or not panel.visible)
	menu.call("close_menu")
	menu.free()
	GameConfig.configure_local_players(previous)
	var expected_buttons := GameConfig.ACTIONS.size() * 2
	if not has_button or not shown or binding_buttons != expected_buttons or not has_quality or not back_to_menu or device_selectors != 2:
		_fail(test_root, "Menu do Esc: botao=%s painel=%s teclas=%d (esperado %d) qualidade=%s dispositivos=%d (esperado 2) volta=%s." % [has_button, shown, binding_buttons, expected_buttons, has_quality, device_selectors, back_to_menu])
		return
	print("PASS: Menu do Esc abre graficos, dispositivo e teclas de cada jogador.")


## Regressao do SIGSEGV de 2026-09-24. Trocar o dispositivo no Esc chama
## refresh() de dentro do popup do OptionButton; com `free()` imediato o
## emissor morria no meio da emissao e o cliente caia ("Object was freed or
## unreferenced while a signal is being emitted from it", em godot.log).
func _test_device_rebuild_keeps_the_emitter_alive(test_root: Node) -> void:
	print("Testando rebuild do painel sem matar o OptionButton que emitiu...")
	var previous: Array[Dictionary] = []
	for config in GameConfig.player_input_configs:
		previous.append(config.duplicate(true))
	GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)] as Array[Dictionary])
	var menu := IN_GAME_MENU_SCENE.instantiate() as Control
	test_root.add_child(menu)
	await test_root.get_tree().process_frame
	menu.call("open_menu")
	menu.call("open_settings")
	var panel := menu.find_child("InGameSettingsPanel", true, false) as Control
	var selector := panel.find_child("Device_0", true, false) as OptionButton
	panel.call("refresh")
	var alive_during_emission := is_instance_valid(selector)
	await test_root.get_tree().process_frame
	var freed_after_frame := not is_instance_valid(selector)
	var rebuilt := panel.find_children("Device_*", "OptionButton", true, false).size() == 1
	menu.call("close_menu")
	menu.queue_free()
	await test_root.get_tree().process_frame
	GameConfig.configure_local_players(previous)
	if not alive_during_emission or not freed_after_frame or not rebuilt:
		_fail(test_root, "Rebuild do painel: vivo_no_frame=%s liberado_depois=%s remontou=%s." % [alive_during_emission, freed_after_frame, rebuilt])
		return
	print("PASS: O rebuild so destroi a UI velha no fim do frame.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
