# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
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
## Hash da superficie de RPC; atualize junto com BuildInfo.GAME_BUILD.
const RPC_SIGNATURE := "8514a39cfa1b2b54"
## Hash dos arquivos que DEFINEM a geometria do mundo; idem.
##
## Por que existe: a cidade NAO viaja pela rede. O servidor manda so a seed
## (NetworkSession._join_result) e cada lado monta a sua com o CityGenerator,
## que roda no cliente tambem. Mudar o gerador sem subir o GAME_BUILD poe duas
## cidades diferentes na mesma partida — e, ao contrario de um RPC trocado,
## isso nao gera erro nenhum: os snapshots continuam chegando certos, num mapa
## que nao e o seu, ate alguem bater numa parede que o outro nao ve.
## Foi o furo real: a superficie de RPC ficou intacta enquanto o mundo do
## mata-mata era reescrito (casa central removida, carros de base adicionados).
##
## O hash saiu de c835f824dcd2b383 para 90d62cbe0538fc84 ao adicionar o
## cabecalho SPDX da AGPL nos 28 arquivos do gerador, e o GAME_BUILD ficou onde
## estava de proposito. O motivo do bump e "o outro joga num mapa diferente", e
## comentario nao muda mapa: o diff desses arquivos foi 56 insercoes, todas as
## duas linhas de SPDX por arquivo, com zero linha de codigo adicionada ou
## removida. Bumpar aqui so quebraria a conexao com a VPS a troco de nada.
const WORLD_SIGNATURE := "90d62cbe0538fc84"
const WORLD_FILES := [
	"res://scripts/city_generator.gd",
	"res://scripts/safehouse_builder.gd",
	"res://scripts/safehouse_roof_builder.gd",
	"res://scripts/survival_map_builder.gd",
]
const WORLD_DIRECTORIES := ["res://scripts/procedural"]


func run(test_root: Node) -> void:
	_test_describe_has_identity(test_root)
	_test_handshake_ignores_commit(test_root)
	_test_matches_rejects_other_build_and_version(test_root)
	_test_rpc_surface_matches_declared_build(test_root)
	_test_world_geometry_matches_declared_build(test_root)


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


## Guarda contra o erro que travou o multiplayer hoje: mudar RPC (nome,
## assinatura, quantidade) sem subir o BUILD DECLARADO. O cliente antigo passa
## no handshake (build igual), cai em `rpc node checksum failed` e o input e
## recusado — o jogador nao anda, sem pista. Qualquer mudanca de @rpc quebra
## este teste ate o hash ser atualizado junto com o GAME_BUILD.
func _test_rpc_surface_matches_declared_build(test_root: Node) -> void:
	print("Testando a superficie de RPC contra o build declarado...")
	var signature := _rpc_signature()
	if signature != RPC_SIGNATURE:
		_fail(test_root, "A superficie de RPC mudou (hash %s, esperado %s). Suba BuildInfo.GAME_BUILD (hoje %s) e atualize RPC_SIGNATURE em test_build_info.gd, senao cliente antigo conecta e nao anda." % [signature, RPC_SIGNATURE, BUILD_INFO_SCRIPT.GAME_BUILD])
		return
	print("PASS: Superficie de RPC igual ao build declarado (%s)." % signature)


## Guarda irma da de RPC, para o lado ESTATICO do jogo: qualquer mudanca nos
## arquivos que geram a cidade quebra este teste ate o hash ser atualizado junto
## com o GAME_BUILD. O preco e um bump ate por mudanca de comentario nesses
## arquivos; e barato perto de dois jogadores em mapas diferentes sem nenhum
## erro no log.
func _test_world_geometry_matches_declared_build(test_root: Node) -> void:
	print("Testando a geometria do mundo contra o build declarado...")
	var signature := _world_signature()
	if signature != WORLD_SIGNATURE:
		_fail(test_root, "O gerador de mundo mudou (hash %s, esperado %s). Suba BuildInfo.GAME_BUILD (hoje %s) e atualize WORLD_SIGNATURE em test_build_info.gd: a cidade nao viaja pela rede, cada lado monta a sua pela seed, entao cliente antigo joga num mapa diferente SEM nenhum erro aparecer." % [signature, WORLD_SIGNATURE, BUILD_INFO_SCRIPT.GAME_BUILD])
		return
	print("PASS: Geometria do mundo igual ao build declarado (%s)." % signature)


## Hash do conteudo dos arquivos de geracao de mundo, na ordem do caminho.
func _world_signature() -> String:
	var paths: Array[String] = []
	for path in WORLD_FILES:
		paths.append(String(path))
	for directory in WORLD_DIRECTORIES:
		paths.append_array(_gd_files(String(directory)))
	paths.sort()
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	for path in paths:
		hasher.update(path.to_utf8_buffer())
		hasher.update(FileAccess.get_file_as_bytes(path))
	return hasher.finish().hex_encode().substr(0, 16)


## Hash estavel de todas as declaracoes @rpc do projeto (arquivo + linha do
## decorador + assinatura da funcao), na ordem de caminho.
func _rpc_signature() -> String:
	var entries: Array[String] = []
	for path in _gd_files("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var lines := text.split("\n")
		for index in lines.size():
			var line := lines[index].strip_edges()
			if not line.begins_with("@rpc"):
				continue
			for next in range(index + 1, mini(index + 5, lines.size())):
				var candidate := lines[next].strip_edges()
				if candidate.begins_with("func "):
					entries.append("%s|%s|%s" % [path, line, candidate.split("->")[0].strip_edges()])
					break
	entries.sort()
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update("\n".join(entries).to_utf8_buffer())
	return hasher.finish().hex_encode().substr(0, 16)


func _gd_files(directory: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := directory.path_join(entry)
		if dir.current_is_dir():
			files.append_array(_gd_files(path))
		elif entry.ends_with(".gd"):
			files.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return files


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
