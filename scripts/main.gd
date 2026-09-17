extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const ZOMBIE_RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const ZOMBIE_SPAWN_SCHEDULE_SCRIPT := preload("res://scripts/zombie_spawn_schedule.gd")
const ZOMBIE_SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
const SURVIVAL_WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const DOOR_NETWORK_STATE_SCRIPT := preload("res://scripts/door_network_state.gd")
const DOOR_STATE_REPLICATOR_SCRIPT := preload("res://scripts/door_state_replicator.gd")
const WAVE_SUPPLY_CONTROLLER_SCRIPT := preload("res://scripts/wave_supply_controller.gd")
const SUPPLY_NETWORK_STATE_SCRIPT := preload("res://scripts/supply_network_state.gd")
const AIRDROP_CONTROLLER_SCRIPT := preload("res://scripts/airdrop_controller.gd")
const AIRDROP_PLANE_SCRIPT := preload("res://scripts/airdrop_plane.gd")
const CORPSE_CLEANUP_POLICY_SCRIPT := preload("res://scripts/corpse_cleanup_policy.gd")
const ZOMBIE_SNAPSHOT_CODEC_SCRIPT := preload("res://scripts/zombie_snapshot_codec.gd")
const LOAD_TEST_OPTIONS_SCRIPT := preload("res://scripts/load_test_options.gd")
const CORPSE_CLEANUP_INTERVAL := 1.0
const MAX_LOCAL_PLAYERS := 4
const GLOBAL_ACTIVE_ZOMBIE_TARGET := 600
const MAX_CORPSES := 20
const SPAWN_INTERVAL := 1.0
const INPUT_INTERVAL := 1.0 / 30.0
const SNAPSHOT_INTERVAL := 1.0 / 10.0
## Suprimentos/armas no chao sao lentos: 2 Hz basta e mantem o pacote fino.
const GROUND_STATE_INTERVAL := 0.5
# Payload binario por RPC abaixo do MTU do ENet (~1400 bytes com cabecalhos).
const ZOMBIE_SNAPSHOT_PACKET_BYTES := 1100
# Jogadores vao em binario (PlayerSnapshotCodec, 47 bytes sem slots de arma),
# varios por pacote abaixo do MTU: antes 1 jogador (~810 bytes) por RPC por peer
# dava N x N chamadas e 7-14 ms com 24 jogadores no benchmark da VPS. Dois
# Dictionaries por pacote davam 1624 bytes (MTU 1392) e o snapshot fragmentado
# se perdia inteiro, deixando municao/vida velhas no cliente.
const PLAYER_SNAPSHOT_PACKET_BYTES := 1100
## Onda nova chega com centenas de zumbis: o cliente spawna no maximo N por
## frame (fila) para nao dar hitch de instantiates sincronos.
const MAX_ZOMBIE_SPAWNS_PER_FRAME := 2
const NETWORK_ZOMBIE_PROXY_FACTORY_SCRIPT := preload("res://scripts/network_zombie_proxy_factory.gd")
const AMMO_LOOT_DIRECTOR_SCRIPT := preload("res://scripts/ammo_loot_director.gd")
const SHARED_VISION_SCRIPT := preload("res://scripts/shared_vision.gd")
const ZOMBIE_BOSS_BRAIN_SCRIPT := preload("res://scripts/zombie_boss_brain.gd")
const ZOMBIE_SCRIPT := preload("res://scripts/zombie.gd")
const EXPLOSION_COLOR := Color(1.0, 0.45, 0.1)
const PLAYER_VISION_UPDATE_INTERVAL := 0.12
const PLAYER_SPAWN_POINTS := [
	Vector3(-13.0, 1.18, 9.5),
	Vector3(-11.0, 1.18, 9.5),
	Vector3(-13.0, 1.18, 12.5),
	Vector3(-11.0, 1.18, 12.5),
]

@onready var players_node: Node3D = $Players
@onready var zombies: Node3D = $Zombies
@onready var split_screen = $Interface/SplitScreen
@onready var sun: DirectionalLight3D = $Sun
@onready var in_game_menu: Control = $Interface/InGameMenu
# Resolvida sob demanda: a cidade em etapas cria a safehouse com call_deferred,
# depois do @onready (antes ficava null e a porta nunca abria no client).
var safehouse_door: Node = null

var local_players: Array[Node] = []
var network_players: Dictionary = {}
## Contador de nomes estaveis para pickups de arma dropada no chao.
var ground_weapon_index := 0
var corpses: Array[Node] = []
var ragdolls: Array[Node] = []
var ragdolls_by_zombie: Dictionary = {}
var spawn_index := 0
var input_elapsed := 0.0
var snapshot_elapsed := 0.0
var zombie_snapshot_sequence := 0
var received_zombie_snapshot_sequence := -1
var received_zombie_snapshot_chunks: Dictionary = {}
var received_zombie_names: Dictionary = {}
## Fila de spawn do cliente (do snapshot -> mundo aos poucos) e cache de nos.
var pending_zombie_spawns: Array[Dictionary] = []
## Nomes ja na fila: snapshots seguintes nao duplicam o mesmo zumbi pendente.
var pending_zombie_names: Dictionary = {}
## Ultimo [onda, abates, restantes] enviado; reenvia so quando muda.
var last_sent_wave_progress: Array[int] = []
var zombie_cache: Dictionary = {}
var smoke_test_mode := false
## --smoke-test-swat: chama o esquadrao perto do jogador e imprime o estado dos
## 4 soldados a cada 2 s, para testar a chamada sem esperar a onda 5.
var smoke_swat_mode := false
var smoke_swat_elapsed := 0.0
var smoke_swat_called := false
var smoke_swat_report_in := 0.0
## Alvos criados pelo smoke, para medir o dano do esquadrao.
var smoke_swat_targets: Array[Node] = []
var smoke_swat_done_in := -1.0
## Cliente: primeira posicao vista de cada soldado, para medir deslocamento.
var smoke_swat_first_seen: Dictionary = {}
## watch() do replicador de portas precisa re-agir quando a cidade em etapas
## termina de montar; false evita re-watch repetido a cada frame.
var _city_doors_watched := false
var player_vision_elapsed := 0.0
var corpse_cleanup_elapsed := 0.0
## Cadencia do sync dedicado de suprimentos/armas no chao (2 Hz).
var ground_state_elapsed := 0.0
var bot_ai := PlayerBotAI.new()
var lag_probe := NetworkLagProbe.from_arguments(OS.get_cmdline_user_args())
var flow_audit := NetworkFlowAudit.from_arguments(OS.get_cmdline_user_args())
## Custo por frame (micro travadas com a horda): perf_report a cada 5 s e
## perf_hitch em frame >= 33 ms. Substitui o antigo log de stutter >= 80 ms,
## que nao pegava a tremida constante. `--perf-probe=off` desliga.
var perf_probe := FramePerfProbe.from_arguments(OS.get_cmdline_user_args())
var zombie_spawn_schedule = ZOMBIE_SPAWN_SCHEDULE_SCRIPT.new(GLOBAL_ACTIVE_ZOMBIE_TARGET, SPAWN_INTERVAL)
var zombie_spawn_locator = ZOMBIE_SPAWN_LOCATOR_SCRIPT.new()
var survival_wave_controller
var wave_supply_controller
## Airdrop de armas por onda (crate de paraquedas) — lado autoritativo.
var airdrop_controller
## Contador de nomes estaveis dos crates de airdrop.
var crate_index := 0
## Contador de nomes estaveis dos itens de vida/municao espalhados.
var loot_index := 0
var door_state_replicator = DOOR_STATE_REPLICATOR_SCRIPT.new()
var ammo_loot_director = AMMO_LOOT_DIRECTOR_SCRIPT.new()
var player_slots_replication := PlayerSlotsReplication.new()
var player_snapshot_sequence := 0
## Esquadroes SWAT ativos: id -> {"keys": Array[String], "anchor": Node3D,
## "elapsed": float}. Cada soldado e um jogador de verdade simulado no servidor
## (ver SwatSquadBot) e replicado pelo snapshot de jogadores.
var swat_squads: Dictionary = {}
var swat_squad_index := 0
## Cerebro dos soldados: mesma IA do bot de teste, em modo esquadrao.
var swat_bot_ai := PlayerBotAI.new()
## Mata-mata (--pvp): economia, placar e respawn vivem aqui no servidor.
var pvp_match: PvpMatch = null
## Bots de PVP criados no servidor (--pvp-bots=N): chaves no dicionario de
## jogadores de rede, para o cliente enxergar eles pelo snapshot normal.
var pvp_bot_keys: Dictionary = {}
## Ids reservados dos bots (negativos, fora do sorteio do ENet).
const PVP_BOT_PEER_ID_BASE := -2000
## Contagem para comecar uma partida nova depois do fim (0 = sem partida).
var pvp_restart_left := 0.0
## Estado replicado do mata-mata para o cliente (linha de HUD e dica de compra).
var pvp_state_text := ""
var pvp_buy_open := false
var pvp_state_elapsed := 0.0
## Ultimo motivo de recusa de compra (mostrado no menu de compra do cliente).
var last_purchase_rejection := ""
## Menu de compra do cliente (tecla B), criado quando o jogador local existe.
var buy_menu: BuyMenu = null
## Gira os marcadores fixos de spawn de cada time (nao empilha os 4 no mesmo).
var pvp_spawn_counters: Array[int] = [0, 0]
const PVP_RESTART_SECONDS := 10.0
## Bases dos dois times: as DUAS safehouses do mapa (a central e a do PVP, no
## lote oposto, ~97 m uma da outra). Cada time nasce nos marcadores fixos
## PlayerSpawn1..4 da sua casa e so compra DENTRO dela.
const PVP_TEAM_SAFEHOUSES := ["CentralSafehouse", "PvpSafehouse"]
## Fallback quando a cidade nao tem a casa (modo legacy/teste).
const PVP_TEAM_BASE_FALLBACK := [Vector3(-10.5, 1.18, 10.5), Vector3(58.5, 1.18, -58.5)]
## Raio da zona de compra em volta da casa (a casa tem 12,8 m de lado).
const PVP_BASE_RADIUS := 7.0
## Rota pelas ruas entre as duas casas (ruas em -72/-48/-24/24/48/72): o bot sem
## pathfinding segue de esquina em esquina em vez de atravessar predio.
const PVP_STREET_ROUTE := [Vector3(-10.5, 1.3, 10.5), Vector3(24.0, 1.3, 24.0), Vector3(24.0, 1.3, -24.0), Vector3(48.0, 1.3, -48.0), Vector3(58.5, 1.3, -58.5)]
var loot_rng := RandomNumberGenerator.new()
## Armas soltas por zumbis ainda no chao, da mais antiga para a mais nova.
var zombie_weapon_drops: Array[Node] = []


