# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Mira de quem joga no controle, do analogico ate o ponto no mundo. O caminho
## puro (zona morta, rampa, cursor preso na tela) mora em test_in_game_settings;
## aqui e a integracao: jogador de verdade, SubViewport e Camera3D como o
## split_screen_manager monta em jogo.
## Uso: await GamepadAimTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const VIEW_SIZE := Vector2i(800, 600)
## Passos de _apply_look_stick: 0,25 s no talo tem que tirar o cursor do centro
## bem alem de MIN_AIM_PLANAR_DISTANCE.
const STEP_SECONDS := 0.05
const STEPS := 5
## Controle imaginario do teste: id alto para nao colidir com pad plugado.
const FAKE_DEVICE := 7


## Analogico falso, para mirar sem controle plugado na maquina de teste.
class StuckStick extends RefCounted:
	var axis := Vector2.ZERO

	func read(_slot: int) -> Vector2:
		return axis


func run(test_root: Node) -> void:
	await _test_right_stick_aims_in_third_person(test_root)
	await _test_keyboard_slot_keeps_the_mouse_cursor(test_root)
	await _test_joypad_event_moves_the_cursor_end_to_end(test_root)
	await _test_left_stick_walks_and_buttons_act(test_root)
	await _test_four_local_players_do_not_mix_devices(test_root)


## Joystick de verdade, sem fake: `Input.parse_input_event` com um
## `InputEventJoypadMotion` e o jeito que o GodotTestDriver simula controle
## (Chickensoft.GodotTestDriver/src/Input/ControllerInputExtensions.cs). Este
## teste fecha a camada que o StuckStick pula: `GameConfig.player_look_axis`
## lendo o device e os eixos certos, e o gatilho direito apertando a acao de
## tiro pelo InputMap. Usa o device 7 para nao brigar com controle plugado na
## maquina. O evento so aparece no frame seguinte, dai os awaits.
func _test_joypad_event_moves_the_cursor_end_to_end(test_root: Node) -> void:
	print("Testando joystick simulado de ponta a ponta...")
	var previous := _saved_configs()
	GameConfig.configure_local_players([GameConfig.create_gamepad_config(FAKE_DEVICE)] as Array[Dictionary])
	var player := await _spawn_aiming_player(test_root, null)
	var centered: Vector2 = player.call("aim_cursor_position")
	_send_axis(JOY_AXIS_RIGHT_X, 0.9)
	_send_axis(JOY_AXIS_RIGHT_Y, -0.5)
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await test_root.get_tree().process_frame
	await test_root.get_tree().process_frame
	var axis_read: Vector2 = GameConfig.player_look_axis(0)
	var shoots: bool = Input.is_action_pressed(GameConfig.action_name(0, "attack"))
	for step in STEPS:
		player.call("_apply_look_stick", STEP_SECONDS)
	var moved: Vector2 = player.call("aim_cursor_position")
	_send_axis(JOY_AXIS_RIGHT_X, 0.0)
	_send_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await test_root.get_tree().process_frame
	_despawn(test_root, player)
	GameConfig.configure_local_players(previous)
	var right_axes := axis_read.is_equal_approx(Vector2(0.9, -0.5))
	var cursor_followed := moved.x > centered.x + 40.0 and moved.y < centered.y - 20.0
	if not right_axes or not shoots or not cursor_followed:
		_fail(test_root, "Joystick simulado: eixos=%s (esperado (0.9, -0.5)) gatilho_atira=%s centro=%s cursor=%s." % [axis_read, shoots, centered, moved])
		return
	print("PASS: Evento de joypad real chega no eixo, no gatilho e no cursor.")


