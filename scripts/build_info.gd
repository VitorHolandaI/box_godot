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
		"commit": COMMIT,
		"built_at": BUILT_AT,
		"version": game_version(),
		"godot": Engine.get_version_info().string,
	})


## Texto curto para HUD/mensagem de erro.
## Uso: var texto := BuildInfo.short_text()
static func short_text() -> String:
	return "v%s+%s" % [game_version(), COMMIT]


## true quando o outro lado e exatamente o mesmo build.
## Uso: if not BuildInfo.matches(outro_commit, outra_versao): ...
static func matches(other_commit: String, other_version: String) -> bool:
	return other_commit == COMMIT and other_version == game_version()