func _ready() -> void:
	FramePerfProbe.active = perf_probe
	loot_rng.randomize()
	in_game_menu.unstuck_requested.connect(_on_unstuck_requested)
	survival_wave_controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(Callable(self, "_spawn_zombie"))
	# Debug: pula direto para onda especifica e prespawn para teste de carga
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-wave="):
			var w := int(arg.trim_prefix("--test-wave=")) - 1
			survival_wave_controller.wave_index = clampi(w, 0, survival_wave_controller.schedule.TARGETS.size() - 1)
		if arg == "--test-wave-8":
			survival_wave_controller.wave_index = 7
	if not NetworkSession.is_client() and NetworkSession.pvp_mode:
		# PVP: sem supimentos/airdrop/loot de sobrevivencia no mapa.
		pvp_match = PvpMatch.new()
	if not NetworkSession.is_client() and not NetworkSession.pvp_mode:
		wave_supply_controller = WAVE_SUPPLY_CONTROLLER_SCRIPT.new(get_tree(), NetworkSession.world_seed)
		airdrop_controller = AIRDROP_CONTROLLER_SCRIPT.new(get_tree(), NetworkSession.world_seed)
		airdrop_controller.airdrop_requested.connect(_launch_airdrop)
		# Transicao de onda escalonada: refresh de suprimentos, airdrop, loot
		# e HUD rodam em frames distintos para nao varrer 600 zumbis 4x no
		# mesmo frame (hitch de 1 frame a cada nova hora).
		survival_wave_controller.wave_started.connect(_on_wave_transition)
		wave_supply_controller.refresh_wave(survival_wave_controller.wave_index)
		_spawn_scattered_loot(survival_wave_controller.wave_index)
	var coordinator = FLOCK_COORDINATOR_SCRIPT.new()
	coordinator.name = "ZombieFlockCoordinator"
	add_child(coordinator)

	if not NetworkSession.bot_name.is_empty():
		DisplayServer.window_set_title("Box Godot - %s" % NetworkSession.bot_name)
	sun.shadow_enabled = GameConfig.uses_world_shadows()
	if NetworkSession.is_offline():
		var configs := _get_local_player_configs()
		for slot in configs.size():
			_spawn_offline_player(slot, configs[slot])
		split_screen.configure(local_players)
		# Teste offline com horda: --test-wave=8 --prespawn-zombies=200
		var offline_prespawn := LoadTestOptions.prespawn_zombie_count(OS.get_cmdline_user_args())
		if offline_prespawn > 0:
			_prespawn_load_test_zombies(offline_prespawn)
		return

	NetworkSession.roster_changed.connect(_reconcile_network_players)
	NetworkSession.server_lost.connect(_on_server_lost)
	NetworkSession.peer_scene_loaded.connect(_on_peer_scene_loaded)
	_configure_network_zombies()
	_reconcile_network_players()
	smoke_test_mode = NetworkSession.is_server() and "--smoke-test-zombie" in OS.get_cmdline_user_args()
	smoke_swat_mode = "--smoke-test-swat" in OS.get_cmdline_user_args()
	if smoke_test_mode:
		_spawn_zombie(Vector3(-8.5, 1.0, 9.5))
		var smoke_zombie := zombies.get_child(-1) as CharacterBody3D
		smoke_zombie.set("health", 35)
		smoke_zombie.set("speed", 0.0)
	if NetworkSession.is_server():
		door_state_replicator.watch(get_tree())
		_prespawn_load_test_zombies(LOAD_TEST_OPTIONS_SCRIPT.prespawn_zombie_count(OS.get_cmdline_user_args()))
		if NetworkSession.pvp_mode:
			_spawn_pvp_bots_when_ready.call_deferred(LOAD_TEST_OPTIONS_SCRIPT.pvp_bot_count(OS.get_cmdline_user_args()))
	_notify_scene_loaded.call_deferred()


## Teste de carga: enche o mundo de zumbis ja no inicio para medir rede e CPU
## sem precisar jogar ate as ondas altas.
func _prespawn_load_test_zombies(count: int) -> void:
	var spawned := 0
	for _index in count:
		if _spawn_zombie():
			spawned += 1
	if count > 0:
		print(JSON.stringify({"event": "prespawn_zombies", "requested": count, "spawned": spawned}))


func _notify_scene_loaded() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	while not _procedural_city_ready():
		# A cidade monta em etapas: o peer so entra quando o mundo completo
		# existe (predios, portas e navmesh registrados).
		await get_tree().create_timer(0.1).timeout
	NetworkSession.notify_scene_loaded()


## Nó da cidade procedural, ou null quando o modo legacy nao tem.
## Uso: var city := _city_node()
func _city_node() -> Node3D:
	return get_node_or_null("GeneratedCity") as Node3D


## Gameplay (waves, spawns de zumbi, sync) espera a montagem em etapas
## terminar; modo legacy sem cidade procedural libera direto.
## Uso: if not _procedural_city_ready(): return
func _procedural_city_ready() -> bool:
	var city := _city_node()
	if city == null:
		return true
	if city.has_method("is_city_ready"):
		return bool(city.call("is_city_ready"))
	return true


func _exit_tree() -> void:
	if FramePerfProbe.active == perf_probe:
		FramePerfProbe.active = null


## Fecha o frame na sonda e imprime as linhas JSON (relatorio/hitch).
## Uso: chamado no inicio de _process; nada a fazer manualmente.
func _finish_perf_frame(delta: float) -> void:
	if not perf_probe.enabled:
		return
	for line in perf_probe.finish_frame(delta * 1000.0, Time.get_ticks_msec(), _perf_context()):
		print(JSON.stringify(line))


## Contexto do frame para a sonda: papel, populacao e monitores do motor
## (process/physics do ultimo frame, draw calls, nos, corpos ativos).
func _perf_context() -> Dictionary:
	var role := "offline"
	if NetworkSession.is_server():
		role = "server"
	elif NetworkSession.is_client():
		role = "client"
	return {
		"role": role,
		"zombies": zombies.get_child_count(),
		"pending_spawns": pending_zombie_spawns.size(),
		"players": players_node.get_child_count(),
		"engine_process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"engine_physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"physics_active_bodies": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
	}


func _process(delta: float) -> void:
	_finish_perf_frame(delta)
	if flow_audit.is_enabled():
		flow_audit.tick(delta, self)
	if lag_probe.is_enabled():
		lag_probe.record_frame_time(delta * 1000.0)
	var perf_start := FramePerfProbe.begin()
	_update_player_vision(delta)
	FramePerfProbe.end("vision", perf_start)
	perf_start = FramePerfProbe.begin()
	_cleanup_far_ragdolls(delta)
	FramePerfProbe.end("ragdoll_cleanup", perf_start)
	if NetworkSession.is_client() or smoke_test_mode:
		return
	if not _procedural_city_ready():
		# Cidade ainda montando: nada de wave/zumbi sobre predio inexistente.
		return
	if not _city_doors_watched:
		# watch() no _ready corria com a cidade pela metade: as portas montam
		# DEPOIS e ficavam sem listener, e nenhuma mudanca replicava. Re-assina
		# os sinais com o mundo completo (watch e idempotente).
		_city_doors_watched = true
		door_state_replicator.watch(get_tree())
	if NetworkSession.pvp_mode:
		# Mata-mata nao tem zumbi: sem isso o spawner do modo classico (que roda
		# quando survival_mode e falso) enchia o mapa de zumbi durante o PVP.
		return
	if NetworkSession.survival_mode:
		_check_survival_game_over()
		if survival_wave_controller.game_over:
			if survival_wave_controller.tick_game_over(delta, not get_tree().get_nodes_in_group("player").is_empty()):
				_restart_survival()
			return
		perf_start = FramePerfProbe.begin()
		survival_wave_controller.tick(delta)
		FramePerfProbe.end("wave_spawn", perf_start)
		# Sem jogador nao ha onde espalhar (pick_clear_position gira em volta deles).
		if not get_tree().get_nodes_in_group("player").is_empty():
			_restock_class_ammo(delta)
		return
	if not zombie_spawn_schedule.is_spawn_due(delta):
		return
	var alive_count := get_tree().get_nodes_in_group("zombies").size()
	if zombie_spawn_schedule.has_capacity(alive_count) and not _spawn_zombie():
		push_warning("Spawn de zumbi adiado: nenhum ponto autorizado esta livre.")


func _physics_process(delta: float) -> void:
	perf_probe.record_physics_step()
	if NetworkSession.is_client() and NetworkSession.pvp_mode and buy_menu == null and not local_players.is_empty():
		buy_menu = BuyMenu.new()
		add_child(buy_menu)
		buy_menu.setup(local_players[0], Callable(self, "request_purchase_local"), Callable(self, "pvp_status_text"))
	if not NetworkSession.is_client():
		# Servidor e offline simulam o esquadrao; o cliente so aplica snapshot.
		_update_swat_squads(delta)
	# O smoke roda nos dois papeis: no servidor cria o esquadrao, no cliente
	# confere que os soldados aparecem e se movem.
	_tick_swat_smoke(delta)
	if pvp_match != null:
		_tick_pvp(delta)
	if NetworkSession.is_client():
		if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
			bot_ai.update(delta, get_tree())
		if lag_probe.is_enabled():
			_record_received_network_traffic()
		if lag_probe.is_enabled() and lag_probe.tick(delta, _server_round_trip_ms()):
			print(JSON.stringify(lag_probe.build_report()))
			get_tree().quit(0)
		input_elapsed += delta
		if input_elapsed >= INPUT_INTERVAL:
			input_elapsed = 0.0
			_submit_inputs.rpc_id(NetworkSession.SERVER_ID, _collect_local_inputs(delta))
		var drain_start := FramePerfProbe.begin()
		_drain_zombie_spawn_queue()
		FramePerfProbe.end("spawn_drain", drain_start)
	elif NetworkSession.is_server():
		ground_state_elapsed += delta
		if ground_state_elapsed >= GROUND_STATE_INTERVAL:
			ground_state_elapsed = 0.0
			_send_ground_states()
			_send_wave_progress()
		snapshot_elapsed += delta
		if snapshot_elapsed >= SNAPSHOT_INTERVAL:
			snapshot_elapsed = 0.0
			# So para quem ja carregou; antes um jogador carregando a cidade
			# congelava os snapshots de todos os outros ate terminar.
			if not NetworkSession.loaded_peers.is_empty():
				var snapshot_start := FramePerfProbe.begin()
				_send_door_states()
				_send_player_snapshots(_collect_player_states())
				FramePerfProbe.end("snapshot_players", snapshot_start)
				snapshot_start = FramePerfProbe.begin()
				_send_zombie_snapshots(_collect_zombie_states())
				FramePerfProbe.end("snapshot_zombies", snapshot_start)


func _record_received_network_traffic() -> void:
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null or enet_peer.host == null:
		return
	# pop_statistic zera o contador: cada chamada devolve so o trafego novo.
	var received_bytes := enet_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var received_packets := enet_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	lag_probe.record_received_traffic(int(received_bytes), int(received_packets))


func _server_round_trip_ms() -> float:
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null or enet_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return -1.0
	var server_peer := enet_peer.get_peer(NetworkSession.SERVER_ID)
	return server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if server_peer != null else -1.0


func register_corpse(corpse: Node) -> void:
	if NetworkSession.is_client() or not is_instance_valid(corpse):
		return
	corpses.append(corpse)
	if corpses.size() > MAX_CORPSES:
		# Sem tipo: o mais antigo pode ja estar liberado (horda morrendo em massa)
		# e atribuir instancia liberada a `var x: Node` dava SCRIPT ERROR (0004fbb).
		var oldest_corpse = corpses.pop_front()
		if is_instance_valid(oldest_corpse):
			oldest_corpse.queue_free()


func spawn_zombie_ragdoll(position: Vector3, rotation: float, velocity: Vector3, z_type: int = 0, appearance_hash: int = 0, source_name: String = "") -> void:
	if not source_name.is_empty() and is_instance_valid(ragdolls_by_zombie.get(source_name)):
		return
	var perf_start := FramePerfProbe.begin()
	var ragdoll := ZOMBIE_RAGDOLL_SCENE.instantiate()
	# Antes de entrar na arvore: _ready monta as partes ja no tamanho do zumbi.
	ragdoll.set("body_scale", ZombieMutator.body_scale_for(z_type))
	add_child(ragdoll)
	ragdoll.position = position
	ragdoll.rotation.y = rotation
	ragdoll.setup(velocity, z_type, appearance_hash)
	ragdolls.append(ragdoll)
	if not source_name.is_empty():
		ragdoll.set_meta("source_zombie", source_name)
		ragdolls_by_zombie[source_name] = ragdoll
	FramePerfProbe.end("ragdoll_spawn", perf_start)


## Corpos visiveis (ragdolls) so somem longe de todos os jogadores; antes o mais
## antigo sumia a partir do 21o, mesmo caido ao lado do jogador.
## Uso: chamado em _process; age a cada CORPSE_CLEANUP_INTERVAL.
func _cleanup_far_ragdolls(delta: float) -> void:
	corpse_cleanup_elapsed += delta
	if corpse_cleanup_elapsed < CORPSE_CLEANUP_INTERVAL:
		return
	corpse_cleanup_elapsed = 0.0
	ragdolls = ragdolls.filter(func(node: Variant) -> bool: return is_instance_valid(node) and not (node as Node).is_queued_for_deletion())
	var corpse_positions: Array[Vector3] = []
	for ragdoll in ragdolls:
		corpse_positions.append(_ragdoll_position(ragdoll))
	var player_positions: Array[Vector3] = []
	for player_node in get_tree().get_nodes_in_group("player"):
		player_positions.append((player_node as Node3D).global_position)
	for index in CORPSE_CLEANUP_POLICY_SCRIPT.pick_removals(corpse_positions, player_positions):
		var ragdoll: Node = ragdolls[index]
		var source := String(ragdoll.get_meta("source_zombie", ""))
		if not source.is_empty():
			ragdolls_by_zombie.erase(source)
		ragdoll.queue_free()
		ragdolls.remove_at(index)