## O analogico direito e so metade do controle. Este cobre a outra: o esquerdo
## virando `move_input` do boneco, e os botoes chegando nas acoes do jogo.
func _test_left_stick_walks_and_buttons_act(test_root: Node) -> void:
	print("Testando analogico esquerdo e botoes do controle simulado...")
	var previous := _saved_configs()
	GameConfig.configure_local_players([GameConfig.create_gamepad_config(FAKE_DEVICE)] as Array[Dictionary])
	var player := await _spawn_aiming_player(test_root, null)
	_send_axis(JOY_AXIS_LEFT_X, 1.0)
	_send_axis(JOY_AXIS_LEFT_Y, -1.0)
	_send_button(JOY_BUTTON_A, true)
	_send_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await test_root.get_tree().process_frame
	await test_root.get_tree().process_frame
	player.call("_poll_input")
	var move: Vector2 = player.get("move_input")
	# `is_action_just_pressed` so vale no frame do evento, e aqui ja passaram
	# dois; o que interessa e o botao ter chegado na acao do slot.
	var jumped: bool = Input.is_action_pressed(GameConfig.action_name(0, "jump"))
	var knifed: bool = Input.is_action_pressed(GameConfig.action_name(0, "knife"))
	var idle_action: bool = Input.is_action_pressed(GameConfig.action_name(0, "reload"))
	_send_axis(JOY_AXIS_LEFT_X, 0.0)
	_send_axis(JOY_AXIS_LEFT_Y, 0.0)
	_send_button(JOY_BUTTON_A, false)
	_send_button(JOY_BUTTON_LEFT_SHOULDER, false)
	await test_root.get_tree().process_frame
	_despawn(test_root, player)
	GameConfig.configure_local_players(previous)
	var walks := move.x > 0.7 and move.y < -0.7
	if not walks or not jumped or not knifed or idle_action:
		_fail(test_root, "Controle simulado: move=%s (esperado +x -y) pulou=%s faca=%s recarga_solta=%s." % [move, jumped, knifed, idle_action])
		return
	print("PASS: Analogico esquerdo anda e os botoes acionam pulo e faca.")


## Quatro jogadores no mesmo computador com dispositivos diferentes. O que pode
## dar errado aqui e um controle pilotar o boneco do vizinho: o InputMap e
## global e so o `device` do evento separa um slot do outro. Mexe um controle
## de cada vez e cobra que so o dono dele reaja.
func _test_four_local_players_do_not_mix_devices(test_root: Node) -> void:
	print("Testando 4 jogadores locais com dispositivos diferentes...")
	var previous := _saved_configs()
	# Teclado no 1 e no 3, controle no 2 e no 4: e a mistura que acontece de
	# verdade quando so tem dois controles em casa.
	GameConfig.configure_local_players([
		GameConfig.create_keyboard_config(0),
		GameConfig.create_gamepad_config(FAKE_DEVICE),
		GameConfig.create_keyboard_config(2),
		GameConfig.create_gamepad_config(FAKE_DEVICE + 1),
	] as Array[Dictionary])
	_send_axis_on(FAKE_DEVICE, JOY_AXIS_RIGHT_X, 0.8)
	_send_button_on(FAKE_DEVICE, JOY_BUTTON_A, true)
	await test_root.get_tree().process_frame
	await test_root.get_tree().process_frame
	var pad_one_aims: Vector2 = GameConfig.player_look_axis(1)
	var pad_two_quiet: Vector2 = GameConfig.player_look_axis(3)
	var keyboard_slots_quiet: bool = GameConfig.player_look_axis(0).is_zero_approx() and GameConfig.player_look_axis(2).is_zero_approx()
	var jumps: Array[bool] = []
	for slot in 4:
		jumps.append(Input.is_action_pressed(GameConfig.action_name(slot, "jump")))
	var taken := GameConfig.selectable_devices(3, GameConfig.player_input_configs, [
		{"id": FAKE_DEVICE, "name": "Controle do jogador 2"},
		{"id": FAKE_DEVICE + 1, "name": "Controle do jogador 4"},
	])
	_send_axis_on(FAKE_DEVICE, JOY_AXIS_RIGHT_X, 0.0)
	_send_button_on(FAKE_DEVICE, JOY_BUTTON_A, false)
	await test_root.get_tree().process_frame
	GameConfig.configure_local_players(previous)
	var only_owner_aims := is_equal_approx(pad_one_aims.x, 0.8) and pad_two_quiet.is_zero_approx()
	var expected_jumps: Array[bool] = [false, true, false, false]
	var only_owner_jumps := jumps == expected_jumps
	var hides_other_pad := _device_names(taken) == ["Teclado", "Controle do jogador 4"]
	if not only_owner_aims or not only_owner_jumps or not keyboard_slots_quiet or not hides_other_pad:
		_fail(test_root, "4 jogadores: mira_do_dono=%s outro_parado=%s teclados_parados=%s pulos=%s lista_do_slot_4=%s." % [pad_one_aims, pad_two_quiet, keyboard_slots_quiet, jumps, _device_names(taken)])
		return
	print("PASS: Cada um dos 4 slots so obedece ao proprio dispositivo.")


