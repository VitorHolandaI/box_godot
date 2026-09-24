# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node

signal roster_changed
signal join_accepted
signal join_failed(message: String)
signal server_lost
signal latency_changed(latency_ms: int)
signal server_list_changed
## Peer terminou de carregar a cena da partida (registro em loaded_peers):
## usado para entregar estado de onda a quem reconectou no meio da horda.
signal peer_scene_loaded(peer_id: int)

const DEFAULT_PORT := 27015
const MIN_PORT := 1024
const MAX_PORT := 65535
const SERVER_ID := 1
const PING_INTERVAL := 1.0
const DEFAULT_WORLD_SEED := 240912
const DISCOVERY_PROTOCOL := "box_godot_server_discovery_v1"
const DISCOVERY_BROADCAST_ADDRESS := "255.255.255.255"
const SHOT_CAPTURE_SCRIPT := preload("res://scripts/shot_capture.gd")
const SERVER_PING_PROBE_SCRIPT := preload("res://scripts/server_ping_probe.gd")

enum Mode { OFFLINE, SERVER, CLIENT }

var mode := Mode.OFFLINE
var peer_slots: Dictionary = {}
var requested_slots := 1
var server_port := DEFAULT_PORT
## Total de jogadores aceitos pelo servidor (`--max-players=N`, padrao 8);
## a tela dividida continua limitada a PlayerCapacity.MAX_LOCAL_SLOTS.
var max_players := PlayerCapacity.DEFAULT_MAX_PLAYERS
var bot_mode := false
var autoplay_bot := false
var bot_name := ""
var loaded_peers: Dictionary = {}
var latency_ms := -1
var procedural_city_enabled := true
## Campo de testes de armas (`--armas-lab`): mapa vazio (so o chao + arena) com
## todas as armas de crate no chao. Mantem cameras/tela dividida do survival.
var weapons_lab := false
var survival_mode := true
## Mata-mata estilo CS: sem zumbis/ondas, economia e placar proprios.
var pvp_mode := false
var world_seed := DEFAULT_WORLD_SEED
## Nome padrao e nome proprio da sala de mata-mata (aparece na descoberta).
const DEFAULT_SERVER_NAME := "Box Godot"
const PVP_SERVER_NAME := "Mata-mata PVP"
var server_name := DEFAULT_SERVER_NAME
var discovered_servers: Array[Dictionary] = []
var _intentional_disconnect := false
var _connected_to_server := false
## Build reportado por cada peer (peer_id -> {"commit","version"}); e o que
## permite recusar cliente de build diferente com mensagem clara em vez do
## `rpc node checksum failed` silencioso (o input era recusado e o jogador nao
## andava). Fica vazio para quem nao reportar dentro de BUILD_REPORT_TIMEOUT.
var peer_builds: Dictionary = {}
const BUILD_REPORT_TIMEOUT := 8.0
## `--fake-build=X`: so para teste. Faz o cliente reportar um build inventado no
## handshake, que e o unico jeito barato de exercitar a recusa sem manter um
## segundo export antigo por perto (ver scripts/test_session.sh, fase 3).
var handshake_build_override := ""
var _ping_elapsed := PING_INTERVAL
var _discovery_socket: PacketPeerUDP
## Servidor filho do "Hospedar partida" (no jogo do host) e, no proprio
## servidor filho, o relogio que o encerra sem peers (`--host-idle-exit=`).
var local_host := LocalHostLauncher.new()


func _ready() -> void:
	if not _configure_session_from_arguments():
		return
	_connect_multiplayer_signals()
	if _enter_tool_scene():
		return
	if _start_dedicated_server():
		return
	_read_client_arguments()
	if _join_as_bot():
		return
	_enter_direct_offline_scene()


## Porta, capacidade, mundo e nome da sala vindos da linha de comando.
## Devolve false quando a porta e invalida e a sessao ja pediu para sair.
## Uso: if not _configure_session_from_arguments(): return
func _configure_session_from_arguments() -> bool:
	server_port = _get_command_line_port()
	max_players = PlayerCapacity.max_players_from_arguments(OS.get_cmdline_user_args())
	local_host.idle_exit_seconds = LocalHostLauncher.idle_exit_seconds_from_arguments(OS.get_cmdline_user_args())
	_reset_world_config_from_arguments()
	server_name = _get_command_line_server_name()
	if server_name == DEFAULT_SERVER_NAME and pvp_mode:
		# Sala de mata-mata sem nome escolhido: usa um nome proprio para a
		# listagem/descoberta nao mostrar "Box Godot" como se fosse sobrevivencia.
		server_name = PVP_SERVER_NAME
	if server_port < 0:
		get_tree().quit(1)
		return false
	return true


