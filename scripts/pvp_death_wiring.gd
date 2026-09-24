# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PvpDeathWiring
extends Object

## Liga o sinal de morte do jogador ao handler do servidor UMA vez.
##
## `is_connected` compara Callable por objeto+metodo+argumentos atados: checar o
## Callable SEM bind nunca casa com o Callable COM bind que foi conectado, e o
## handler acabava conectado de novo a cada registro (o jogador se registra em
## dois caminhos). Resultado do bug: cada morte gerava dois `pvp_kill`, dinheiro
## e abates em dobro, e o fim de rodada por eliminacao disparava duas vezes.
##
## Uso: PvpDeathWiring.connect_once(player, self)


## Conecta `player.pvp_died` ao metodo `_on_pvp_died` de `host` com o jogador
## atado, reutilizando o mesmo Callable. Devolve true se conectou agora.
static func connect_once(player: Node, host: Object) -> bool:
	if not player.has_signal("pvp_died"):
		return false
	var handler := Callable(host, "_on_pvp_died").bind(player)
	if player.pvp_died.is_connected(handler):
		return false
	player.pvp_died.connect(handler)
	return true