func _ragdoll_position(ragdoll: Node) -> Vector3:
	# O torso rola para longe da origem do no ao cair.
	var torso := ragdoll.get_node_or_null("Torso") as Node3D
	return torso.global_position if torso != null else (ragdoll as Node3D).global_position


func replicate_bullet_visual(spawn_position: Vector3, bullet_direction: Vector3, pellet_count: int = 1, spread_deg: float = 0.0, weapon_kind: int = -1) -> void:
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_spawn_bullet_visual.rpc_id(int(peer_id), spawn_position, bullet_direction, pellet_count, spread_deg, weapon_kind)


## Ataque aereo pedido pelo jogador (autoridade): alvo a frente na mira.
## Uso: chamado por PlayerThrowables via has_method("call_air_strike").
func call_air_strike(caller: Node3D, direction: Vector3) -> void:
	var target := caller.global_position + direction * AirStrike.TARGET_DISTANCE
	var strike := AirStrike.new()
	add_child(strike)
	strike.setup(target, direction, true)
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_spawn_air_strike_marker.rpc_id(int(peer_id), target, direction)


@rpc("authority", "call_remote", "reliable")
func _spawn_air_strike_marker(target: Vector3, direction: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	var strike := AirStrike.new()
	add_child(strike)
	strike.setup(target, direction, false)


## SWAT pedido pelo jogador (autoridade): 4 soldados por 20 s, que sao
## jogadores de verdade simulados no servidor (IA do bot de teste, Uzi,
## municao infinita e leash do dono).
## Uso: chamado por PlayerThrowables via has_method("call_swat").
func call_swat(caller: Node3D, _direction: Vector3) -> void:
	if NetworkSession.is_client():
		return
	swat_squad_index += 1
	_enlist_swat_squad(swat_squad_index, caller)
	if not NetworkSession.is_server():
		return
	# Todos os conectados, nao so os "loaded": o esquadrao dura 20 s e quem
	# entrou agora tambem precisa ver os soldados (o snapshot so vai para
	# loaded_peers, e sem o no o cliente ignoraria os estados).
	for peer_id in multiplayer.get_peers():
		_enlist_swat_squad_rpc.rpc_id(int(peer_id), swat_squad_index)


## Cria os 4 soldados do esquadrao (servidor/offline e, pelo RPC, nos clientes).
## No cliente o dono nao existe: quem manda na posicao e o snapshot de jogadores.
func _enlist_swat_squad(squad_id: int, anchor: Node3D) -> void:
	var keys := SwatSquadBot.keys_for(squad_id)
	for index in keys.size():
		_spawn_swat_bot(keys[index], index, anchor)
	# WeakRef, nao o no: depois que o dono desconecta o objeto liberado segue no
	# dicionario e comparar/castar ele levanta "Trying to cast a freed object".
	swat_squads[squad_id] = {"keys": keys, "anchor": weakref(anchor) if is_instance_valid(anchor) else null, "elapsed": 0.0}


@rpc("authority", "call_remote", "reliable")
func _enlist_swat_squad_rpc(squad_id: int) -> void:
	if not NetworkSession.is_client():
		return
	_enlist_swat_squad(squad_id, null)


func _spawn_swat_bot(key: String, index: int, anchor: Node3D) -> void:
	var bot = PLAYER_SCENE.instantiate()
	bot.name = "SwatBot_%s" % key.replace(":", "_")
	bot.set("owner_peer_id", int(key.split(":")[0]))
	bot.local_slot = index
	bot.simulation_enabled = NetworkSession.is_server() or NetworkSession.is_offline()
	SwatSquadBot.configure(bot, index)
	var spawn_position := global_position
	if is_instance_valid(anchor):
		spawn_position = SwatSquadBot.formation_position((anchor as Node3D).global_position, index)
	bot.position = spawn_position
	players_node.add_child(bot, true)
	bot.set_spawn_position(bot.global_position)
	bot.set_color_index(index)
	if bot.simulation_enabled:
		_connect_crate_weapon_signals(bot)
		bot.equip_crate_weapon(WeaponStats.Kind.UZI)
	network_players[key] = bot


## Fim do esquadrao: libera os 4 soldados no servidor e nos clientes.
func _retire_swat_squad(squad_id: int) -> void:
	var squad_value: Variant = swat_squads.get(squad_id)
	if squad_value == null:
		return
	swat_squads.erase(squad_id)
	for key_value in (squad_value as Dictionary)["keys"]:
		var key := String(key_value)
		var bot = network_players.get(key)
		network_players.erase(key)
		player_slots_replication.forget(key)
		if is_instance_valid(bot):
			bot.queue_free()


@rpc("authority", "call_remote", "reliable")
func _retire_swat_squad_rpc(squad_id: int) -> void:
	_retire_swat_squad(squad_id)


## Avanca os esquadroes: expira quem passou do tempo e alimenta a IA de cada
## soldado no servidor. Roda no servidor/offline (quem simula o esquadrao).
## Uso: chamado em _physics_process.
func _update_swat_squads(delta: float) -> void:
	for squad_id_value in swat_squads.keys().duplicate():
		var squad_id := int(squad_id_value)
		var squad: Dictionary = swat_squads[squad_id]
		squad["elapsed"] = float(squad["elapsed"]) + delta
		if SwatSquadBot.remaining_seconds(float(squad["elapsed"])) <= 0.0:
			_retire_swat_squad(squad_id)
			if NetworkSession.is_server():
				_retire_swat_squad_rpc.rpc(squad_id)
			continue
		var anchor_ref: Variant = squad["anchor"]
		var anchor: Node3D = null
		if anchor_ref is WeakRef:
			anchor = (anchor_ref as WeakRef).get_ref() as Node3D
		if anchor_ref != null and anchor == null:
			# Dono sumiu (desconectou): o esquadrao era suporte dele e vai embora.
			_retire_swat_squad(squad_id)
			if NetworkSession.is_server():
				_retire_swat_squad_rpc.rpc(squad_id)
			continue
		var keys: Array = squad["keys"]
		for index in keys.size():
			var bot = network_players.get(String(keys[index]))
			if not is_instance_valid(bot):
				continue
			# Vaga unica por soldado: o dicionario interno da IA (strafe, preso,
			# ultima posicao) nao pode ser compartilhado entre esquadroes vivos.
			var slot := squad_id * SwatSquadBot.COUNT + index
			var input: Dictionary = swat_bot_ai.collect_squad_input(bot, anchor, zombies, slot, index, delta)
			bot.apply_network_input(input)


## Chaves criadas pelo servidor (esquadrao SWAT e bots de PVP) nao vem do
## roster de peers reais: quem cria e libera sao as rotinas proprias, e o
## reconcile tem que deixar elas em paz. A checagem e por pertencimento, nao por
## faixa de id: o ENet sorteia id de peer de 32 bits e um jogador de verdade
## pode cair no mesmo valor reservado.
func _is_reserved_player_key(key: String) -> bool:
	if pvp_bot_keys.has(key):
		return true
	for squad_value in swat_squads.values():
		if (squad_value as Dictionary)["keys"].has(key):
			return true
	return false


## Teste rapido da chamada de SWAT: espera a cidade, spawna zumbis em volta do
## primeiro jogador, chama o esquadrao e imprime o estado dos soldados.
## Uso: godot --headless --path . -- --smoke-test-swat
func _tick_swat_smoke(delta: float) -> void:
	if not smoke_swat_mode:
		return
	smoke_swat_elapsed += delta
	if NetworkSession.is_client():
		_tick_client_swat_smoke(delta)
		return
	if not smoke_swat_called:
		if smoke_swat_elapsed < 2.5 or not _procedural_city_ready():
			return
		var caller := get_tree().get_first_node_in_group("player") as Node3D
		if caller == null:
			return
		smoke_swat_targets.clear()
		var ring_offsets: Array[Vector3] = []
		for index in 6:
			var angle := TAU * float(index) / 6.0
			ring_offsets.append(Vector3(cos(angle), 0.0, sin(angle)) * 10.0)
		for offset in ring_offsets:
			if _spawn_zombie(caller.global_position + offset):
				smoke_swat_targets.append(zombies.get_child(-1))
		call_swat(caller, -caller.global_transform.basis.z)
		smoke_swat_called = true
		smoke_swat_report_in = 2.0
		print(JSON.stringify({"event": "swat_smoke_called", "squads": swat_squads.size()}))
		return
	if swat_squads.is_empty():
		# Esquadrao inteiro expirou: imprime o resumo e espera alguns segundos
		# (tempo de o cliente receber o retire) antes de fechar.
		if smoke_swat_done_in < 0.0:
			_print_swat_smoke_report()
			print(JSON.stringify({"event": "swat_smoke_done", "elapsed": snappedf(smoke_swat_elapsed, 0.1)}))
			smoke_swat_done_in = 6.0
			return
		smoke_swat_done_in -= delta
		if smoke_swat_done_in <= 0.0:
			get_tree().quit(0)
		return
	smoke_swat_report_in -= delta
	if smoke_swat_report_in > 0.0:
		return
	smoke_swat_report_in = 2.0
	_print_swat_smoke_report()


## Cliente: confere que os soldados existem AQUI (nao so no servidor) e que se
## movem. Era o que faltava: com o id de peer negativo lido como u32 o estado
## era descartado e o soldado ficava parado na origem, invisivel, sem erro
## nenhum no log. Imprime o resumo e encerra.
## Uso: godot --headless --path . -- --join=IP --server-port=P --smoke-test-swat
func _tick_client_swat_smoke(delta: float) -> void:
	var bots: Array[Node] = []
	for player_node in players_node.get_children():
		if bool(player_node.get("is_swat_bot")):
			bots.append(player_node)
	for bot in bots:
		if not smoke_swat_first_seen.has(bot.name):
			smoke_swat_first_seen[bot.name] = (bot as Node3D).global_position
	if fmod(smoke_swat_elapsed, 2.0) < delta:
		var travels: Array[float] = []
		for bot in bots:
			var start: Vector3 = smoke_swat_first_seen.get(bot.name, (bot as Node3D).global_position)
			travels.append(snappedf((bot as Node3D).global_position.distance_to(start), 0.1))
		print(JSON.stringify({"event": "swat_seen", "alive": bots.size(), "travel": travels}))
	if smoke_swat_elapsed < 8.0:
		return
	if bots.is_empty() and smoke_swat_elapsed < 20.0:
		# Sem esquadrao nenhum: nao espera para sempre (o teste tem timeout, mas
		# um smoke que trava ate ser morto nao serve de sinal).
		return
	var max_travel := 0.0
	var at_origin := 0
	for bot in bots:
		var start: Vector3 = smoke_swat_first_seen.get(bot.name, (bot as Node3D).global_position)
		var now_position := (bot as Node3D).global_position
		max_travel = maxf(max_travel, now_position.distance_to(start))
		if now_position.length() < 1.0:
			at_origin += 1
	print(JSON.stringify({
		"event": "swat_seen_done",
		"alive": bots.size(),
		"max_travel": snappedf(max_travel, 0.1),
		"at_origin": at_origin,
	}))
	get_tree().quit(0)


## Estado dos soldados: distancia do dono, arma, pente e vida.
func _print_swat_smoke_report() -> void:
	for squad_id_value in swat_squads:
		var squad: Dictionary = swat_squads[squad_id_value]
		var anchor_ref: Variant = squad["anchor"]
		var anchor: Node3D = null
		if anchor_ref is WeakRef:
			anchor = (anchor_ref as WeakRef).get_ref() as Node3D
		var keys: Array = squad["keys"]
		var rows: Array = []
		for index in keys.size():
			var bot = network_players.get(String(keys[index]))
			if not is_instance_valid(bot):
				rows.append({"index": index, "alive": false})
				continue
			var slots: WeaponSlots = bot.get("weapon_slots")
			var kind := int(bot.get("current_weapon"))
			var anchor_distance := -1.0
			if anchor != null:
				anchor_distance = bot.global_position.distance_to(anchor.global_position)
			rows.append({
				"index": index,
				"alive": true,
				"dist_anchor": snappedf(anchor_distance, 0.1),
				"weapon": kind,
				"mag": int(slots.state_of(kind).get("mag", -1)),
				"health": int(bot.get("health")),
			})
		print(JSON.stringify({
			"event": "swat_smoke",
			"squad": int(squad_id_value),
			"elapsed": snappedf(float(squad["elapsed"]), 0.1),
			"zombies": zombies.get_child_count(),
			"kills": survival_wave_controller.total_kills if survival_wave_controller != null else -1,
			"targets_hp": smoke_swat_targets.map(func(z: Node) -> int: return int(z.get("health")) if is_instance_valid(z) else -1),
			"bots": rows,
		}))


## Granada arremessada na autoridade: clientes veem o mesmo arco (so visual).
## Uso: chamado por PlayerThrowables.throw_grenade.
func replicate_thrown_grenade(start: Vector3, start_velocity: Vector3) -> void:
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_spawn_thrown_grenade.rpc_id(int(peer_id), start, start_velocity)


@rpc("authority", "call_remote", "unreliable")
func _spawn_thrown_grenade(start: Vector3, start_velocity: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	var grenade := ThrownGrenade.new()
	add_child(grenade)
	grenade.setup(start, start_velocity, false, null)


## Faca arremessada: rastro prateado rapido, sem som de tiro.
## Uso: chamado por PlayerThrowables.throw_knife.
func show_thrown_knife(origin: Vector3, direction: Vector3) -> void:
	if not ServerTickPolicy.is_dedicated_server():
		_spawn_knife_trail(origin, direction)
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_show_thrown_knife.rpc_id(int(peer_id), origin, direction)


@rpc("authority", "call_remote", "unreliable")
func _show_thrown_knife(origin: Vector3, direction: Vector3) -> void:
	if NetworkSession.is_client():
		_spawn_knife_trail(origin, direction)


func _spawn_knife_trail(origin: Vector3, direction: Vector3) -> void:
	var bullet = BULLET_SCENE.instantiate()
	add_child(bullet)
	bullet.scale = Vector3(0.35, 0.35, 1.4)
	bullet.global_position = origin + direction * 0.12
	bullet.setup(direction, 0, false)
	bullet.speed = 40.0
	bullet.lifetime = 0.5


## Zumbi pegou fogo (lanca-chamas): chamas locais e aviso aos clientes.
## Uso: chamado por zombie.ignite_spread na autoridade.
func show_zombie_burning(zombie: Node3D, seconds: float) -> void:
	WeaponConeVisual.attach_burning(zombie, seconds)
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_show_zombie_burning.rpc_id(int(peer_id), String(zombie.name), seconds)


@rpc("authority", "call_remote", "unreliable")
func _show_zombie_burning(zombie_name: String, seconds: float) -> void:
	if not NetworkSession.is_client():
		return
	WeaponConeVisual.attach_burning(zombies.get_node_or_null(zombie_name) as Node3D, seconds)


## any_peer: o visual de bala e cosmico (tracer, dano 0) e o handler roda
## apenas no cliente; modo "authority" spamava erro quando o rpc chegava
## de um peer que nao e o servidor. Uso: enviado por replicate_bullet_visual.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _spawn_bullet_visual(spawn_position: Vector3, bullet_direction: Vector3, pellet_count: int = 1, spread_deg: float = 0.0, weapon_kind: int = -1) -> void:
	if not NetworkSession.is_client():
		return
	AudioFeedback.play_gunshot(spawn_position, weapon_kind)
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		bot_ai.notify_bullet()
	if WeaponStats.stats_for(weapon_kind).has("cone_range"):
		WeaponConeVisual.spawn(self, spawn_position, bullet_direction, weapon_kind)
		return
	# Pellets recebem a MESMA matematica de leque do servidor: tracers
	# divergentes em arco, nao tracos paralelos sobrepostos (parecia 1 bala).
	var pellet_total := maxi(pellet_count, 1)
	for pellet_index in pellet_total:
		var bullet = BULLET_SCENE.instantiate()
		add_child(bullet)
		var pellet_direction := bullet_direction
		if pellet_total > 1:
			bullet.scale = Vector3(0.5, 0.5, 0.4)
			var angle_offset := deg_to_rad(spread_deg) * (float(pellet_index) - float(pellet_total - 1) / 2.0) / (float(pellet_total) / 2.0)
			pellet_direction = bullet_direction.rotated(Vector3.UP, angle_offset)
		var side := Vector3.UP.cross(pellet_direction).normalized()
		bullet.global_position = spawn_position + pellet_direction * 0.12 + side * (float(pellet_index) - float(pellet_total - 1) / 2.0) * 0.04
		bullet.setup(pellet_direction, 0, false)
		Bullet.style_tracer(bullet, weapon_kind)
		bullet.add_to_group("network_bullet_visuals")


func _spawn_offline_player(slot: int, config: Dictionary) -> void:
	var player = PLAYER_SCENE.instantiate()
	player.name = "Player%d" % (slot + 1)
	player.local_slot = slot
	player.input_action_prefix = "player_%d_" % (slot + 1)
	player.input_device_name = config["device_name"]
	player.position = _get_player_spawn_position(slot)
	player.set_color_index(slot)
	players_node.add_child(player)
	player.set_spawn_position(player.global_position)
	_connect_crate_weapon_signals(player)
	local_players.append(player)
	_register_pvp_player(player)


func _connect_crate_weapon_signals(player: Node) -> void:
	player.crate_weapon_dropped.connect(_on_crate_weapon_dropped.bind(player))
	player.crate_weapon_broken.connect(_on_crate_weapon_broken.bind(player))


## Drop da arma da mao: no servidor/offline spawna a pickup no chao; clientes
## recebem o no pelo sync por nome no snapshot. O player vem por ultimo
## porque Callable.bind() anexa o argumento atado no FIM da lista.
## Uso: conectado ao sinal crate_weapon_dropped do jogador.
func _on_crate_weapon_dropped(kind: int, mag: int, reserve: int, durability: int, player: Node) -> void:
	if NetworkSession.is_client():
		return
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	var drop_position: Vector3 = player.global_position + forward.normalized() * 1.2 if not forward.is_zero_approx() else player.global_position
	drop_position.y = player.global_position.y
	_add_ground_weapon(kind, mag, reserve, durability, drop_position)


## Cria arma no chao com nome estavel e marca o sync. Antes o drop manual nao
## marcava e os outros jogadores so viam a arma no proximo evento de chao.
func _add_ground_weapon(kind: int, mag: int, reserve: int, durability: int, drop_position: Vector3) -> GroundWeaponPickup:
	var pickup := GroundWeaponPickup.new()
	pickup.name = "GroundWeapon%d" % ground_weapon_index
	ground_weapon_index += 1
	pickup.setup(kind, mag, reserve, durability)
	add_child(pickup)
	pickup.global_position = drop_position
	GroundWeaponSync.mark_dirty()
	return pickup


## Com 30% de drop a horda solta centenas de armas: cada uma dura pouco e so as
## MAX_ZOMBIE_WEAPON_DROPS mais novas ficam, para a lista do chao (replicada
## inteira a cada mudanca) nao explodir.
func _track_zombie_weapon_drop(pickup: GroundWeaponPickup) -> void:
	pickup.lifetime_seconds = AMMO_LOOT_DIRECTOR_SCRIPT.ZOMBIE_WEAPON_LIFETIME
	zombie_weapon_drops.assign(zombie_weapon_drops.filter(func(node: Variant) -> bool: return is_instance_valid(node) and not (node as Node).is_queued_for_deletion()))
	zombie_weapon_drops.append(pickup)
	while zombie_weapon_drops.size() > AMMO_LOOT_DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS:
		var oldest: Node = zombie_weapon_drops.pop_front()
		oldest.queue_free()


## Quebra de arma de crate: peca local no simulador + evento para os clientes
## gerarem os pedacos visualmente. Uso: conectado ao sinal crate_weapon_broken.
## Mesmo contrato do drop: bind() anexa o player no fim da lista.
func _on_crate_weapon_broken(kind: int, player: Node) -> void:
	if not NetworkSession.is_server():
		return
	var player_key := ""
	for key in network_players:
		if network_players[key] == player:
			player_key = key
			break
	for peer_id in NetworkSession.loaded_peers:
		_weapon_broke.rpc_id(int(peer_id), player_key, kind, player.global_position + Vector3.UP * 1.1)


@rpc("authority", "call_remote", "reliable")
func _weapon_broke(player_key: String, _kind: int, origin: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	var player = network_players.get(player_key)
	if player != null and is_instance_valid(player):
		WeaponBreakDebris.spawn(get_tree().current_scene, origin)


## Aviao cruza o mapa BAIXO (visivel) e solta o crate no ponto sorteado; o
## crate desce de paraquedas com fisica e abre espalhando as armas no chao.
## Clientes recebem o mesmo voo cosmico por RPC.
## Uso: conectado ao sinal airdrop_requested do AirdropController.
func _launch_airdrop(drop_position: Vector3, kinds: Array[int]) -> void:
	var plane_start := drop_position + Vector3(-190.0, 16.0, -24.0)
	var plane_end := drop_position + Vector3(190.0, 16.0, 24.0)
	var plane := AirdropPlane.new()
	plane.configure(plane_start, plane_end, drop_position)
	add_child(plane)
	if not NetworkSession.is_client():
		# Partida local e servidor soltam o crate de verdade; no cliente o
		# crate chega pelo sync por nome do snapshot.
		plane.reached_drop_point.connect(_drop_airdrop_crate.bind(drop_position, kinds))
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_airdrop_flyby.rpc_id(int(peer_id), plane_start, plane_end, drop_position)


## Voo cosmico no cliente: mesmo aviao, sem soltar crate (o crate chega pelo
## sync por nome do snapshot). Uso: rpc do servidor.
@rpc("authority", "call_remote", "reliable")
func _airdrop_flyby(plane_start: Vector3, plane_end: Vector3, drop_position: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	var plane := AirdropPlane.new()
	plane.configure(plane_start, plane_end, drop_position)
	add_child(plane)


func _drop_airdrop_crate(drop_position: Vector3, kinds: Array[int]) -> void:
	var crate := AirSupplyPickup.new()
	crate.name = "AirCrate%d" % crate_index
	crate_index += 1
	crate.setup(kinds)
	# Nasce no ar (a _ready soma o DROP_HEIGHT) e desce de paraquedas.
	crate.position = Vector3(drop_position.x, 0.02, drop_position.z)
	add_child(crate)
	GroundWeaponSync.mark_dirty()


## Espalha itens de vida e municao pelas ruas a cada onda (e na partida).
## Replica por nome via GroundWeaponSync; some sozinho em 3 minutos.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func _spawn_scattered_loot(_wave_index: int = 0) -> void:
	if NetworkSession.is_client():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkSession.world_seed * 31337 + Time.get_ticks_msec()
	for item_index in 2:
		_spawn_loot_item(rng, GroundSupplyPickup.Kind.HEALTH, 35)
	for item_index in 2:
		_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO, 60)
	# Municao para CADA classe de arma de crate: um refresh completo por onda.
	_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO_SHOTGUN, 12)
	_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO_UZI, 90)
	_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO_MAGNUM, 8)
	_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO_DOUBLE_BARREL, 6)
	_spawn_loot_item(rng, GroundSupplyPickup.Kind.AMMO_CARBINE, 30)