func _connect_multiplayer_signals() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Cenas de ferramenta (testes e benchmarks) entram no lugar do menu.
## Devolve true quando assumiu a cena. Uso: if _enter_tool_scene(): return
func _enter_tool_scene() -> bool:
	var tool_scenes := {
		"--unit-test": "res://scenes/test_combat_and_variants.tscn",
		"--benchmark-zombies": "res://scenes/benchmark_zombies.tscn",
		"--benchmark-indoor-escape": "res://scenes/benchmark_indoor_escape.tscn",
	}
	for flag in tool_scenes:
		if flag in OS.get_cmdline_user_args():
			get_tree().call_deferred("change_scene_to_file", tool_scenes[flag])
			return true
	return false


## Servidor dedicado: tick reduzido, socket aberto e entrada direta no mundo.
## Devolve true quando este processo e o servidor. Uso: if _start_dedicated_server(): return
func _start_dedicated_server() -> bool:
	if not ServerTickPolicy.is_dedicated_server():
		return false
	ServerTickPolicy.apply_dedicated_tick()
	var error := start_server(server_port)
	if error != OK:
		push_error("Nao foi possivel iniciar o servidor: %s" % error_string(error))
		get_tree().quit(1)
		return true
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
	return true


## Bandeiras que so o lado cliente le, antes de tentar entrar no servidor:
## `--bot-name=` (nome na sala) e `--fake-build=` (gancho de teste).
## Uso: _read_client_arguments()
func _read_client_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bot-name="):
			bot_name = argument.trim_prefix("--bot-name=").strip_edges()
		elif argument.begins_with("--fake-build="):
			handshake_build_override = argument.trim_prefix("--fake-build=").strip_edges()


## Clientes automaticos: `--bot=IP` (teste de fluxo, sai no fim) e
## `--bot-player=IP` (bot que joga de verdade). Devolve true quando entrou.
## Uso: if _join_as_bot(): return
func _join_as_bot() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bot="):
			bot_mode = true
			_configure_single_local_player()
			join_failed.connect(_on_bot_join_failed, CONNECT_ONE_SHOT)
			_join_or_quit(argument.trim_prefix("--bot="), "BOT_TEST_FAIL: %s")
			return true
		if argument.begins_with("--bot-player=") or argument == "--bot-player":
			autoplay_bot = true
			_configure_single_local_player()
			join_failed.connect(_on_autoplay_bot_join_failed, CONNECT_ONE_SHOT)
			var target_ip := argument.trim_prefix("--bot-player=") if argument.begins_with("--bot-player=") else "127.0.0.1"
			_join_or_quit(target_ip, "Falha ao conectar bot player: %s")
			return true
		if argument.begins_with("--join="):
			_configure_single_local_player()
			_join_or_quit(argument.trim_prefix("--join="), "Falha ao conectar: %s")
			return true
	return false


func _configure_single_local_player() -> void:
	var config: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
	GameConfig.configure_local_players(config)


## Entra no servidor e encerra o processo quando a conexao nem sai do chao:
## sem isso o bot/cliente ficava vivo sem sessao, sem erro visivel.
## Uso: _join_or_quit(ip, "Falha ao conectar: %s")
func _join_or_quit(target_ip: String, error_format: String) -> void:
	var error := join_server(target_ip, 1, server_port)
	if error == OK:
		return
	push_error(error_format % error_string(error))
	get_tree().quit(2)


## Modos de dev que pulam o menu e caem direto numa partida offline.
func _enter_direct_offline_scene() -> void:
	if SHOT_CAPTURE_SCRIPT.is_requested():
		# Dev (--capture): entra direto numa partida offline, sem passar pelo menu.
		leave_session()
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
		return
	if not weapons_lab:
		return
	# Campo de testes de armas: entra direto numa partida offline, sem menu.
	_configure_single_local_player()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")


