class_name BuildInfo
extends RefCounted

## Identidade do build. `COMMIT`/`BUILT_AT` sao reescritos por
## scripts/build_exports.sh antes de exportar (o valor versionado e o de
## desenvolvimento) e restaurados depois, igual aos templates do
## export_presets.cfg.
##
## Por que existe: um cliente de build antigo contra servidor novo falha em
## `rpc node checksum failed` e o input e recusado — o jogador simplesmente nao
## anda, sem nenhuma pista. Agora os dois lados imprimem a versao na subida e o
## servidor recusa (com mensagem clara) quem reporta build diferente ou nao
## reporta nada.
## Uso:
##   print(BuildInfo.describe("server"))
##   if not BuildInfo.matches(commit, version): recusar()

## Build declarado do jogo. SUBIR quando mudar algo que os dois lados precisam
## ter igual (RPC, formato de snapshot, regra de jogo).
##
## Comparar o commit do export NAO serve: o servidor da VPS roda do fonte dentro
## do container (Dockerfile copia scripts/ e roda godot no /game), entao o
## commit dele e sempre "dev", enquanto o cliente e um export com o commit
## injetado. Comparar commit recusaria um par perfeitamente compativel. O que
## pega o caso real (cliente velho esquecido) e o build declarado + a versao.
const GAME_BUILD := "2026-09-21.1"
const COMMIT := "dev"
const BUILT_AT := "dev"


## Versao declarada no project.godot.
## Uso: var versao := BuildInfo.game_version()
static func game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Linha JSON unica com tudo que identifica o build (vai pro log dos dois lados).
## Uso: print(BuildInfo.describe("server"))
static func describe(role: String) -> String:
	return JSON.stringify({
		"event": "build",
		"role": role,
		"build": GAME_BUILD,
		"commit": COMMIT,
		"built_at": BUILT_AT,
		"version": game_version(),
		"godot": Engine.get_version_info().string,
	})


## Texto curto para HUD/mensagem de erro.
## Uso: var texto := BuildInfo.short_text()
static func short_text() -> String:
	return "v%s build %s (commit %s)" % [game_version(), GAME_BUILD, COMMIT]


## O que vai no handshake: build declarado + versao (nunca o commit, que no
## servidor rodando do fonte e sempre "dev"). Uso:
##   var payload := BuildInfo.handshake_payload()
static func handshake_payload() -> Array:
	return [GAME_BUILD, game_version()]


## true quando o outro lado e exatamente o mesmo build.
## Uso: if not BuildInfo.matches(outro_commit, outra_versao): ...
static func matches(other_build: String, other_version: String) -> bool:
	return other_build == GAME_BUILD and other_version == game_version()