func _spawn_loot_item(rng: RandomNumberGenerator, kind: int, amount: int) -> void:
	var position := AIRDROP_CONTROLLER_SCRIPT.pick_clear_position(get_tree(), rng, 20.0, 110.0)
	if position == AIRDROP_CONTROLLER_SCRIPT.INVALID_DROP_POSITION:
		return
	_add_loot_item(kind, amount, position)


func _add_loot_item(kind: int, amount: int, position: Vector3) -> void:
	var item := GroundSupplyPickup.new()
	item.name = "Loot%d" % loot_index
	loot_index += 1
	item.setup(kind, amount)
	add_child(item)
	GroundWeaponSync.mark_dirty()
	item.global_position = position


## Estado de onda para os clientes (hoje o HUD do cliente fica preso na
## "Hora 1"): um pacote confiavel por mudanca de onda, custo zero por frame.
func _broadcast_wave_state(wave_index: int) -> void:
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_wave_state.rpc_id(int(peer_id), wave_index, survival_wave_controller.total_kills, survival_wave_controller.alive_in_wave, survival_wave_controller.game_over)
	last_sent_wave_progress = _wave_progress()


## Restantes e abates mudam a cada morte: reenvia a 2 Hz so quando mudou, para o
## HUD do cliente nao ficar parado no valor da entrada na onda.
func _send_wave_progress() -> void:
	if not NetworkSession.survival_mode or survival_wave_controller == null:
		return
	if _wave_progress() == last_sent_wave_progress:
		return
	_broadcast_wave_state(survival_wave_controller.wave_index)


