extends RefCounted

## Regressoes da identidade de build e do handshake de versao.
##
## O caso que importa: o servidor da VPS roda do FONTE dentro do container
## (o Dockerfile copia scripts/ e roda godot no /game), entao o commit dele e
## sempre "dev"; o cliente e um export com o commit injetado pelo
## build_exports.sh. Comparar commit recusaria um par compativel — foi o que
## quase quebrou o deploy. O handshake compara o BUILD DECLARADO + a versao.
## Uso: BuildInfoTests.new().run(test_root)

const BUILD_INFO_SCRIPT := preload("res://scripts/build_info.gd")


func run(test_root: Node) -> void:
	_test_describe_has_identity(test_root)
	_test_handshake_ignores_commit(test_root)
	_test_matches_rejects_other_build_and_version(test_root)


func _test_describe_has_identity(test_root: Node) -> void:
	print("Testando a linha de build dos dois lados...")
	var parsed: Variant = JSON.parse_string(BUILD_INFO_SCRIPT.describe("server"))
	if not parsed is Dictionary:
		_fail(test_root, "describe deveria devolver JSON valido; veio %s." % BUILD_INFO_SCRIPT.describe("server"))
		return
	var info := parsed as Dictionary
	for field in ["event", "role", "build", "commit", "version", "godot"]:
		if not info.has(field):
			_fail(test_root, "Linha de build sem o campo '%s': %s." % [field, info])
			return
	if String(info["event"]) != "build" or String(info["role"]) != "server":
		_fail(test_root, "Linha de build com event/role errados: %s." % info)
		return
	print("PASS: Linha de build com build %s." % info["build"])


## Servidor do fonte ("dev") e cliente export (commit injetado) tem que casar:
## o que vale e o build declarado, nao o commit.
func _test_handshake_ignores_commit(test_root: Node) -> void:
	print("Testando handshake sem depender do commit...")
	var payload: Array = BUILD_INFO_SCRIPT.handshake_payload()
	if payload.size() != 2 or String(payload[0]) != String(BUILD_INFO_SCRIPT.GAME_BUILD):
		_fail(test_root, "Handshake deveria mandar [GAME_BUILD, versao]; veio %s (GAME_BUILD=%s)." % [payload, BUILD_INFO_SCRIPT.GAME_BUILD])
		return
	if String(payload[0]) == String(BUILD_INFO_SCRIPT.COMMIT):
		_fail(test_root, "Handshake nao pode mandar o commit (%s) no lugar do build declarado." % BUILD_INFO_SCRIPT.COMMIT)
		return
	var server_build := String(BUILD_INFO_SCRIPT.GAME_BUILD)
	var server_version := String(BUILD_INFO_SCRIPT.game_version())
	var client_commit := "0000000+outro"
	if client_commit == String(BUILD_INFO_SCRIPT.COMMIT):
		_fail(test_root, "O teste precisa de um commit diferente do build; ajuste a constante.")
		return
	if not BUILD_INFO_SCRIPT.matches(server_build, server_version):
		_fail(test_root, "Mesmo build e mesma versao deveriam casar, mesmo com commits diferentes (servidor do fonte x cliente export).")
		return
	print("PASS: Handshake compara build declarado + versao.")


func _test_matches_rejects_other_build_and_version(test_root: Node) -> void:
	print("Testando recusa de build/versao diferentes...")
	if BUILD_INFO_SCRIPT.matches("build-de-outro-cliente", String(BUILD_INFO_SCRIPT.game_version())):
		_fail(test_root, "Build declarado diferente deveria ser recusado.")
		return
	if BUILD_INFO_SCRIPT.matches(String(BUILD_INFO_SCRIPT.GAME_BUILD), "9.9.9"):
		_fail(test_root, "Versao diferente deveria ser recusada.")
		return
	print("PASS: Build/versao diferentes sao recusados.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