func _process(delta: float) -> void:
	_poll_server_discovery()
	if is_server() and local_host.should_exit_idle(delta, multiplayer.get_peers().size()):
		print(JSON.stringify({"event": "hosted_server_idle_exit", "idle_seconds": local_host.idle_exit_seconds}))
		get_tree().quit(0)
		return
	if not is_client() or not _connected_to_server:
		return
	_ping_elapsed += delta
	if _ping_elapsed < PING_INTERVAL:
		return
	_ping_elapsed = 0.0
	_ping_request.rpc_id(SERVER_ID, Time.get_ticks_usec())


## Jogo do host fechando: o servidor filho sai junto (menu e quit passam aqui).
func _exit_tree() -> void:
	local_host.stop()


func start_server(port: int = DEFAULT_PORT) -> Error:
	leave_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_players)
	if error != OK:
		return error
	mode = Mode.SERVER
	server_port = port
	multiplayer.multiplayer_peer = peer
	var discovery_error := _open_discovery_socket(_discovery_port_for(port))
	if discovery_error != OK:
		push_error("Nao foi possivel abrir descoberta do servidor na porta %d: %s" % [_discovery_port_for(port), error_string(discovery_error)])
		return discovery_error
	print("Servidor dedicado ouvindo em UDP %d" % port)
	print(BuildInfo.describe("server"))
	return OK


func join_server(address: String, local_slots: int, port: int = DEFAULT_PORT) -> Error:
	if address.is_empty() or local_slots < 1 or local_slots > PlayerCapacity.MAX_LOCAL_SLOTS:
		return ERR_INVALID_PARAMETER
	leave_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	mode = Mode.CLIENT
	requested_slots = local_slots
	server_port = port
	multiplayer.multiplayer_peer = peer
	print("Conectando a %s:%d..." % [address, port])
	return OK


func refresh_server_list() -> Error:
	if is_server():
		return ERR_UNAVAILABLE
	var open_error := _open_discovery_socket(0)
	if open_error != OK:
		return open_error
	discovered_servers.clear()
	for saved_server in GameConfig.get_saved_servers():
		_discovered_servers_add_offline(saved_server)
	_send_discovery_request(DISCOVERY_BROADCAST_ADDRESS, DEFAULT_PORT)
	for saved_server in GameConfig.get_saved_servers():
		_send_discovery_request(String(saved_server["address"]), int(saved_server["port"]))
	server_list_changed.emit()
	return OK


func get_server_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for server in discovered_servers:
		result.append(server.duplicate(true))
	return result


func leave_session() -> void:
	_intentional_disconnect = true
	_connected_to_server = false
	_ping_elapsed = PING_INTERVAL
	latency_ms = -1
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	peer_slots.clear()
	loaded_peers.clear()
	_close_discovery_socket()
	_reset_world_config_from_arguments()
	_intentional_disconnect = false


func is_offline() -> bool:
	return mode == Mode.OFFLINE


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func local_peer_id() -> int:
	return SERVER_ID if is_offline() else multiplayer.get_unique_id()


func notify_scene_loaded() -> void:
	if is_client():
		_client_loaded.rpc_id(SERVER_ID)


func _on_connected_to_server() -> void:
	_connected_to_server = true
	_ping_elapsed = PING_INTERVAL
	print(BuildInfo.describe("client"))
	var handshake: Array = BuildInfo.handshake_payload()
	var reported_build := handshake_build_override if not handshake_build_override.is_empty() else String(handshake[0])
	_report_build.rpc_id(SERVER_ID, reported_build, String(handshake[1]))
	_request_slots.rpc_id(SERVER_ID, requested_slots)


## Servidor: novo peer entrou; se ele nao reportar o build em
## BUILD_REPORT_TIMEOUT, e build antigo (nao tem o RPC) e nao pode jogar: o
## input dele seria recusado sem explicacao.
func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return
	print("Peer %d conectando; aguardando build." % peer_id)
	_await_build_report(peer_id)


func _await_build_report(peer_id: int) -> void:
	await get_tree().create_timer(BUILD_REPORT_TIMEOUT).timeout
	if not is_server() or peer_builds.has(peer_id):
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	push_error("Peer %d nao reportou o build em %.0f s (cliente antigo?); desconectando. Servidor: %s." % [peer_id, BUILD_REPORT_TIMEOUT, BuildInfo.short_text()])
	_kick_peer(peer_id, "Build antigo/incompativel: o cliente nao reportou a versao.")