func _wave_progress() -> Array[int]:
	return [survival_wave_controller.wave_index, survival_wave_controller.total_kills, survival_wave_controller.alive_in_wave, int(survival_wave_controller.game_over)]


@rpc("authority", "call_remote", "reliable")
func _wave_state(wave_index: int, total_kills: int, alive_in_wave: int, is_game_over: bool) -> void:
	if not NetworkSession.is_client():
		return
	survival_wave_controller.set_sync_state(wave_index, total_kills, alive_in_wave, is_game_over)


func _reconcile_network_players() -> void:
	var expected: Dictionary = {}
	for peer_value in NetworkSession.peer_slots:
		var peer_id := int(peer_value)
		var slot_count := clampi(int(NetworkSession.peer_slots[peer_value]), 0, MAX_LOCAL_PLAYERS)
		for slot in slot_count:
			var key := _player_key(peer_id, slot)
			expected[key] = true
			if not network_players.has(key):
				_spawn_network_player(peer_id, slot, key)

	for key in network_players.keys():
		if expected.has(key) or _is_reserved_player_key(key):
			continue
		var player = network_players[key]
		network_players.erase(key)
		if pvp_match != null:
			pvp_match.remove_player(key)
		player_slots_replication.forget(key)
		if is_instance_valid(player):
			player.queue_free()
	_refresh_local_views()


## Peer reconectou no meio da partida: entrega o estado atual da onda na
## Alguem entrou de novo: entrega o estado da onda e, em GAME OVER, zera a
## horda e recomeca do inicio. Uso: sinal peer_scene_loaded.
func _on_peer_scene_loaded(peer_id: int) -> void:
	if not NetworkSession.is_server() or survival_wave_controller == null:
		return
	# Antes saia cedo na onda 0: quem entrava num servidor em game over na onda 0
	# nunca reiniciava a horda, e quem entrava cedo ficava sem os itens do chao.
	if pvp_bot_keys.size() > 0:
		# Quem entra no meio do mata-mata tambem precisa ver os bots.
		_spawn_pvp_bots_rpc.rpc_id(peer_id, pvp_bot_keys.size())
	if survival_wave_controller.game_over:
		_restart_survival()
	_wave_state.rpc_id(peer_id, survival_wave_controller.wave_index, survival_wave_controller.total_kills, survival_wave_controller.alive_in_wave, survival_wave_controller.game_over)
	# Peer novo precisa da lista completa de itens no chao do primeiro sync.
	SupplyNetworkState.mark_dirty()
	GroundWeaponSync.mark_dirty()


## Todo mundo caido/eliminado = GAME OVER: horda zerada (zumbis limpos,
## contadores zero) e a partida espera novo jogador entrar.
func _check_survival_game_over() -> void:
	if survival_wave_controller.game_over:
		return
	if not SURVIVAL_WAVE_CONTROLLER_SCRIPT.everyone_is_down(get_tree().get_nodes_in_group("player")):
		return
	# Ninguem de pe: zera.
	for zombie_node in zombies.get_children():
		zombie_cache.erase(String(zombie_node.name))
		zombie_node.queue_free()
	zombie_cache.clear()
	pending_zombie_spawns.clear()
	pending_zombie_names.clear()
	survival_wave_controller.trigger_game_over()
	for peer_id in NetworkSession.loaded_peers:
		_game_over.rpc_id(int(peer_id))


@rpc("authority", "call_remote", "reliable")
func _game_over() -> void:
	if NetworkSession.is_client() and NetworkSession.survival_mode:
		survival_wave_controller.trigger_game_over()


func _restart_survival() -> void:
	survival_wave_controller.restart()
	# Quem caiu volta de pe com vidas cheias; sem isso o proximo frame ja
	# disparava outro GAME OVER.
	_reset_wave_lives(0)
	_broadcast_wave_state(survival_wave_controller.wave_index)
	_spawn_scattered_loot(0)


func _spawn_network_player(peer_id: int, slot: int, key: String) -> void:
	var player = PLAYER_SCENE.instantiate()
	player.name = "Player_%d_%d" % [peer_id, slot]
	player.owner_peer_id = peer_id
	player.local_slot = slot
	player.simulation_enabled = NetworkSession.is_server()
	player.reads_local_input = false
	player.is_local_controller = peer_id == NetworkSession.local_peer_id()
	player.position = _get_player_spawn_position(network_players.size())
	player.set_color_index(network_players.size())

	if peer_id == NetworkSession.local_peer_id() and slot < GameConfig.player_input_configs.size():
		var config: Dictionary = GameConfig.player_input_configs[slot]
		player.input_action_prefix = "player_%d_" % (slot + 1)
		if NetworkSession.autoplay_bot:
			player.input_device_name = NetworkSession.bot_name if not NetworkSession.bot_name.is_empty() else "Bot"
		else:
			player.input_device_name = config["device_name"]
	else:
		player.input_device_name = "Rede"

	players_node.add_child(player, true)
	player.set_spawn_position(player.global_position)
	network_players[key] = player
	_register_pvp_player(player)
	if player.simulation_enabled:
		_connect_crate_weapon_signals(player)


func _refresh_local_views() -> void:
	local_players.clear()
	var local_id := NetworkSession.local_peer_id()
	var local_count := int(NetworkSession.peer_slots.get(local_id, 0))
	for slot in local_count:
		var player = network_players.get(_player_key(local_id, slot))
		if player != null:
			local_players.append(player)
	split_screen.configure(local_players)


func _collect_local_inputs(delta: float = 1.0 / 30.0) -> Array:
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		if NetworkSession.pvp_mode:
			return bot_ai.collect_pvp_inputs(local_players, get_tree(), delta)
		return bot_ai.collect_inputs(local_players, zombies, get_tree())
	if in_game_menu.is_open:
		return _collect_neutral_inputs()
	var states: Array = []
	for player in local_players:
		if is_instance_valid(player):
			states.append(player.get_local_input_state())
	return states


func _collect_neutral_inputs() -> Array:
	var states: Array = []
	for player in local_players:
		if not is_instance_valid(player):
			continue
		states.append({
			"slot": player.local_slot,
			"move": Vector2.ZERO,
			"jump": false,
			"sprint": false,
			"attack": false,
			"knife": false,
			"pistol": false,
			"reload": false,
		})
	return states


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_inputs(states: Array) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var allowed_slots := int(NetworkSession.peer_slots.get(sender_id, 0))
	if allowed_slots == 0 or states.size() > allowed_slots:
		return
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var slot := int(state.get("slot", -1))
		if slot < 0 or slot >= allowed_slots:
			continue
		var player = network_players.get(_player_key(sender_id, slot))
		if player != null:
			player.apply_network_input(state)


func _collect_player_states() -> Array:
	var states: Array = []
	for key in network_players:
		var player = network_players[key]
		if not is_instance_valid(player):
			continue
		var state: Dictionary = player.get_network_state()
		state["key"] = key
		states.append(state)
	return states


func _collect_zombie_states() -> Array:
	var states: Array = []
	for zombie in zombies.get_children():
		if not zombie.has_method("get_network_state"):
			continue
		var network_id := int(zombie.get_meta("network_id", -1))
		if network_id < 0:
			push_error("Zumbi '%s' sem meta network_id; esperado id atribuido em _spawn_zombie." % zombie.name)
			continue
		var state: Dictionary = zombie.get_network_state()
		state["network_id"] = network_id
		states.append(state)
	return states


## Suprimentos e itens no chao: RPC confiavel proprio a 2 Hz, so quando
## sujo. Iam no pacote de players e estouravam o MTU (1645 > 1392 bytes).
## Uso: roda via _process do servidor. Uso: _send_ground_states()
func _send_ground_states() -> void:
	if not NetworkSession.is_server():
		return
	var supply_states: Array = []
	var ground_weapons: Array = []
	if SupplyNetworkState.dirty:
		supply_states = SUPPLY_NETWORK_STATE_SCRIPT.collect(get_tree())
		SupplyNetworkState.dirty = false
	if GroundWeaponSync.dirty:
		ground_weapons = GroundWeaponSync.collect(get_tree())
		GroundWeaponSync.dirty = false
	if supply_states.is_empty() and ground_weapons.is_empty():
		return
	for peer_id in NetworkSession.loaded_peers:
		_apply_ground_snapshot.rpc_id(int(peer_id), supply_states, ground_weapons)


@rpc("authority", "call_remote", "reliable")
func _apply_ground_snapshot(supply_states: Array, ground_weapons: Array) -> void:
	if not NetworkSession.is_client():
		return
	if not supply_states.is_empty():
		SUPPLY_NETWORK_STATE_SCRIPT.apply(get_tree(), supply_states)
	if not ground_weapons.is_empty():
		GroundWeaponSync.apply(get_tree(), ground_weapons)


func _send_player_snapshots(states: Array) -> void:
	var door := _find_safehouse_door()
	var door_open := door != null and bool(door.call("is_open_requested"))
	var include_slots: Dictionary = {}
	for state_value in states:
		var state := state_value as Dictionary
		var slots: Variant = state.get("weapon_slots")
		var revision := int((slots as Dictionary).get("revision", 0)) if slots is Dictionary else 0
		var key := String(state.get("key", ""))
		if player_slots_replication.should_include(key, revision, player_snapshot_sequence):
			include_slots[key] = true
	player_snapshot_sequence += 1
	# Cada pacote e codificado uma vez; os mesmos bytes vao para todos os peers.
	for packet_states in PlayerSnapshotCodec.split_into_packets(states, include_slots, PLAYER_SNAPSHOT_PACKET_BYTES):
		var payload := PlayerSnapshotCodec.encode(packet_states, include_slots)
		for peer_id in NetworkSession.loaded_peers:
			_apply_player_snapshot.rpc_id(int(peer_id), payload, door_open)


## Portas dos predios: estado completo (confiavel) para quem acabou de carregar
## e, depois, so as mudancas. Fora do snapshot nao confiavel de jogadores.
func _send_door_states() -> void:
	var loaded_peer_ids: Array[int] = []
	for peer_id in NetworkSession.loaded_peers:
		loaded_peer_ids.append(int(peer_id))
	for peer_id in door_state_replicator.take_unsynced_peers(loaded_peer_ids):
		_apply_full_door_states.rpc_id(peer_id, DOOR_NETWORK_STATE_SCRIPT.collect(get_tree()))
	var changes: Dictionary = door_state_replicator.take_changes()
	if changes.is_empty():
		return
	for peer_id in loaded_peer_ids:
		_apply_door_changes.rpc_id(peer_id, changes)


@rpc("authority", "call_remote", "reliable")
func _apply_full_door_states(states: Dictionary) -> void:
	if NetworkSession.is_client():
		DOOR_NETWORK_STATE_SCRIPT.apply(get_tree(), states)


@rpc("authority", "call_remote", "reliable")
func _apply_door_changes(changes: Dictionary) -> void:
	if NetworkSession.is_client():
		DOOR_NETWORK_STATE_SCRIPT.apply_changes(get_tree(), changes)


func _send_zombie_snapshots(states: Array) -> void:
	var packets: Array[Array] = ZOMBIE_SNAPSHOT_CODEC_SCRIPT.split_into_packets(states, ZOMBIE_SNAPSHOT_PACKET_BYTES)
	for packet_index in packets.size():
		var payload: PackedByteArray = ZOMBIE_SNAPSHOT_CODEC_SCRIPT.encode(packets[packet_index])
		for peer_id in NetworkSession.loaded_peers:
			_apply_zombie_snapshot.rpc_id(int(peer_id), payload, zombie_snapshot_sequence, packet_index, packets.size())
	zombie_snapshot_sequence += 1


