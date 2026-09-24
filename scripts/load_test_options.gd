# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LoadTestOptions
extends RefCounted

## Opcoes de linha de comando para teste de carga do servidor dedicado.
## Uso:
##   godot --headless --path . -- --server --prespawn-zombies=600
##   var count := LoadTestOptions.prespawn_zombie_count(OS.get_cmdline_user_args())

const MAX_PRESPAWN_ZOMBIES := 2000
const MAX_PVP_BOTS := 8
const MAX_CAR_BOTS := 4


## Quantos carros dirigiveis ganham um bot motorista no servidor (0 quando
## ausente). Serve para testar a rede do carro no servidor dedicado sem um
## jogador humano: o bot dirige e o snapshot leva o movimento aos clientes.
## Uso: var count := LoadTestOptions.car_bot_count(PackedStringArray(["--car-bot=1"]))
static func car_bot_count(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if argument == "--car-bot":
			return 1
		if not argument.begins_with("--car-bot="):
			continue
		var raw_value := argument.trim_prefix("--car-bot=")
		if not raw_value.is_valid_int() or int(raw_value) < 0 or int(raw_value) > MAX_CAR_BOTS:
			push_error("Valor invalido para --car-bot: '%s'; esperado inteiro entre 0 e %d." % [raw_value, MAX_CAR_BOTS])
			return 0
		return int(raw_value)
	return 0


## Quantidade de bots de mata-mata a criar no servidor (0 quando ausente).
## Servem para jogar contra bot sem precisar de outro cliente.
## Uso: var count := LoadTestOptions.pvp_bot_count(PackedStringArray(["--pvp-bots=4"]))
static func pvp_bot_count(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if not argument.begins_with("--pvp-bots="):
			continue
		var raw_value := argument.trim_prefix("--pvp-bots=")
		if not raw_value.is_valid_int() or int(raw_value) < 0 or int(raw_value) > MAX_PVP_BOTS:
			push_error("Valor invalido para --pvp-bots: '%s'; esperado inteiro entre 0 e %d." % [raw_value, MAX_PVP_BOTS])
			return 0
		return int(raw_value)
	return 0


## Quantidade de zumbis a criar ao iniciar o servidor (0 quando ausente/invalido).
## Uso: var count := LoadTestOptions.prespawn_zombie_count(PackedStringArray(["--prespawn-zombies=600"]))
static func prespawn_zombie_count(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if not argument.begins_with("--prespawn-zombies="):
			continue
		var raw_value := argument.trim_prefix("--prespawn-zombies=")
		if not raw_value.is_valid_int() or int(raw_value) < 0 or int(raw_value) > MAX_PRESPAWN_ZOMBIES:
			push_error("Valor invalido para --prespawn-zombies: '%s'; esperado inteiro entre 0 e %d." % [raw_value, MAX_PRESPAWN_ZOMBIES])
			return 0
		return int(raw_value)
	return 0