func _device_names(devices: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for device in devices:
		names.append(String(device.get("name", "")))
	return names


func _send_axis_on(device: int, axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = device
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


func _send_button_on(device: int, button_index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)


## Um botao do controle simulado, apertado ou solto.
func _send_button(button_index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = FAKE_DEVICE
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)


## Um eixo do controle simulado, no formato que o Godot entrega de um pad real.
func _send_axis(axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = FAKE_DEVICE
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


## O analogico direito tem que fazer na 3a pessoa o que o mouse faz: levar o
## cursor e, por ele, o ponto de mira no mundo.
func _test_right_stick_aims_in_third_person(test_root: Node) -> void:
	print("Testando analogico direito mirando na terceira pessoa...")
	var previous := _saved_configs()
	GameConfig.configure_local_players([GameConfig.create_gamepad_config(0)] as Array[Dictionary])
	var stick := StuckStick.new()
	var player := await _spawn_aiming_player(test_root, stick)
	var centered: Vector2 = player.call("aim_cursor_position")
	stick.axis = Vector2(1.0, 0.0)
	for step in STEPS:
		player.call("_apply_look_stick", STEP_SECONDS)
	var moved: Vector2 = player.call("aim_cursor_position")
	var target: Variant = player.call("_local_aim_target")
	var recognized: bool = bool(player.call("uses_gamepad"))
	var went_right := moved.x > centered.x + 40.0 and is_equal_approx(moved.y, centered.y)
	var aimed_in_world := target is Vector3 and PlayerCharacter.aim_point_is_usable(player.global_position, target as Vector3)
	var aimed_to_the_right := target is Vector3 and (target as Vector3).x > player.global_position.x + 1.0
	_despawn(test_root, player)
	GameConfig.configure_local_players(previous)
	if not recognized or not went_right or not aimed_in_world or not aimed_to_the_right:
		_fail(test_root, "Mira do controle: reconhecido=%s centro=%s cursor=%s alvo=%s longe=%s direita=%s." % [recognized, centered, moved, target, aimed_in_world, aimed_to_the_right])
		return
	print("PASS: Analogico direito leva o cursor e o ponto de mira na 3a pessoa.")


## Quem esta no teclado nao ganha cursor virtual: o ponto de mira continua sendo
## o do mouse, e o analogico de um controle qualquer nao mexe nele.
func _test_keyboard_slot_keeps_the_mouse_cursor(test_root: Node) -> void:
	print("Testando slot de teclado sem cursor virtual...")
	var previous := _saved_configs()
	GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)] as Array[Dictionary])
	var stick := StuckStick.new()
	stick.axis = Vector2(1.0, 0.0)
	var player := await _spawn_aiming_player(test_root, stick)
	for step in STEPS:
		player.call("_apply_look_stick", STEP_SECONDS)
	var cursor: Vector2 = player.call("aim_cursor_position")
	var mouse_cursor: Vector2 = (player.get("aim_viewport") as Viewport).get_mouse_position()
	var untouched: bool = (player.get("virtual_cursor") as Vector2).is_zero_approx()
	var follows_mouse := cursor.is_equal_approx(mouse_cursor)
	var recognized: bool = bool(player.call("uses_gamepad"))
	_despawn(test_root, player)
	GameConfig.configure_local_players(previous)
	if recognized or not untouched or not follows_mouse:
		_fail(test_root, "Slot de teclado: virou_controle=%s cursor_virtual_parado=%s segue_mouse=%s (%s vs %s)." % [recognized, untouched, follows_mouse, cursor, mouse_cursor])
		return
	print("PASS: Slot de teclado continua no cursor do mouse.")


## Jogador local em 3a pessoa com o quadro que o split_screen_manager daria:
## SubViewport proprio e camera olhando o boneco de cima.
func _spawn_aiming_player(test_root: Node, stick: Variant) -> CharacterBody3D:
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.world_3d = test_root.get_viewport().world_3d
	test_root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.global_position = Vector3(0.0, 14.0, 14.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	# A suite roda a partir da cena do menu, que deixa menu_open ligado; em
	# partida o main.gd desliga. Sem isto a mira do controle fica travada.
	GameConfig.menu_open = false
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(player)
	player.global_position = Vector3.ZERO
	player.set("local_slot", 0)
	player.set("is_local_controller", true)
	player.set("mouse_owner", true)
	player.set("first_person", false)
	player.set("mouse_aim", true)
	player.set("aim_camera", camera)
	player.set("aim_viewport", viewport)
	if stick != null:
		player.set("look_axis_source", Callable(stick, "read"))
	await test_root.get_tree().process_frame
	return player


func _despawn(test_root: Node, player: CharacterBody3D) -> void:
	var viewport := player.get("aim_viewport") as Node
	test_root.remove_child(player)
	player.queue_free()
	if viewport != null and is_instance_valid(viewport):
		test_root.remove_child(viewport)
		viewport.queue_free()


func _saved_configs() -> Array[Dictionary]:
	var previous: Array[Dictionary] = []
	for config in GameConfig.player_input_configs:
		previous.append(config.duplicate(true))
	return previous


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