## O peer ja passou pelo handshake de build? Enquanto nao passou, nenhum RPC
## dele vale: o cliente dispara _report_build e _request_slots em sequencia
## (_on_connected_to_server), entao o pedido de vaga de quem foi recusado JA
## esta na fila e chega depois do kick. Sem esta guarda o servidor metia um peer
## desconectado no roster ("Peer N entrou com 1 jogador(es)" logo apos "Peer N
## recusado") e ainda tentava responder nele, com tres
## "Unable to send packet on channel 0, max channels: 0" no log da VPS.
## Uso: if not peer_passed_handshake(peer_builds, sender_id): return
static func peer_passed_handshake(reported_builds: Dictionary, peer_id: int) -> bool:
	return reported_builds.has(peer_id)


## Handshake de versao: recusa build diferente com mensagem legivel.
## Uso: chamado pelo cliente ao conectar (_report_build.rpc_id).
@rpc("any_peer", "call_remote", "reliable")
func _report_build(client_build: String, client_version: String) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not BuildInfo.matches(client_build, client_version):
		push_error("Build diferente: servidor %s, cliente %d reportou v%s build %s. Atualize o cliente com o mesmo build do servidor; senao o input e recusado e o jogador nao anda." % [BuildInfo.short_text(), sender_id, client_version, client_build])
		_kick_peer(sender_id, "Build do cliente diferente do servidor: v%s build %s vs %s." % [client_version, client_build, BuildInfo.short_text()])
		return
	peer_builds[sender_id] = {"build": client_build, "version": client_version}
	print("Peer %d reportou build %s (ok)." % [sender_id, client_build])


## Derruba o peer com motivo; avisa antes (se o cliente tiver o RPC) para a
## mensagem aparecer no menu dele em vez de uma queda sem explicacao.
func _kick_peer(peer_id: int, reason: String) -> void:
	_join_result.rpc_id(peer_id, false, reason, procedural_city_enabled, world_seed, survival_mode, pvp_mode)
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		peer.disconnect_peer(peer_id)
	print("Peer %d recusado: %s" % [peer_id, reason])


