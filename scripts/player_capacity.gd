class_name PlayerCapacity
extends RefCounted

## Limite de jogadores por servidor, separado da tela dividida. Antes os dois
## eram o mesmo MAX_PLAYERS = 4: nenhum servidor aceitava um 5o jogador.
## `--max-players=N` no servidor ajusta o total (benchmark de quantos jogadores
## a VPS aguenta com a horda de 200; padrao 8).
## Uso:
##   var cap := PlayerCapacity.max_players_from_arguments(OS.get_cmdline_user_args())
##   var motivo := PlayerCapacity.join_rejection(total_atual, pedidos, cap)

const MAX_LOCAL_SLOTS := 4
# 8 por decisao do dono do jogo; o benchmark na VPS (a3c2ccd) aguentou 32 com a
# horda de 200 (mediana 59-60 FPS), entao da para subir com --max-players=N.
const DEFAULT_MAX_PLAYERS := 8
const HARD_MAX_PLAYERS := 256
const MAX_PLAYERS_ARGUMENT := "--max-players="
## Do 5o jogador em diante o spawn gira em aneis em volta dos 4 marcadores.
const SPAWN_RING_STEP := 0.8
const SPAWN_RING_POINTS := 6
const MAX_SPAWN_OFFSET := 2.4


## Uso: PlayerCapacity.max_players_from_arguments(PackedStringArray(["--max-players=12"])) -> 12
static func max_players_from_arguments(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if not argument.begins_with(MAX_PLAYERS_ARGUMENT):
			continue
		var raw_value := argument.trim_prefix(MAX_PLAYERS_ARGUMENT)
		if not raw_value.is_valid_int() or int(raw_value) < 1 or int(raw_value) > HARD_MAX_PLAYERS:
			push_error("Valor invalido para %s'%s'; esperado inteiro entre 1 e %d." % [MAX_PLAYERS_ARGUMENT, raw_value, HARD_MAX_PLAYERS])
			return DEFAULT_MAX_PLAYERS
		return int(raw_value)
	return DEFAULT_MAX_PLAYERS


## Motivo da recusa para mostrar ao cliente, ou "" quando pode entrar.
## Uso: var motivo := PlayerCapacity.join_rejection(6, 2, 32)
static func join_rejection(current_total: int, requested_slots: int, max_players: int) -> String:
	if requested_slots < 1 or requested_slots > MAX_LOCAL_SLOTS:
		return "Quantidade de jogadores invalida: %d; esperado de 1 a %d por computador." % [requested_slots, MAX_LOCAL_SLOTS]
	if current_total + requested_slots > max_players:
		return "O servidor ja atingiu o limite de %d jogadores." % max_players
	return ""


## Deslocamento do spawn do slot: zero nos 4 primeiros; depois aneis de
## SPAWN_RING_POINTS pontos a cada SPAWN_RING_STEP m, ate MAX_SPAWN_OFFSET.
## Uso: player.position = marcador + PlayerCapacity.spawn_offset(slot, 4)
static func spawn_offset(slot: int, marker_count: int) -> Vector3:
	var round_index := slot / maxi(marker_count, 1)
	if round_index == 0:
		return Vector3.ZERO
	var ring := ceili(float(round_index) / SPAWN_RING_POINTS)
	var radius := minf(ring * SPAWN_RING_STEP, MAX_SPAWN_OFFSET)
	var angle := TAU * float(posmod(round_index - 1, SPAWN_RING_POINTS)) / SPAWN_RING_POINTS + ring * 0.5
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
