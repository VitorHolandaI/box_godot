# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends CanvasLayer

## Painel do controle por cima da partida, um bloco por jogador local. Mostra ao
## vivo os mesmos valores que `scripts/test_gamepad_aim.gd` confere sem janela,
## entao da para conferir a olho o que o teste afirma.
##
## Fica pendurado na raiz, nao na cena, para sobreviver a troca de cena que o
## `controle_lab.gd` faz ao subir a partida.
##
## Os slots listados em `sim_devices` sao pilotados por eventos fabricados
## (`Input.parse_input_event`), o mesmo jeito do teste e do GodotTestDriver.
## Cada um anda com uma defasagem diferente, senao os quatro bonecos fariam o
## mesmo movimento e nao daria para ver que um nao pilota o outro.
##
## TAB liga/desliga o roteiro, ESPACO segura o gatilho direito dos simulados.

const SIM_TURNS_PER_SECOND := 0.25
## O analogico esquerdo gira mais devagar, senao o boneco so treme no lugar.
const SIM_WALK_TURNS_PER_SECOND := 0.12
const BUTTON_HOLD_SECONDS := 0.9
## Acoes de botao que o roteiro aperta, uma por vez, na ordem.
const SCRIPTED_BUTTONS := ["interact", "jump", "sprint", "knife", "pistol", "reload", "sonar", "grenade", "throw_knife"]

## Devices simulados que este painel pilota, na ordem dos slots que os usam.
var sim_devices: Array[int] = []

var _readout: Label
var _players: Array = []
var _look_angle := 0.0
var _walk_angle := 0.0
var _scripted := true
var _pulling_trigger := false
var _button_clock := 0.0
var _button_index := 0
var _held_buttons: Dictionary = {}


func _ready() -> void:
	layer = 100
	_readout = Label.new()
	_readout.position = Vector2(14.0, 12.0)
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_readout.add_theme_constant_override("shadow_offset_x", 1)
	_readout.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_readout)


func _process(delta: float) -> void:
	if _scripted and not sim_devices.is_empty():
		_drive_sticks(delta)
		_drive_buttons(delta)
	_readout.text = _describe()


## Cada controle simulado gira com uma defasagem propria, para os bonecos nao
## andarem em bloco e dar para ver que um controle nao pilota o vizinho.
func _drive_sticks(delta: float) -> void:
	_look_angle = wrapf(_look_angle + delta * SIM_TURNS_PER_SECOND * TAU, 0.0, TAU)
	_walk_angle = wrapf(_walk_angle + delta * SIM_WALK_TURNS_PER_SECOND * TAU, 0.0, TAU)
	for index in sim_devices.size():
		var device: int = sim_devices[index]
		var phase := TAU * float(index) / float(sim_devices.size())
		_send_axis(device, JOY_AXIS_RIGHT_X, cos(_look_angle + phase))
		_send_axis(device, JOY_AXIS_RIGHT_Y, sin(_look_angle + phase))
		_send_axis(device, JOY_AXIS_LEFT_X, cos(_walk_angle + phase))
		_send_axis(device, JOY_AXIS_LEFT_Y, sin(_walk_angle + phase))
		_send_axis(device, JOY_AXIS_TRIGGER_RIGHT, 1.0 if _pulling_trigger else 0.0)


## Aperta um botao mapeado por vez em cada controle simulado: assim porta, arma
## do chao, faca e granada aparecem acontecendo sem ninguem com o controle.
func _drive_buttons(delta: float) -> void:
	_button_clock += delta
	if _button_clock < BUTTON_HOLD_SECONDS:
		return
	_button_clock = 0.0
	if not _held_buttons.is_empty():
		_release_buttons()
		return
	var action := String(SCRIPTED_BUTTONS[_button_index])
	_button_index = (_button_index + 1) % SCRIPTED_BUTTONS.size()
	for slot in GameConfig.player_input_configs.size():
		var device := _sim_device_of(slot)
		if device < 0:
			continue
		var binding := _joy_button_of(slot, action)
		if binding < 0:
			continue
		_held_buttons[device] = binding
		_send_button(device, binding, true)


