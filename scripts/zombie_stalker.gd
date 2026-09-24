# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieStalker
extends RefCounted

## Espreitador: quase invisivel (HIDDEN_OPACITY) ate um jogador chegar a
## REVEAL_DISTANCE; colado (POUNCE_RANGE) da o bote que fere e prende o jogador
## por PIN_SECONDS, com recarga de POUNCE_COOLDOWN.
## Uso:
##   var opacidade := ZombieStalker.reveal_opacity(distancia_do_jogador)
##   if espreitador.try_pounce(jogador, distancia, direcao): animar_ataque()

const REVEAL_DISTANCE := 6.0
const HIDDEN_OPACITY := 0.12
const POUNCE_RANGE := 2.5
const POUNCE_DAMAGE := 35
const PIN_SECONDS := 1.5
const POUNCE_COOLDOWN := 6.0

var _cooldown := 0.0


static func reveal_opacity(distance_to_player: float) -> float:
	return 1.0 if distance_to_player <= REVEAL_DISTANCE else HIDDEN_OPACITY


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Bote no jogador colado; true se atacou.
## Uso: espreitador.try_pounce(alvo, distancia, direcao)
func try_pounce(player: Node, distance: float, direction: Vector3) -> bool:
	if _cooldown > 0.0 or distance > POUNCE_RANGE or not is_instance_valid(player):
		return false
	player.call("take_damage", POUNCE_DAMAGE, direction, "melee", null)
	if player.has_method("apply_forced_move"):
		player.call("apply_forced_move", Vector3.ZERO, PIN_SECONDS)
	_cooldown = POUNCE_COOLDOWN
	return true