## Porta da safehouse central, guardada assim que a cidade em etapas a cria.
## Uso: var door := _find_safehouse_door()
func _find_safehouse_door() -> Node:
	if is_instance_valid(safehouse_door):
		return safehouse_door
	safehouse_door = get_node_or_null("GeneratedCity/CentralSafehouse/SafehouseDoor")
	return safehouse_door


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_player_snapshot(payload: PackedByteArray, door_open: bool) -> void:
	if not NetworkSession.is_client():
		return
	var door := _find_safehouse_door()
	if door != null:
		door.call("apply_network_open_state", door_open)
	for state in PlayerSnapshotCodec.decode(payload):
		var player = network_players.get(String(state.get("key", "")))
		if player != null:
			player.apply_network_state(state)
			bot_ai.notify_player_state(state, player in local_players)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_zombie_snapshot(
		payload: PackedByteArray,
		snapshot_sequence: int,
		packet_index: int,
		packet_count: int
) -> void:
	if not NetworkSession.is_client():
		return
	if snapshot_sequence < received_zombie_snapshot_sequence or packet_count <= 0:
		return
	if packet_index < 0 or packet_index >= packet_count:
		return
	if snapshot_sequence > received_zombie_snapshot_sequence:
		received_zombie_snapshot_sequence = snapshot_sequence
		received_zombie_snapshot_chunks.clear()
		received_zombie_names.clear()
	received_zombie_snapshot_chunks[packet_index] = true
	var apply_start := FramePerfProbe.begin()
	var zombie_states: Array[Dictionary] = ZOMBIE_SNAPSHOT_CODEC_SCRIPT.decode(payload)
	if lag_probe.is_enabled():
		lag_probe.record_zombie_packet(snapshot_sequence, packet_index, packet_count, zombie_states.size(), Time.get_ticks_usec())
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		bot_ai.notify_zombie_states(zombie_states)
	_apply_zombie_states(zombie_states)
	if received_zombie_snapshot_chunks.size() == packet_count:
		_remove_missing_network_zombies()
	FramePerfProbe.end("snapshot_apply", apply_start)


func _apply_zombie_states(states: Array) -> void:
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var zombie_name := String(state.get("name", ""))
		if zombie_name.is_empty() or zombie_name.length() > 64:
			continue
		received_zombie_names[zombie_name] = true
		var zombie := _client_zombie_by_name(zombie_name)
		if zombie == null:
			# Fila: novos zumbis entram no mundo aos poucos (no maximo N por
			# frame) para a nova onda nao instanciar centenas num frame so.
			if pending_zombie_spawns.size() < 512 and not pending_zombie_names.has(zombie_name):
				pending_zombie_spawns.append({"name": zombie_name, "state": state})
				pending_zombie_names[zombie_name] = true
			continue
		zombie.apply_network_state(state)


func _client_zombie_by_name(zombie_name: String) -> Node:
	var cached: Variant = zombie_cache.get(zombie_name)
	if cached != null and is_instance_valid(cached):
		return cached
	var zombie := zombies.get_node_or_null(NodePath(zombie_name))
	if zombie != null:
		zombie_cache[zombie_name] = zombie
	return zombie


## Descarrega a fila de spawns do cliente no maximo N por frame.
func _drain_zombie_spawn_queue() -> void:
	if pending_zombie_spawns.is_empty():
		return
	var spawned := 0
	while spawned < MAX_ZOMBIE_SPAWNS_PER_FRAME and not pending_zombie_spawns.is_empty():
		var entry: Dictionary = pending_zombie_spawns.pop_front()
		var zombie_name := String(entry["name"])
		pending_zombie_names.erase(zombie_name)
		if _client_zombie_by_name(zombie_name) != null:
			continue
		var state: Dictionary = entry["state"]
		var zombie: CharacterBody3D = NETWORK_ZOMBIE_PROXY_FACTORY_SCRIPT.instantiate_proxy(ZOMBIE_SCENE, zombie_name, state)
		zombies.add_child(zombie, true)
		zombie_cache[zombie_name] = zombie
		var initial_position: Variant = state.get("position")
		if initial_position is Vector3:
			zombie.global_position = initial_position
		zombie.apply_network_state(state)
		spawned += 1


func _remove_missing_network_zombies() -> void:
	for zombie in zombies.get_children():
		if not received_zombie_names.has(String(zombie.name)):
			zombie_cache.erase(String(zombie.name))
			zombie.queue_free()


func _configure_network_zombies() -> void:
	if not NetworkSession.is_client():
		return
	for zombie in zombies.get_children():
		zombie.simulation_enabled = false


func _spawn_zombie(position_override: Variant = null, variant_override: int = -1) -> bool:
	var spawn_position: Vector3 = position_override as Vector3 if position_override is Vector3 else zombie_spawn_locator.pick_spawn_position(get_tree())
	if spawn_position == ZOMBIE_SPAWN_LOCATOR_SCRIPT.INVALID_SPAWN_POSITION:
		return false
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "%s%d" % [ZOMBIE_SNAPSHOT_CODEC_SCRIPT.NAME_PREFIX, spawn_index]
	zombie.set_meta("network_id", spawn_index)
	# Sobrevivencia: a onda sorteia a variante (mix percentual por fase) e o
	# hash sincroniza o visual para os clientes pelo snapshot.
	if variant_override >= 0:
		zombie.set("forced_variant", variant_override)
	elif NetworkSession.survival_mode and survival_wave_controller != null:
		var roll := posmod(spawn_index * 37 + NetworkSession.world_seed * 13, 100)
		zombie.set("forced_variant", survival_wave_controller.schedule.pick_variant(survival_wave_controller.wave_index, roll))
	zombies.add_child(zombie, true)
	zombie.died.connect(_on_zombie_died.bind(zombie))
	zombie.stranded.connect(_on_zombie_stranded)
	zombie.boss_ability_used.connect(_on_boss_ability_used)
	zombie.spit_used.connect(_on_spit_used)
	zombie.global_position = spawn_position
	spawn_index += 1
	return true


## Botao do menu: na partida local destrava na hora; online pede ao servidor,
## que e quem simula o boneco, e a posicao nova chega pelo snapshot.
func _on_unstuck_requested() -> void:
	if NetworkSession.is_client():
		_request_unstuck.rpc_id(NetworkSession.SERVER_ID)
		return
	for player in local_players:
		if is_instance_valid(player):
			player.unstuck()


@rpc("any_peer", "call_remote", "reliable")
func _request_unstuck() -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	for slot in int(NetworkSession.peer_slots.get(sender_id, 0)):
		var player = network_players.get(_player_key(sender_id, slot))
		if player != null and is_instance_valid(player):
			player.unstuck()


func _on_zombie_stranded(zombie: Node) -> void:
	var new_position := zombie_spawn_locator.pick_spawn_position(get_tree())
	if new_position == ZOMBIE_SPAWN_LOCATOR_SCRIPT.INVALID_SPAWN_POSITION or not is_instance_valid(zombie):
		return
	zombie.relocate(new_position)
	print(JSON.stringify({"event": "zombie_relocated", "zombie": String(zombie.name), "position": [snappedf(new_position.x, 0.1), snappedf(new_position.z, 0.1)]}))


func _on_zombie_died(_killer: Node, zombie: Node3D) -> void:
	if NetworkSession.survival_mode:
		survival_wave_controller.register_death()
	_drop_kill_ammo(zombie)


## Zumbi abatido solta de vez em quando municao de qualquer classe e, mais raro,
## uma arma de crate usada, no lugar da morte.
func _drop_kill_ammo(zombie: Node3D) -> void:
	if NetworkSession.is_client() or not is_instance_valid(zombie):
		return
	var ground_position := Vector3(zombie.global_position.x, 0.02, zombie.global_position.z)
	var weapon: Dictionary = AMMO_LOOT_DIRECTOR_SCRIPT.weapon_drop_for_kill(loot_rng.randf(), loot_rng.randf(), loot_rng.randf())
	if not weapon.is_empty():
		var pickup := _add_ground_weapon(int(weapon["kind"]), int(weapon["mag"]), int(weapon["reserve"]), int(weapon["durability"]), ground_position)
		_track_zombie_weapon_drop(pickup)
	var supply_kind: int = AMMO_LOOT_DIRECTOR_SCRIPT.drop_kind_for_kill(loot_rng.randf(), loot_rng.randf())
	if supply_kind < 0:
		return
	_add_loot_item(supply_kind, AMMO_LOOT_DIRECTOR_SCRIPT.drop_amount_for(supply_kind), ground_position)


## Reposicao periodica: completa o minimo de municao de cada classe no mapa.
func _restock_class_ammo(delta: float) -> void:
	if not ammo_loot_director.is_restock_due(delta):
		return
	for supply_kind in AMMO_LOOT_DIRECTOR_SCRIPT.kinds_to_restock(AMMO_LOOT_DIRECTOR_SCRIPT.count_supplies(get_tree())):
		_spawn_loot_item(loot_rng, supply_kind, AMMO_LOOT_DIRECTOR_SCRIPT.amount_for(supply_kind))


## Cada nova onda devolve 3 vidas a todos os jogadores, inclusive os que
## haviam sido eliminados. O cliente recebe o novo estado pelos snapshots.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func _reset_wave_lives(_wave_index: int) -> void:
	if NetworkSession.is_client():
		return
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or not is_instance_valid(player) or not player.has_method("restore_wave_lives"):
			continue
		if players_node != null and not players_node.is_ancestor_of(player):
			continue
		player.restore_wave_lives()


func get_survival_hud_text() -> String:
	if NetworkSession.pvp_mode:
		# No servidor/offline o texto sai da partida; no cliente vem replicado.
		return pvp_match.hud_text() if pvp_match != null else pvp_state_text
	return survival_wave_controller.get_hud_text() if NetworkSession.survival_mode else ""


## Teste jogador vs bot: cria `count` jogadores de verdade simulados no
## servidor, cacando os outros (mesma IA de PVP dos clientes bot). O cliente
## ve eles como qualquer jogador, pelo snapshot.
## Uso: godot --headless --path . -- --server --pvp --pvp-bots=4
## Espera a cidade montar (as safehouses nascem na montagem em etapas) para
## criar os bots ja nos marcadores fixos da casa do time deles.
## Uso: _spawn_pvp_bots_when_ready.call_deferred(count)
func _spawn_pvp_bots_when_ready(count: int) -> void:
	while not _procedural_city_ready():
		await get_tree().create_timer(0.1).timeout
	_spawn_pvp_bots(count)


func _spawn_pvp_bots(count: int) -> void:
	if not NetworkSession.pvp_mode or count <= 0:
		return
	for index in count:
		_create_pvp_bot(index, NetworkSession.is_server() or NetworkSession.is_offline())
	# O cliente so cria jogador do roster de peers; os bots sao do servidor,
	# entao precisam deste RPC para existir do outro lado (senao o estado deles
	# chega no snapshot e nao ha no para receber: o humano nao ve os bots).
	if NetworkSession.is_server():
		for peer_id in multiplayer.get_peers():
			_spawn_pvp_bots_rpc.rpc_id(int(peer_id), count)
	print(JSON.stringify({"event": "pvp_bots_spawned", "count": pvp_bot_keys.size()}))


@rpc("authority", "call_remote", "reliable")
func _spawn_pvp_bots_rpc(count: int) -> void:
	if not NetworkSession.is_client():
		return
	for index in count:
		_create_pvp_bot(index, false)


## Cria (ou reaproveita) o no de um bot de PVP. `simulate` so no servidor: no
## cliente o bot e um proxy como qualquer jogador de rede.
## Uso: _create_pvp_bot(0, NetworkSession.is_server())
func _create_pvp_bot(index: int, simulate: bool) -> void:
	var key := "%d:%d" % [PVP_BOT_PEER_ID_BASE - index, 0]
	if pvp_bot_keys.has(key):
		return
	var bot = PLAYER_SCENE.instantiate()
	bot.name = "PvpBot_%d" % index
	bot.local_slot = index
	bot.simulation_enabled = simulate
	bot.owner_peer_id = PVP_BOT_PEER_ID_BASE - index
	bot.reads_local_input = false
	bot.is_local_controller = false
	bot.position = _get_player_spawn_position(index + 1)
	players_node.add_child(bot, true)
	bot.set_spawn_position(bot.global_position)
	bot.set_color_index(index + 1)
	bot.set("input_device_name", "Bot PVP %d" % (index + 1))
	if simulate:
		bot.reset_pvp_loadout()
	network_players[key] = bot
	pvp_bot_keys[key] = true
	if simulate:
		_register_pvp_player(bot)
		# O time so existe depois do register: e ele que decide a casa/marcador.
		bot.global_position = _pvp_spawn_position_for(bot)
		bot.set_spawn_position(bot.global_position)