## Device simulado do slot, ou -1 quando o slot esta no teclado ou num controle
## de verdade (nesses o roteiro nao encosta).
func _sim_device_of(slot: int) -> int:
	if not GameConfig.slot_uses_gamepad(GameConfig.player_input_configs, slot):
		return -1
	var device := int(GameConfig.player_input_configs[slot].get("device_id", -1))
	return device if sim_devices.has(device) else -1


## Botao do controle ligado a essa acao nesse slot, ou -1 quando a acao mora num
## eixo (os analogicos e o gatilho de tiro sao eixo, nao botao).
func _joy_button_of(slot: int, action: String) -> int:
	for event in InputMap.action_get_events(GameConfig.action_name(slot, action)):
		if event is InputEventJoypadButton:
			return int((event as InputEventJoypadButton).button_index)
	return -1


## Jogadores locais da partida, pegos do `local_players` do main. Ficam em cache
## porque a busca so precisa acontecer uma vez por partida.
func _local_players() -> Array:
	if not _players.is_empty() and is_instance_valid(_players[0]):
		return _players
	var scene := get_tree().current_scene
	if scene == null:
		return []
	var found: Variant = scene.get("local_players")
	if found is Array:
		_players = found as Array
	return _players


func _describe() -> String:
	var roteiro := "ligado" if _scripted else "desligado"
	var lines: Array[String] = [
		"LAB DO CONTROLE   %d jogador(es) local(is)   roteiro simulado: %s" % [GameConfig.player_input_configs.size(), roteiro],
		"TAB = liga/desliga roteiro   ESPACO = gatilho direito dos simulados",
	]
	var players := _local_players()
	if players.is_empty():
		return "\n".join(lines + ["", "esperando os jogadores locais da partida..."])
	for slot in GameConfig.player_input_configs.size():
		lines.append("")
		lines.append_array(_describe_slot(slot, players))
	return "\n".join(lines)


## Bloco de um jogador: de onde vem o comando, o que os analogicos mandaram e o
## que o boneco fez com isso.
func _describe_slot(slot: int, players: Array) -> Array[String]:
	var config: Dictionary = GameConfig.player_input_configs[slot]
	var device_type := String(config.get("device_type", "keyboard"))
	var origem := "teclado (perfil %d)" % (slot + 1)
	if device_type == "gamepad":
		var device := int(config.get("device_id", -1))
		origem = "controle %d %s" % [device, "(simulado)" if sim_devices.has(device) else "(plugado)"]
	var head := "JOGADOR %d  %s" % [slot + 1, origem]
	if slot >= players.size() or not is_instance_valid(players[slot]):
		return [head, "  (ainda sem boneco na partida)"]
	var player: Node = players[slot]
	var raw: Vector2 = GameConfig.player_look_axis(slot)
	var cursor: Vector2 = player.call("aim_cursor_position")
	var move: Vector2 = player.get("move_input")
	var carro := "dirigindo" if bool(player.call("is_driving")) else ("de carona" if bool(player.call("is_riding")) else "a pe")
	return [
		head,
		"  mira %+.2f,%+.2f   cursor %.0f,%.0f   andar %+.2f,%+.2f" % [raw.x, raw.y, cursor.x, cursor.y, move.x, move.y],
		"  %s   vida %d   %s" % [carro, int(player.get("health")), _pressed_actions(slot)],
	]


## Acoes que o jogo esta lendo apertadas nesse slot agora, em texto curto.
func _pressed_actions(slot: int) -> String:
	var pressed: Array[String] = []
	for action: String in GameConfig.ACTIONS:
		if Input.is_action_pressed(GameConfig.action_name(slot, action)):
			pressed.append(action)
	return "apertado: %s" % ", ".join(pressed) if not pressed.is_empty() else "nada apertado"


func _send_button(device: int, button_index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_axis(device: int, axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = device
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		_scripted = not _scripted
		_release_everything()
	elif key.keycode == KEY_SPACE:
		_pulling_trigger = not _pulling_trigger


## Zera eixos e solta botao preso nos simulados, senao os bonecos continuam
## andando sozinhos depois que o roteiro para.
func _release_everything() -> void:
	for device in sim_devices:
		for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_RIGHT]:
			_send_axis(device, axis, 0.0)
	_release_buttons()


func _release_buttons() -> void:
	for device: int in _held_buttons.keys():
		_send_button(device, int(_held_buttons[device]), false)
	_held_buttons.clear()
