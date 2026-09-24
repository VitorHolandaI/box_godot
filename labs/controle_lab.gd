# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node

## Sobe a partida de verdade com os jogadores locais nos dispositivos pedidos e
## o painel do controle por cima. E a versao assistivel de
## `scripts/test_gamepad_aim.gd`: aqui da para ver o carro, o tiro no zumbi, a
## porta abrindo e a arma do chao sendo pega, tudo pelo controle, enquanto o
## painel mostra os mesmos numeros que o teste afirma.
##
## O primeiro controle plugado, quando existe, fica com o jogador 1. Os outros
## slots ganham controles SIMULADOS, pilotados pelo roteiro do painel: e assim
## que da para testar 4 jogadores com um controle so em casa.
##
## Uso:
##   godot --path . labs/controle_lab.tscn
##   godot --path . labs/controle_lab.tscn -- --lab-jogadores=4
##   godot --path . labs/controle_lab.tscn -- --lab-jogadores=4 --lab-so-simulado

const GAMEPAD_READOUT_SCRIPT := preload("res://labs/gamepad_readout.gd")
## Devices imaginarios: id alto para nao colidir com controle plugado de verdade.
const FIRST_SIM_DEVICE := 7


func _ready() -> void:
	GameConfig.menu_open = false
	var slots := _requested_slots()
	var real_pad := _first_real_pad()
	var configs: Array[Dictionary] = []
	var sim_devices: Array[int] = []
	for slot in slots:
		_append_slot_config(slot, slots, real_pad, configs, sim_devices)
	GameConfig.configure_local_players(configs)
	var readout := GAMEPAD_READOUT_SCRIPT.new() as CanvasLayer
	readout.name = "GamepadReadout"
	readout.set("sim_devices", sim_devices)
	# O painel mora na raiz porque a troca de cena abaixo mata esta cena inteira.
	get_tree().root.add_child.call_deferred(readout)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## Dispositivo de um slot: controle plugado no 1, teclado num slot do meio (para
## a mistura aparecer) e controle simulado no resto.
func _append_slot_config(slot: int, slots: int, real_pad: int, configs: Array[Dictionary], sim_devices: Array[int]) -> void:
	if slot == 0 and real_pad >= 0:
		configs.append(GameConfig.create_gamepad_config(real_pad))
		return
	if slots > 2 and slot == slots - 2:
		configs.append(GameConfig.create_keyboard_config(slot))
		return
	var device := FIRST_SIM_DEVICE + slot
	sim_devices.append(device)
	configs.append(GameConfig.create_gamepad_config(device))


## Quantos jogadores locais o lab sobe. Uso: -- --lab-jogadores=4
func _requested_slots() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lab-jogadores="):
			return clampi(int(argument.trim_prefix("--lab-jogadores=")), 1, PlayerCapacity.MAX_LOCAL_SLOTS)
	return 1


## Primeiro controle de verdade plugado, ou -1. `--lab-so-simulado` ignora o
## controle da maquina, para testar o caminho de quem nao tem nenhum.
func _first_real_pad() -> int:
	if OS.get_cmdline_user_args().has("--lab-so-simulado"):
		return -1
	var pads := Input.get_connected_joypads()
	return int(pads[0]) if not pads.is_empty() else -1