@rpc("any_peer", "call_remote", "reliable")
func _request_slots(slot_count: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not peer_passed_handshake(peer_builds, sender_id):
		print("Peer %d pediu vaga sem passar pelo handshake de build; ignorado." % sender_id)
		return
	var rejection := PlayerCapacity.join_rejection(_total_player_count(), slot_count, max_players)
	if not rejection.is_empty():
		_join_result.rpc_id(sender_id, false, rejection, procedural_city_enabled, world_seed, survival_mode, pvp_mode)
		return
	var requested_count := slot_count

	peer_slots[sender_id] = requested_count
	roster_changed.emit()
	_sync_roster.rpc(peer_slots)
	_join_result.rpc_id(sender_id, true, "", procedural_city_enabled, world_seed, survival_mode, pvp_mode)
	print("Peer %d entrou com %d jogador(es)." % [sender_id, requested_count])


@rpc("authority", "call_remote", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	peer_slots = new_roster.duplicate(true)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _join_result(accepted: bool, message: String, server_uses_procedural_city: bool, server_world_seed: int, server_uses_survival: bool, server_uses_pvp: bool) -> void:
	if accepted:
		procedural_city_enabled = server_uses_procedural_city
		world_seed = server_world_seed
		survival_mode = server_uses_survival
		pvp_mode = server_uses_pvp
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
		join_accepted.emit()
		return
	join_failed.emit(message)
	leave_session()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server() or not peer_slots.has(peer_id):
		return
	peer_slots.erase(peer_id)
	loaded_peers.erase(peer_id)
	peer_builds.erase(peer_id)
	roster_changed.emit()
	_sync_roster.rpc(peer_slots)
	print("Peer %d desconectou." % peer_id)


func _on_connection_failed() -> void:
	if not is_client():
		return
	join_failed.emit("Nao foi possivel conectar ao servidor.")
	leave_session()


func _on_server_disconnected() -> void:
	if _intentional_disconnect or not is_client():
		return
	leave_session()
	server_lost.emit()


func _total_player_count() -> int:
	var total := 0
	for count in peer_slots.values():
		total += int(count)
	return total


func _open_discovery_socket(listen_port: int) -> Error:
	_close_discovery_socket()
	_discovery_socket = PacketPeerUDP.new()
	var error := _discovery_socket.bind(listen_port)
	if error != OK:
		_discovery_socket = null
		return error
	_discovery_socket.set_broadcast_enabled(true)
	return OK


func _close_discovery_socket() -> void:
	if _discovery_socket == null:
		return
	_discovery_socket.close()
	_discovery_socket = null


func _send_discovery_request(address: String, game_port: int) -> void:
	if _discovery_socket == null:
		return
	var discovery_port := _discovery_port_for(game_port)
	var error := _discovery_socket.set_dest_address(address, discovery_port)
	if error != OK:
		push_error("Nao foi possivel consultar servidor '%s:%d': %s" % [address, game_port, error_string(error)])
		return
	var request := JSON.stringify({
		"protocol": DISCOVERY_PROTOCOL,
		"kind": "discover",
	})
	var send_error := _discovery_socket.put_packet(request.to_utf8_buffer())
	if send_error != OK:
		push_error("Nao foi possivel enviar consulta de servidores para '%s:%d': %s" % [address, game_port, error_string(send_error)])


func _poll_server_discovery() -> void:
	if _discovery_socket == null:
		return
	while _discovery_socket.get_available_packet_count() > 0:
		var packet := _discovery_socket.get_packet().get_string_from_utf8()
		var payload: Variant = JSON.parse_string(packet)
		if not payload is Dictionary or payload.get("protocol", "") != DISCOVERY_PROTOCOL:
			continue
		if payload.get("kind", "") == "discover" and is_server():
			_respond_to_discovery(payload)
		elif payload.get("kind", "") == "status" and not is_server():
			_register_discovered_server(payload, _discovery_socket.get_packet_ip())


func _respond_to_discovery(_request: Dictionary) -> void:
	var response := {
		"protocol": DISCOVERY_PROTOCOL,
		"kind": "status",
		"name": server_name,
		"port": server_port,
		"mission": _server_mission_name(),
		"active_players": _total_player_count(),
		"max_players": max_players,
	}
	var send_error := _discovery_socket.set_dest_address(_discovery_socket.get_packet_ip(), _discovery_socket.get_packet_port())
	if send_error != OK:
		push_error("Nao foi possivel responder descoberta de servidor: %s" % error_string(send_error))
		return
	send_error = _discovery_socket.put_packet(JSON.stringify(response).to_utf8_buffer())
	if send_error != OK:
		push_error("Nao foi possivel enviar status de servidor: %s" % error_string(send_error))


func _register_discovered_server(payload: Dictionary, source_address: String) -> void:
	var port := int(payload.get("port", 0))
	if source_address.is_empty() or port < GameConfig.MIN_SERVER_PORT or port > GameConfig.MAX_SERVER_PORT:
		return
	var key := "%s:%d" % [source_address, port]
	var ping_ms := SERVER_PING_PROBE_SCRIPT.new().measure(source_address, port)
	var entry := {
		"key": key,
		"address": source_address,
		"port": port,
		"name": String(payload.get("name", source_address)),
		"mission": String(payload.get("mission", "Desconhecida")),
		"active_players": clampi(int(payload.get("active_players", 0)), 0, PlayerCapacity.HARD_MAX_PLAYERS),
		"max_players": clampi(int(payload.get("max_players", PlayerCapacity.DEFAULT_MAX_PLAYERS)), 1, PlayerCapacity.HARD_MAX_PLAYERS),
		"ping_ms": ping_ms,
		"online": true,
		"saved": _is_saved_server(source_address, port),
	}
	for index in discovered_servers.size():
		if discovered_servers[index].get("key", "") == key:
			discovered_servers[index] = entry
			server_list_changed.emit()
			return
	discovered_servers.append(entry)
	server_list_changed.emit()


func _discovered_servers_add_offline(saved_server: Dictionary) -> void:
	var address := String(saved_server.get("address", ""))
	var port := int(saved_server.get("port", 0))
	var display_name := String(saved_server.get("label", ""))
	if display_name.is_empty():
		display_name = address
	discovered_servers.append({
		"key": "%s:%d" % [address, port],
		"address": address,
		"port": port,
		"name": display_name,
		"mission": "Sem resposta",
		"active_players": 0,
		"max_players": PlayerCapacity.DEFAULT_MAX_PLAYERS,
		"ping_ms": -1,
		"online": false,
		"saved": true,
	})


func _is_saved_server(address: String, port: int) -> bool:
	for saved_server in GameConfig.get_saved_servers():
		if String(saved_server.get("address", "")) == address and int(saved_server.get("port", 0)) == port:
			return true
	return false


func _server_mission_name() -> String:
	if pvp_mode:
		return "Mata-mata (2 times)"
	if survival_mode:
		return "Sobrevivencia"
	if procedural_city_enabled:
		return "Cidade procedural"
	return "Operacao Quarentena"


func _discovery_port_for(game_port: int) -> int:
	return game_port - 1 if game_port >= GameConfig.MAX_SERVER_PORT else game_port + 1


func _get_command_line_port() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="):
			var raw_port := argument.trim_prefix("--server-port=")
			var parsed_port := parse_server_port_value(raw_port)
			if parsed_port < 0:
				push_error("Valor de porta invalido '%s'; esperada porta decimal entre %d e %d." % [raw_port, MIN_PORT, MAX_PORT])
			return parsed_port
	return DEFAULT_PORT


func _get_command_line_server_name() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-name="):
			var configured_name := argument.trim_prefix("--server-name=").strip_edges()
			if not configured_name.is_empty():
				return configured_name
	return DEFAULT_SERVER_NAME


func _reset_world_config_from_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	var unit_test_mode := "--unit-test" in arguments
	procedural_city_enabled = not unit_test_mode and "--legacy-city" not in arguments
	survival_mode = not unit_test_mode and "--classic-mode" not in arguments
	pvp_mode = not unit_test_mode and "--pvp" in arguments
	weapons_lab = "--armas-lab" in arguments
	if weapons_lab:
		# Sem cidade, sem onda, sem PVP: so o campo de armas.
		survival_mode = false
	elif pvp_mode:
		# PVP nao tem onda de sobrevivencia: o modo substitui o survival.
		survival_mode = false
	world_seed = DEFAULT_WORLD_SEED
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--world-seed="):
			continue
		var raw_seed := argument.trim_prefix("--world-seed=")
		var parsed_seed: Variant = parse_world_seed_value(raw_seed)
		if parsed_seed == null:
			push_error("Seed procedural invalida '%s'; esperado inteiro decimal." % raw_seed)
			return
		world_seed = int(parsed_seed)
		return


func get_latency_text() -> String:
	return "--" if latency_ms < 0 else "%d ms" % latency_ms


## Autoload e instancia, entao parse_* precisa ser metodo de instancia:
## menu.gd e tests chamam via NetworkSession (singleton), nao pela classe.
func parse_server_port_value(raw_port: String) -> int:
	if raw_port.is_empty() or not raw_port.is_valid_int():
		return -1
	var parsed_port := int(raw_port)
	return parsed_port if parsed_port >= MIN_PORT and parsed_port <= MAX_PORT else -1


static func parse_world_seed_value(raw_seed: String) -> Variant:
	if raw_seed.is_valid_int():
		return int(raw_seed)
	return null


@rpc("any_peer", "call_remote", "unreliable")
func _ping_request(sent_at_usec: int) -> void:
	if not is_server() or sent_at_usec <= 0:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not peer_passed_handshake(peer_builds, sender_id):
		return
	_ping_response.rpc_id(sender_id, sent_at_usec)


@rpc("authority", "call_remote", "unreliable")
func _ping_response(sent_at_usec: int) -> void:
	if not is_client() or sent_at_usec <= 0:
		return
	var elapsed_usec := maxi(Time.get_ticks_usec() - sent_at_usec, 0)
	latency_ms = roundi(float(elapsed_usec) / 1000.0)
	latency_changed.emit(latency_ms)


@rpc("any_peer", "call_remote", "reliable")
func _client_loaded() -> void:
	if not is_server():
		return
	loaded_peers[multiplayer.get_remote_sender_id()] = true
	peer_scene_loaded.emit(multiplayer.get_remote_sender_id())


func _on_bot_join_failed(message: String) -> void:
	push_error("BOT_TEST_FAIL: %s" % message)
	get_tree().quit(2)


func _on_autoplay_bot_join_failed(message: String) -> void:
	push_error("FALHA AO CONECTAR BOT PLAYER: %s" % message)
	get_tree().quit(4)
