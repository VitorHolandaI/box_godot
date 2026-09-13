extends Node

signal roster_changed
signal join_accepted
signal join_failed(message: String)
signal server_lost
signal latency_changed(latency_ms: int)

const DEFAULT_PORT := 27015
const MIN_PORT := 1024
const MAX_PORT := 65535
const MAX_PLAYERS := 4
const SERVER_ID := 1
const PING_INTERVAL := 1.0
const DEFAULT_WORLD_SEED := 240912

enum Mode { OFFLINE, SERVER, CLIENT }

var mode := Mode.OFFLINE
var peer_slots: Dictionary = {}
var requested_slots := 1
var server_port := DEFAULT_PORT
var bot_mode := false
var autoplay_bot := false
var bot_name := ""
var loaded_peers: Dictionary = {}
var latency_ms := -1
var procedural_city_enabled := false
var world_seed := DEFAULT_WORLD_SEED
var _intentional_disconnect := false
var _connected_to_server := false
var _ping_elapsed := PING_INTERVAL


func _ready() -> void:
	server_port = _get_command_line_port()
	_reset_world_config_from_arguments()
	if server_port < 0:
		get_tree().quit(1)
		return
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if "--unit-test" in OS.get_cmdline_user_args():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/test_combat_and_variants.tscn")
		return

	if "--benchmark-zombies" in OS.get_cmdline_user_args():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/benchmark_zombies.tscn")
		return

	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		var error := start_server(server_port)
		if error != OK:
			push_error("Nao foi possivel iniciar o servidor: %s" % error_string(error))
			get_tree().quit(1)
			return
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
		return

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bot-name="):
			bot_name = argument.trim_prefix("--bot-name=").strip_edges()

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--bot="):
			bot_mode = true
			var config: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
			GameConfig.configure_local_players(config)
			join_failed.connect(_on_bot_join_failed, CONNECT_ONE_SHOT)
			var error := join_server(argument.trim_prefix("--bot="), 1, server_port)
			if error != OK:
				push_error("BOT_TEST_FAIL: %s" % error_string(error))
				get_tree().quit(2)
			return
		if argument.begins_with("--bot-player=") or argument == "--bot-player":
			autoplay_bot = true
			var target_ip := argument.trim_prefix("--bot-player=") if argument.begins_with("--bot-player=") else "127.0.0.1"
			var config: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
			GameConfig.configure_local_players(config)
			join_failed.connect(_on_autoplay_bot_join_failed, CONNECT_ONE_SHOT)
			var error := join_server(target_ip, 1, server_port)
			if error != OK:
				push_error("Falha ao conectar bot player: %s" % error_string(error))
				get_tree().quit(2)
			return


func _process(delta: float) -> void:
	if not is_client() or not _connected_to_server:
		return
	_ping_elapsed += delta
	if _ping_elapsed < PING_INTERVAL:
		return
	_ping_elapsed = 0.0
	_ping_request.rpc_id(SERVER_ID, Time.get_ticks_usec())


func start_server(port: int = DEFAULT_PORT) -> Error:
	leave_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		return error
	mode = Mode.SERVER
	server_port = port
	multiplayer.multiplayer_peer = peer
	print("Servidor dedicado ouvindo em UDP %d" % port)
	return OK


func join_server(address: String, local_slots: int, port: int = DEFAULT_PORT) -> Error:
	if address.is_empty() or local_slots < 1 or local_slots > MAX_PLAYERS:
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
	_request_slots.rpc_id(SERVER_ID, requested_slots)


@rpc("any_peer", "call_remote", "reliable")
func _request_slots(slot_count: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var requested_count := clampi(slot_count, 0, MAX_PLAYERS)
	if requested_count != slot_count or requested_count == 0:
		_join_result.rpc_id(sender_id, false, "Quantidade de jogadores invalida.", procedural_city_enabled, world_seed)
		return
	if _total_player_count() + requested_count > MAX_PLAYERS:
		_join_result.rpc_id(sender_id, false, "O servidor ja atingiu o limite de 4 jogadores.", procedural_city_enabled, world_seed)
		return

	peer_slots[sender_id] = requested_count
	roster_changed.emit()
	_sync_roster.rpc(peer_slots)
	_join_result.rpc_id(sender_id, true, "", procedural_city_enabled, world_seed)
	print("Peer %d entrou com %d jogador(es)." % [sender_id, requested_count])


@rpc("authority", "call_remote", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	peer_slots = new_roster.duplicate(true)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _join_result(accepted: bool, message: String, server_uses_procedural_city: bool, server_world_seed: int) -> void:
	if accepted:
		procedural_city_enabled = server_uses_procedural_city
		world_seed = server_world_seed
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


func _get_command_line_port() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="):
			var raw_port := argument.trim_prefix("--server-port=")
			var parsed_port := parse_server_port_value(raw_port)
			if parsed_port < 0:
				push_error("Valor de porta invalido '%s'; esperada porta decimal entre %d e %d." % [raw_port, MIN_PORT, MAX_PORT])
			return parsed_port
	return DEFAULT_PORT


func _reset_world_config_from_arguments() -> void:
	procedural_city_enabled = "--procedural-city" in OS.get_cmdline_user_args()
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


static func parse_server_port_value(raw_port: String) -> int:
	if raw_port.is_empty() or not raw_port.is_valid_int():
		return -1
	var parsed_port := int(raw_port)
	return parsed_port if parsed_port >= MIN_PORT and parsed_port <= MAX_PORT else -1


static func parse_world_seed_value(raw_seed: String) -> Variant:
	return int(raw_seed) if raw_seed.is_valid_int() else null


@rpc("any_peer", "call_remote", "unreliable")
func _ping_request(sent_at_usec: int) -> void:
	if not is_server() or sent_at_usec <= 0:
		return
	_ping_response.rpc_id(multiplayer.get_remote_sender_id(), sent_at_usec)


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


func _on_bot_join_failed(message: String) -> void:
	push_error("BOT_TEST_FAIL: %s" % message)
	get_tree().quit(2)


func _on_autoplay_bot_join_failed(message: String) -> void:
	push_error("FALHA AO CONECTAR BOT PLAYER: %s" % message)
	get_tree().quit(4)
