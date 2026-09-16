class_name ServerTickPolicy
extends RefCounted

## Orcamento de CPU do servidor dedicado. Medido na VPS (2 vCPU) com a horda de
## 200: IA dos zumbis 9-31 ms/frame, move_and_slide ~60% disso, e frames
## atrasados puxando ate 8 ticks de fisica seguidos (frame de 409 ms).
## - 30 Hz corta pela metade as chamadas de move_and_slide; snapshots saem a
##   cada 100 ms e o client ja interpola, entao 30 Hz nao aparece na tela.
## - No maximo 2 passos por frame: atrasado, o servidor desacelera um pouco em
##   vez de entrar em bola de neve.
## Uso:
##   if ServerTickPolicy.is_dedicated_server(): ServerTickPolicy.apply_dedicated_tick()

const DEDICATED_PHYSICS_TICKS := 30
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