## Alimenta a IA dos bots de PVP (servidor simula; o cliente so ve o snapshot).
func _tick_pvp_bots(delta: float) -> void:
	var slot := 0
	for key in pvp_bot_keys.keys().duplicate():
		var bot = network_players.get(key)
		if not is_instance_valid(bot):
			pvp_bot_keys.erase(key)
			network_players.erase(key)
			if pvp_match != null:
				pvp_match.remove_player(String(key))
			continue
		if bool(bot.get("is_eliminated")):
			continue
		_pvp_bot_try_buy(bot)
		var rumo := _pvp_bot_hunt_position(bot)
		bot.apply_network_input(bot_ai.collect_pvp_input(bot, get_tree(), slot, delta, rumo))
		slot += 1


## Proxima esquina da rota do bot ate o lado inimigo (anda para a frente quando
## chega perto). Sem rota definida para o time, devolve a base inimiga.
## Uso: var rumo := _pvp_bot_hunt_position(bot)
func _pvp_bot_hunt_position(bot: Node) -> Vector3:
	if pvp_match == null or not is_instance_valid(bot):
		return _pvp_team_base(1)
	var team: int = pvp_match.team_of(_key_for_player(bot))
	var enemy_team := 0 if team == 1 else 1
	var route: Array = PVP_STREET_ROUTE if team == 0 else _reversed_route()
	var position := (bot as Node3D).global_position
	# Indice de progresso: a ultima esquina alcancada manda; o alvo e a SEGUINTE.
	# Antes o alvo era a primeira esquina a mais de 8 m — que e a propria base —
	# e o bot voltava pra casa em circulo.
	var progress := 0
	for index in route.size():
		if position.distance_to(route[index]) <= 10.0:
			progress = index
	var next_index: int = mini(progress + 1, route.size() - 1)
	var next_waypoint: Vector3 = route[next_index]
	if team == 1:
		# Rota invertida termina na base do time 0; ultimo alvo e a base inimiga.
		pass
	return next_waypoint if next_waypoint != position else _pvp_team_base(enemy_team)


func _reversed_route() -> Array:
	var route: Array = []
	for index in range(PVP_STREET_ROUTE.size() - 1, -1, -1):
		route.append(PVP_STREET_ROUTE[index])
	return route


## Bot compra na fase de compra, na propria base, a arma mais cara que couber.
## E o mesmo caminho do humano (money -> spend -> equipar), so sem menu.
## Uso: chamado no _tick_pvp_bots.
func _pvp_bot_try_buy(bot: Node) -> void:
	if pvp_match == null or pvp_match.phase != PvpMatch.Phase.BUY:
		return
	if not _pvp_in_buy_zone(bot):
		return
	var key := _key_for_player(bot)
	if key.is_empty():
		return
	var wanted := 0
	var wanted_price := pvp_match.money_of(key)
	for kind in WeaponStats.purchasable_kinds():
		var price := WeaponStats.price_for(kind)
		if price <= wanted_price and price > WeaponStats.price_for(wanted):
			wanted = int(kind)
			wanted_price = price
	if wanted == 0 or WeaponStats.price_for(wanted) > pvp_match.money_of(key):
		return
	if bot.has_crate_weapon(wanted):
		return
	var rejection := request_purchase(bot, wanted)
	if not rejection.is_empty():
		return
	print(JSON.stringify({"event": "pvp_buy", "key": key, "kind": wanted, "price": WeaponStats.price_for(wanted)}))


## Entra na partida de PVP com a economia inicial e a janela de compra aberta.
## Uso: chamado no spawn de cada jogador (servidor/offline).
func _register_pvp_player(player: Node) -> void:
	if pvp_match == null or not is_instance_valid(player):
		return
	var key := _key_for_player(player)
	if key.is_empty():
		return
	pvp_match.register_player(key)
	player.set("pvp_money", pvp_match.money_of(key))
	if not player.pvp_died.is_connected(_on_pvp_died):
		player.pvp_died.connect(_on_pvp_died.bind(player))


## Chave de rede do jogador ("" quando nao esta no dicionario).
## Uso: var key := _key_for_player(player)
func _key_for_player(player: Node) -> String:
	for key in network_players:
		if network_players[key] == player:
			return String(key)
	return ""


## Abate no mata-mata: credita quem matou, conta a morte e encerra a partida
## quando alguem chega no alvo. Callable.bind anexa a vitima no FIM.
## Uso: conectado ao sinal pvp_died de cada jogador.
func _on_pvp_died(killer: Node, victim: Node) -> void:
	if pvp_match == null:
		return
	var killer_key := _key_for_player(killer) if is_instance_valid(killer) else ""
	var victim_key := _key_for_player(victim)
	if victim_key.is_empty():
		return
	pvp_match.register_kill(killer_key, victim_key)
	print(JSON.stringify({"event": "pvp_kill", "killer": killer_key, "victim": victim_key, "team_kills": pvp_match.kills_of(killer_key)}))
	_check_pvp_round_end()


## A rodada acaba quando um time inteiro cai (o outro leva) — o tempo estourando
## e tratado no _tick_pvp. Uso: chamado a cada abate.
func _check_pvp_round_end() -> void:
	if pvp_match.phase != PvpMatch.Phase.LIVE:
		return
	var alive := _pvp_alive_per_team()
	if alive[0] > 0 and alive[1] > 0:
		return
	if alive[0] == 0 and alive[1] == 0:
		pvp_match.finish_round(-1)
		return
	pvp_match.finish_round(0 if alive[0] > 0 else 1)


## Vivos por time (usado para decidir a rodada). Uso: var vivos := _pvp_alive_per_team()
func _pvp_alive_per_team() -> Array[int]:
	var alive: Array[int] = [0, 0]
	for key in network_players.keys():
		var player = network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		if bool(player.get("is_eliminated")):
			continue
		var team: int = pvp_match.team_of(String(key))
		if team >= 0 and team < alive.size():
			alive[team] += 1
	return alive


func _pvp_announce_end() -> void:
	pvp_restart_left = PVP_RESTART_SECONDS
	print(JSON.stringify({"event": "pvp_over", "winner_team": pvp_match.match_winner(), "score": pvp_match.team_score_text(), "standings": pvp_match.standings()}))


## Avanca a partida: fases/rodadas, IA dos bots, respawn e broadcast do estado.
## Uso: chamado em _physics_process no servidor/offline.
func _tick_pvp(delta: float) -> void:
	var phase_before: int = pvp_match.phase
	var round_before: int = pvp_match.round_index
	if pvp_match.phase == PvpMatch.Phase.LIVE and _pvp_alive_per_team() == [0, 0]:
		# Ninguem vivo (rodada travada em 0x0 por morte simultanea/queda).
		pvp_match.finish_round(-1)
	elif pvp_match.phase == PvpMatch.Phase.LIVE and float(pvp_match.phase_left) <= delta:
		# Tempo estourou: quem tem mais gente viva leva a rodada.
		pvp_match.finish_round_by_time(_pvp_alive_per_team())
	pvp_match.tick(delta)
	_tick_pvp_bots(delta)
	for key in network_players.keys().duplicate():
		var player = network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		player.tick_pvp(delta)
		player.set("pvp_money", pvp_match.money_of(String(key)))
		if pvp_match.phase != PvpMatch.Phase.BUY:
			# Estilo CS: quem morre fica fora ate o fim da rodada; o respawn
			# acontece quando a proxima fase de compra abre (senao a rodada
			# nunca fecha, porque o time eliminado volta em 3 s).
			continue
		if not bool(player.get("is_eliminated")):
			continue
		player.pvp_respawn_at(_pvp_spawn_position_for(player))
	if round_before != pvp_match.round_index or (phase_before != pvp_match.phase and pvp_match.phase == PvpMatch.Phase.BUY):
		print(JSON.stringify({"event": "pvp_round", "round": pvp_match.round_index, "score": pvp_match.team_score_text()}))
	if pvp_match.is_over() and pvp_restart_left <= 0.0 and phase_before != PvpMatch.Phase.MATCH_END:
		_pvp_announce_end()
	if pvp_restart_left <= 0.0:
		_pvp_broadcast_state()
		return
	pvp_restart_left -= delta
	if pvp_restart_left > 0.0:
		_pvp_broadcast_state()
		return
	pvp_restart_left = 0.0
	_pvp_start_new_match()


## Estado da partida para os clientes (HUD e dica do menu de compra), 2 Hz.
## Uso: chamado no _tick_pvp (pvp_match so existe no servidor/offline).
func _pvp_broadcast_state() -> void:
	if not NetworkSession.is_server():
		return
	pvp_state_elapsed += 1.0 / 30.0
	if pvp_state_elapsed < 0.5:
		return
	pvp_state_elapsed = 0.0
	var text := pvp_match.hud_text()
	var in_buy := pvp_match.phase == PvpMatch.Phase.BUY
	for peer_id in NetworkSession.loaded_peers:
		_pvp_state.rpc_id(int(peer_id), text, in_buy)


@rpc("authority", "call_remote", "reliable")
func _pvp_state(text: String, in_buy: bool) -> void:
	if not NetworkSession.is_client():
		return
	pvp_state_text = text
	pvp_buy_open = in_buy


## Partida nova: economia zerada, placar limpo e todo mundo na base.
## Uso: chamado quando o reinicio vence (fim de partida).
func _pvp_start_new_match() -> void:
	pvp_match = PvpMatch.new()
	pvp_restart_left = 0.0
	for key in network_players.keys().duplicate():
		var player = network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		_register_pvp_player(player)
		player.set("pvp_kills", 0)
		player.set("pvp_deaths", 0)
		player.pvp_respawn_at(_pvp_spawn_position_for(player))
	print(JSON.stringify({"event": "pvp_restart"}))


## Ponto de spawn do jogador: anel na base do time dele (lados opostos do mapa).
## Uso: var posicao := _pvp_spawn_position_for(player)
func _pvp_spawn_position_for(player: Node) -> Vector3:
	var key := _key_for_player(player)
	var team: int = pvp_match.team_of(key) if not key.is_empty() else 0
	if team < 0 or team >= PVP_TEAM_SAFEHOUSES.size():
		team = 0
	# Marcador FIXO da safehouse do time, girando entre os 4 para nao empilhar.
	pvp_spawn_counters[team] += 1
	var slot := posmod(pvp_spawn_counters[team], 4) + 1
	var marker := get_node_or_null("GeneratedCity/%s/PlayerSpawn%d" % [PVP_TEAM_SAFEHOUSES[team], slot]) as Marker3D
	if marker != null:
		return marker.global_position
	return PVP_TEAM_BASE_FALLBACK[team]


## Centro (no chao) da safehouse do time; fallback se a casa nao existir.
## Uso: var centro := _pvp_team_base(team)
func _pvp_team_base(team: int) -> Vector3:
	if team < 0 or team >= PVP_TEAM_SAFEHOUSES.size():
		return PVP_TEAM_BASE_FALLBACK[0]
	var house := get_node_or_null("GeneratedCity/" + PVP_TEAM_SAFEHOUSES[team]) as Node3D
	if house != null:
		return house.global_position
	return PVP_TEAM_BASE_FALLBACK[team]


## Verdadeiro quando o jogador esta DENTRO da propria safehouse (zona de compra).
## Uso: if _pvp_in_buy_zone(player): ...
func _pvp_in_buy_zone(player: Node) -> bool:
	var key := _key_for_player(player)
	var team: int = pvp_match.team_of(key) if not key.is_empty() else -1
	if team < 0:
		return false
	var position := (player as Node3D).global_position
	var base := _pvp_team_base(team)
	return Vector2(position.x - base.x, position.z - base.z).length() <= PVP_BASE_RADIUS


## Compra pedida pelo cliente: valida fase, base, dinheiro e arma; desconta e
## equipa. A resposta volta para o cliente mostrar o motivo da recusa.
## Uso: chamado por BuyMenu via main.request_purchase(kind)
func request_purchase(player: Node, kind: int) -> String:
	if pvp_match == null or not is_instance_valid(player):
		return "Sem partida de PVP."
	var price := WeaponStats.price_for(kind)
	var rejection := pvp_match.buy_rejection(_key_for_player(player), price)
	if not rejection.is_empty():
		return rejection
	if not _pvp_in_buy_zone(player):
		return "Compre na sua base (zona azul no mapa)."
	if not player.equip_crate_weapon(kind):
		return "Nao deu para equipar %s." % WeaponStats.stats_for(kind).get("label", kind)
	pvp_match.spend(_key_for_player(player), price)
	player.set("pvp_money", pvp_match.money_of(_key_for_player(player)))
	return ""


