# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ServerTickPolicy
extends RefCounted

## Orcamento de CPU do servidor dedicado. O tick de 60 Hz entrega snapshots e
## simulacao no mesmo passo; a sonda de carga com 200 zumbis valida se a VPS
## continua dentro do orcamento antes de publicar uma atualizacao.
## - No maximo 2 passos por frame: atrasado, o servidor desacelera um pouco em
##   vez de entrar em bola de neve.
## Uso:
##   if ServerTickPolicy.is_dedicated_server(): ServerTickPolicy.apply_dedicated_tick()

const DEDICATED_PHYSICS_TICKS := 60
const DEDICATED_MAX_PHYSICS_STEPS := 2

static var _dedicated_cache := -1


## Aplica o tick reduzido no motor; chamar so no servidor dedicado.
## Uso: ServerTickPolicy.apply_dedicated_tick()
static func apply_dedicated_tick() -> void:
	Engine.physics_ticks_per_second = DEDICATED_PHYSICS_TICKS
	Engine.max_physics_steps_per_frame = DEDICATED_MAX_PHYSICS_STEPS


## Servidor dedicado = export dedicated_server ou `--server` (docker da VPS).
## Resultado guardado: consultado por zumbi a cada tick.
## Uso: if ServerTickPolicy.is_dedicated_server(): return
static func is_dedicated_server() -> bool:
	if _dedicated_cache < 0:
		var dedicated := OS.has_feature("dedicated_server") or is_dedicated_arguments(OS.get_cmdline_user_args())
		_dedicated_cache = 1 if dedicated else 0
	return _dedicated_cache == 1


## Uso: ServerTickPolicy.is_dedicated_arguments(PackedStringArray(["--server"]))
static func is_dedicated_arguments(arguments: PackedStringArray) -> bool:
	return arguments.has("--server")