## Compra pedida pelo jogador local (menu de compra). No cliente vai por RPC;
## offline resolve direto, que e o mesmo caminho do servidor.
## Uso: conectado ao BuyMenu.
func request_purchase_local(kind: int) -> void:
	if NetworkSession.is_client():
		_request_purchase.rpc_id(NetworkSession.SERVER_ID, kind, 0)
		return
	if NetworkSession.is_offline() and not local_players.is_empty():
		last_purchase_rejection = request_purchase(local_players[0], kind)


## Ultima recusa de compra (o menu mostra essa linha). Limpa na proxima compra.
## Uso: var texto := main.pvp_status_text()
func pvp_status_text() -> String:
	return last_purchase_rejection


@rpc("any_peer", "call_remote", "reliable")
func _request_purchase(kind: int, slot: int) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var allowed_slots := int(NetworkSession.peer_slots.get(sender_id, 0))
	if slot < 0 or slot >= allowed_slots:
		return
	var player = network_players.get(_player_key(sender_id, slot))
	if player == null:
		return
	_pvp_purchase_result.rpc_id(sender_id, kind, request_purchase(player, kind))


@rpc("authority", "call_remote", "reliable")
func _pvp_purchase_result(kind: int, rejection: String) -> void:
	last_purchase_rejection = rejection
	if not rejection.is_empty():
		print(JSON.stringify({"event": "pvp_buy_refused", "kind": kind, "reason": rejection}))


## Transicao de onda: o barato roda na hora (vidas, estado do HUD) e o que
## varre o mundo (suprimentos, airdrop, loot) entra escalonado por timers.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func _on_wave_transition(wave_index: int) -> void:
	_reset_wave_lives(wave_index)
	_broadcast_wave_state(wave_index)
	_schedule_wave_task(0.12, func() -> void: if wave_supply_controller != null: wave_supply_controller.refresh_wave(wave_index))
	_schedule_wave_task(0.24, func() -> void: if airdrop_controller != null: airdrop_controller.on_wave_started(wave_index))
	_schedule_wave_task(0.36, func() -> void: _spawn_scattered_loot(wave_index))
	_schedule_wave_task(0.48, func() -> void: _grant_support_calls(wave_index))
	if survival_wave_controller.schedule.is_boss_wave(wave_index):
		_schedule_wave_task(3.0, _spawn_boss)


## Ataque aereo a cada 3 ondas e SWAT a cada 5 para cada jogador (autoridade).
func _grant_support_calls(wave_index: int) -> void:
	if NetworkSession.is_client():
		return
	var equipments: Array = []
	for player_node in get_tree().get_nodes_in_group("player"):
		var equipment: Variant = player_node.get("equipment")
		if equipment is PlayerEquipment:
			equipments.append(equipment)
	PlayerEquipment.grant_wave_rewards(equipments, wave_index)


## Hora 10, 20, 30: o super zumbi entra fora da cota e a onda espera ele morrer.
func _spawn_boss() -> void:
	if NetworkSession.is_client() or survival_wave_controller.game_over:
		return
	if _spawn_zombie(null, ZombieMutator.Type.TITAN):
		survival_wave_controller.register_extra_spawn()
		print(JSON.stringify({"event": "boss_spawned", "wave_index": survival_wave_controller.wave_index}))


## Habilidade do Tita: invocacao vira sprinters ao redor; todo efeito visual vai
## para os clientes por RPC (a partida local toca direto).
func _on_boss_ability_used(zombie: Node, ability: String) -> void:
	if NetworkSession.is_client() or not is_instance_valid(zombie):
		return
	var origin: Vector3 = (zombie as Node3D).global_position
	if ability == "summon":
		for index in ZOMBIE_BOSS_BRAIN_SCRIPT.SUMMON_COUNT:
			var angle := TAU * float(index) / float(ZOMBIE_BOSS_BRAIN_SCRIPT.SUMMON_COUNT)
			if _spawn_zombie(origin + Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0), ZombieMutator.Type.SPRINTER):
				survival_wave_controller.register_extra_spawn()
	_play_boss_ability_effect(ability, origin)
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_boss_ability_effect.rpc_id(int(peer_id), ability, origin)


## Efeito de habilidade de zumbi comum (cura do curandeiro): local e clientes.
## Uso: chamado por ZombieHealer.update via has_method("show_zombie_ability").
func show_zombie_ability(ability: String, origin: Vector3) -> void:
	_play_boss_ability_effect(ability, origin)
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_boss_ability_effect.rpc_id(int(peer_id), ability, origin)


## Curandeiro levanta um cadaver: zumbi novo no lugar, fora da cota da onda.
## Devolve false quando o cadaver nao serve mais ou o spawn falhou.
## Uso: chamado por ZombieHealer.update.
func revive_zombie_corpse(corpse: Node) -> bool:
	if NetworkSession.is_client() or not is_instance_valid(corpse) or not corpses.has(corpse):
		return false
	var position := (corpse as Node3D).global_position
	if not _spawn_zombie(position, ZombieMutator.Type.WALKER):
		return false
	if NetworkSession.survival_mode and survival_wave_controller != null:
		survival_wave_controller.register_extra_spawn()
	corpses.erase(corpse)
	var corpse_name := String(corpse.name)
	corpse.queue_free()
	_remove_zombie_ragdoll(corpse_name)
	show_zombie_ability("heal", position)
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_remove_zombie_ragdoll_remote.rpc_id(int(peer_id), corpse_name)
	return true


@rpc("authority", "call_remote", "reliable")
func _remove_zombie_ragdoll_remote(zombie_name: String) -> void:
	if NetworkSession.is_client():
		_remove_zombie_ragdoll(zombie_name)


func _remove_zombie_ragdoll(zombie_name: String) -> void:
	var ragdoll: Variant = ragdolls_by_zombie.get(zombie_name)
	if is_instance_valid(ragdoll):
		(ragdoll as Node).queue_free()
	ragdolls_by_zombie.erase(zombie_name)


## Lingua do puxador presa (ou solta) num jogador: desenho local e clientes.
## Uso: chamado pelo zumbi puxador.
func show_zombie_tongue(zombie: Node3D, target: Node3D, active: bool) -> void:
	_set_tongue_visual(zombie, target, active)
	if not NetworkSession.is_server():
		return
	var target_key := ""
	for key in network_players:
		if network_players[key] == target:
			target_key = String(key)
	for peer_id in NetworkSession.loaded_peers:
		_show_zombie_tongue.rpc_id(int(peer_id), String(zombie.name), target_key, active)


@rpc("authority", "call_remote", "reliable")
func _show_zombie_tongue(zombie_name: String, target_key: String, active: bool) -> void:
	if not NetworkSession.is_client():
		return
	_set_tongue_visual(zombies.get_node_or_null(zombie_name) as Node3D, network_players.get(target_key) as Node3D, active)


func _set_tongue_visual(zombie: Node3D, target: Node3D, active: bool) -> void:
	if zombie == null or ServerTickPolicy.is_dedicated_server():
		return
	var existing := get_node_or_null("Tongue_%s" % String(zombie.name))
	if existing != null:
		existing.queue_free()
	if not active or target == null:
		return
	var tongue_visual := ZombieTongueVisual.new()
	add_child(tongue_visual)
	tongue_visual.setup(zombie, target)


## Cuspe: poca que queima onde ha simulacao; clientes recebem so o visual.
func _on_spit_used(_zombie: Node, target_position: Vector3) -> void:
	var ground := Vector3(target_position.x, target_position.y - 0.9, target_position.z)
	_spawn_acid_puddle(ground, not NetworkSession.is_client())
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_acid_puddle_effect.rpc_id(int(peer_id), ground)


@rpc("authority", "call_remote", "reliable")
func _acid_puddle_effect(ground: Vector3) -> void:
	if NetworkSession.is_client():
		_spawn_acid_puddle(ground, false)


func _spawn_acid_puddle(ground: Vector3, damages: bool) -> void:
	if NetworkSession.is_server() and not damages:
		return
	var puddle := AcidPuddle.new()
	puddle.damages = damages
	add_child(puddle)
	puddle.global_position = ground


## Explosao da bazuca: toca local (partida local) e manda para os clientes.
## Uso: get_tree().current_scene.show_explosion(ponto, 5.0)
func show_explosion(impact: Vector3, radius: float) -> void:
	ZOMBIE_SCRIPT.play_area_effect(get_tree(), impact, EXPLOSION_COLOR, radius)
	if NetworkSession.is_server():
		for peer_id in NetworkSession.loaded_peers:
			_explosion_effect.rpc_id(int(peer_id), impact, radius)


@rpc("authority", "call_remote", "reliable")
func _explosion_effect(impact: Vector3, radius: float) -> void:
	if NetworkSession.is_client():
		ZOMBIE_SCRIPT.play_area_effect(get_tree(), impact, EXPLOSION_COLOR, radius)


@rpc("authority", "call_remote", "reliable")
func _boss_ability_effect(ability: String, origin: Vector3) -> void:
	if NetworkSession.is_client():
		_play_boss_ability_effect(ability, origin)


func _play_boss_ability_effect(ability: String, origin: Vector3) -> void:
	var colors := {"slam": ZOMBIE_SCRIPT.TITAN_SLAM_COLOR, "summon": Color(0.6, 0.2, 0.9), "rage": Color(1.0, 0.1, 0.05), "heal": Color(0.3, 1.0, 0.4)}
	var radius: float = ZOMBIE_BOSS_BRAIN_SCRIPT.SLAM_RANGE if ability == "slam" else 3.0
	ZOMBIE_SCRIPT.play_area_effect(get_tree(), origin, colors.get(ability, Color.WHITE), radius)


func _schedule_wave_task(delay: float, task: Callable) -> void:
	get_tree().create_timer(delay, false).timeout.connect(task)


func _get_player_spawn_position(slot: int) -> Vector3:
	var spawn_slot := slot % PLAYER_SPAWN_POINTS.size()
	var marker_path := "GeneratedCity/CentralSafehouse/PlayerSpawn%d" % (spawn_slot + 1)
	var marker := get_node_or_null(marker_path) as Marker3D
	var base: Vector3 = marker.global_position if marker != null else PLAYER_SPAWN_POINTS[spawn_slot]
	# Servidor com mais de 4 jogadores: nao nascer em cima de outro no marcador.
	return base + PlayerCapacity.spawn_offset(slot, PLAYER_SPAWN_POINTS.size())


func _update_player_vision(delta: float) -> void:
	if NetworkSession.is_server() or local_players.is_empty():
		return
	player_vision_elapsed += delta
	if player_vision_elapsed < PLAYER_VISION_UPDATE_INTERVAL:
		return
	player_vision_elapsed = 0.0
	# Visao compartilhada por raio: aliados (locais e de rede) revelam zumbis para todos.
	var observers := SHARED_VISION_SCRIPT.observers(get_tree())
	for zombie_node in get_tree().get_nodes_in_group("zombies"):
		var zombie := zombie_node as CharacterBody3D
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("is_dead")):
			continue
		# LOD FAR (alem de 50 m) ja fica oculto por design.
		if int(zombie.get("lod_level")) == 2: # LodLevel.FAR
			continue
		zombie.set_vision_visible(SHARED_VISION_SCRIPT.is_seen_by_any(observers, zombie))


func _player_key(peer_id: int, slot: int) -> String:
	return "%d:%d" % [peer_id, slot]


func _on_server_lost() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _get_local_player_configs() -> Array[Dictionary]:
	var forced_count := _get_forced_local_player_count()
	if forced_count > 0:
		var forced_configs: Array[Dictionary] = []
		for slot in forced_count:
			forced_configs.append(GameConfig.create_keyboard_config(slot))
		GameConfig.configure_local_players(forced_configs)

	if GameConfig.player_input_configs.is_empty():
		var default_configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
		GameConfig.configure_local_players(default_configs)
	return GameConfig.player_input_configs


func _get_forced_local_player_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--local-players="):
			return clampi(int(argument.trim_prefix("--local-players=")), 1, MAX_LOCAL_PLAYERS)
	return 0
