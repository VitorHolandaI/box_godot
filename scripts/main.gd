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
const SHOT_CAPTURE_SCRIPT := preload("res://scripts/shot_capture.gd")
const CAR_BOT_DRIVER_SCRIPT := preload("res://scripts/car_bot_driver.gd")
const CORPSE_CLEANUP_INTERVAL := 1.0
const MAX_LOCAL_PLAYERS := 4
const GLOBAL_ACTIVE_ZOMBIE_TARGET := 600
const MAX_CORPSES := 20
const SPAWN_INTERVAL := 1.0
const INPUT_INTERVAL := 1.0 / 30.0
## 20 Hz reduz a latencia de interpolacao sem aumentar a fisica dedicada (30 Hz).
const SNAPSHOT_INTERVAL := 1.0 / 20.0
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
## --smoke-test-swat: harness de dev que chama o esquadrao e reporta; nulo
## quando o argumento nao veio (ver SwatSmokeTest).
var swat_smoke: SwatSmokeTest = null
## watch() do replicador de portas precisa re-agir quando a cidade em etapas
## termina de montar; false evita re-watch repetido a cada frame.
var _city_doors_watched := false
## O primeiro lote de loot espera a cidade montar (ancoras internas prontas).
var _initial_loot_spawned := false
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
## O que cai no chao por onda (aviao, crate e itens de vida/municao).
var loot := WaveLootSpawner.new(self)
var door_state_replicator = DOOR_STATE_REPLICATOR_SCRIPT.new()
var ammo_loot_director = AMMO_LOOT_DIRECTOR_SCRIPT.new()
var player_slots_replication := PlayerSlotsReplication.new()
var player_snapshot_sequence := 0
## Esquadrao SWAT: cada soldado e um jogador de verdade simulado no servidor
## (ver SwatSquadBot) e replicado pelo snapshot de jogadores. A conducao inteira
## vive em SwatSquadDirector; aqui ficam so os RPCs.
var swat := SwatSquadDirector.new(self)
## Mata-mata (--pvp): times, bots, respawn e rota entre as bases vivem em
## PvpServerDirector; as regras em TdmMatch. Aqui ficam so os RPCs e o estado
## replicado abaixo.
var pvp := PvpServerDirector.new(self)
## Estado replicado do mata-mata para o cliente (linha de HUD com placar).
var pvp_state_text := ""
var pvp_state_elapsed := 0.0
## Ultima resposta do servidor a escolha de arma no mata-mata ("" = equipou).
var last_loadout_message := ""
## Menu de arma do cliente (tecla B), criado quando o jogador local existe.
var loadout_menu: LoadoutMenu = null
var loot_rng := RandomNumberGenerator.new()
## Jogadores na sala no frame anterior: a sala reinicia na TRANSICAO para vazia.
var _previous_player_count := 0
## Armas soltas por zumbis ainda no chao, da mais antiga para a mais nova.
var zombie_weapon_drops: Array[Node] = []


## Monta a partida por papel: o comum, depois offline (jogadores locais) ou
## rede (roster, smoke tests e carga do servidor).
func _ready() -> void:
	GameConfig.menu_open = false
	FramePerfProbe.active = perf_probe
	loot_rng.randomize()
	in_game_menu.unstuck_requested.connect(_on_unstuck_requested)
	survival_wave_controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(Callable(self, "_spawn_zombie"))
	_apply_debug_wave_arguments()
	_start_game_mode()
	_add_world_helpers()
	if NetworkSession.is_offline():
		_start_offline_match()
		return
	_start_network_match()


## Debug: pula direto para uma onda especifica (`--test-wave=N`), para chegar
## na horda cheia sem jogar as horas anteriores.
func _apply_debug_wave_arguments() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-wave="):
			var wave := int(arg.trim_prefix("--test-wave=")) - 1
			survival_wave_controller.wave_index = clampi(wave, 0, survival_wave_controller.schedule.TARGETS.size() - 1)
		if arg == "--test-wave-8":
			survival_wave_controller.wave_index = 7


## Mata-mata ou sobrevivencia, so onde a partida e simulada. O cliente nao
## monta nem um nem outro: ele recebe tudo pronto.
func _start_game_mode() -> void:
	if NetworkSession.is_client():
		return
	if NetworkSession.pvp_mode:
		# PVP: sem suprimentos/airdrop/loot de sobrevivencia no mapa.
		pvp.start_match()
		return
	wave_supply_controller = WAVE_SUPPLY_CONTROLLER_SCRIPT.new(get_tree(), NetworkSession.world_seed)
	airdrop_controller = AIRDROP_CONTROLLER_SCRIPT.new(get_tree(), NetworkSession.world_seed)
	airdrop_controller.airdrop_requested.connect(loot.launch_airdrop)
	# Transicao de onda escalonada: refresh de suprimentos, airdrop, loot
	# e HUD rodam em frames distintos para nao varrer 600 zumbis 4x no
	# mesmo frame (hitch de 1 frame a cada nova hora).
	survival_wave_controller.wave_started.connect(_on_wave_transition)
	wave_supply_controller.refresh_wave(survival_wave_controller.wave_index)
	# Sem o loot aqui: a cidade monta em etapas e as ancoras internas ainda
	# nao existem; o primeiro lote sai no _process quando ela fica pronta.


## Nos que existem em qualquer papel: o cerebro das hordas, a captura de telas
## de dev e a janela/sombras.
func _add_world_helpers() -> void:
	var coordinator = FLOCK_COORDINATOR_SCRIPT.new()
	coordinator.name = "ZombieFlockCoordinator"
	add_child(coordinator)
	if SHOT_CAPTURE_SCRIPT.is_requested():
		# Captura de frames para docs/README (dev-only): inerte sem --capture.
		add_child(SHOT_CAPTURE_SCRIPT.new())
	if not NetworkSession.bot_name.is_empty():
		DisplayServer.window_set_title("Box Godot - %s" % NetworkSession.bot_name)
	sun.shadow_enabled = GameConfig.uses_world_shadows()


## Partida local: os jogadores da tela dividida e, se pedido, o campo de armas
## ou a horda de teste de carga.
func _start_offline_match() -> void:
	var configs := _get_local_player_configs()
	for slot in configs.size():
		_spawn_offline_player(slot, configs[slot])
	split_screen.configure(local_players)
	if NetworkSession.weapons_lab:
		_build_weapons_lab()
		return
	# Teste offline com horda: --test-wave=8 --prespawn-zombies=200
	var offline_prespawn := LoadTestOptions.prespawn_zombie_count(OS.get_cmdline_user_args())
	if offline_prespawn > 0:
		_prespawn_load_test_zombies(offline_prespawn)
	_start_car_bots_if_requested()


## Servidor ou cliente: roster de peers, smoke tests de dev e, no servidor, a
## carga inicial e os bots de PVP.
func _start_network_match() -> void:
	NetworkSession.roster_changed.connect(_reconcile_network_players)
	NetworkSession.server_lost.connect(_on_server_lost)
	NetworkSession.peer_scene_loaded.connect(_on_peer_scene_loaded)
	_configure_network_zombies()
	_reconcile_network_players()
	_start_smoke_tests()
	if NetworkSession.is_server():
		door_state_replicator.watch(get_tree())
		_prespawn_load_test_zombies(LOAD_TEST_OPTIONS_SCRIPT.prespawn_zombie_count(OS.get_cmdline_user_args()))
		_start_car_bots_if_requested()
		if NetworkSession.pvp_mode:
			pvp.spawn_bots_when_ready.call_deferred(LOAD_TEST_OPTIONS_SCRIPT.pvp_bot_count(OS.get_cmdline_user_args()))
	_notify_scene_loaded.call_deferred()


## Harnesses de desenvolvimento: um zumbi parado para mirar (--smoke-test-zombie)
## e o teste da chamada de SWAT (--smoke-test-swat).
func _start_smoke_tests() -> void:
	if "--smoke-test-swat" in OS.get_cmdline_user_args():
		swat_smoke = SwatSmokeTest.new(self, swat)
	smoke_test_mode = NetworkSession.is_server() and "--smoke-test-zombie" in OS.get_cmdline_user_args()
	if not smoke_test_mode:
		return
	_spawn_zombie(Vector3(-8.5, 1.0, 9.5))
	var smoke_zombie := zombies.get_child(-1) as CharacterBody3D
	smoke_zombie.set("health", 35)
	smoke_zombie.set("speed", 0.0)


## Teste de carga: enche o mundo de zumbis ja no inicio para medir rede e CPU
## sem precisar jogar ate as ondas altas.
func _prespawn_load_test_zombies(count: int) -> void:
	var spawned := 0
	for _index in count:
		if _spawn_zombie():
			spawned += 1
	if count > 0:
		print(JSON.stringify({"event": "prespawn_zombies", "requested": count, "spawned": spawned}))


## Cria bots motoristas nos carros dirigiveis quando `--car-bot=N` foi pedido
## (servidor dedicado/Docker ou partida offline). Serve para testar a rede do
## carro sem um jogador humano: o bot dirige e o snapshot leva o movimento.
## Uso: inicio da partida offline ou do servidor
func _start_car_bots_if_requested() -> void:
	var count := LoadTestOptions.car_bot_count(OS.get_cmdline_user_args())
	if count > 0:
		_spawn_car_bots_when_ready(count)


## Espera os carros existirem e liga ate `count` bots motoristas. Uso: interno de
## _start_car_bots_if_requested
func _spawn_car_bots_when_ready(count: int) -> void:
	var cars := await _await_drivable_cars()
	var spawned := 0
	for car in cars:
		if spawned >= count:
			break
		if car.has_method("is_occupied") and bool(car.call("is_occupied")):
			continue
		_spawn_car_bot_for(car)
		spawned += 1
	print(JSON.stringify({"event": "car_bots", "requested": count, "spawned": spawned}))


## Carros dirigiveis da cidade, esperando a geracao terminar (teto de ~6 s).
## Uso: var cars := await _await_drivable_cars()
func _await_drivable_cars() -> Array:
	for _attempt in 60:
		var cars := get_tree().get_nodes_in_group("drivable_cars")
		if not cars.is_empty():
			return cars
		await get_tree().create_timer(0.1).timeout
	return get_tree().get_nodes_in_group("drivable_cars")


## Prende um CarBotDriver a um carro vazio: o bot entrega steer/throttle pelo
## mesmo contrato do jogador (`get_vehicle_input`). Uso: _spawn_car_bot_for(car)
func _spawn_car_bot_for(car: Node3D) -> void:
	var bot := CAR_BOT_DRIVER_SCRIPT.new()
	bot.name = "CarBotDriver"
	bot.set("car", car)
	bot.set("route_center", car.global_position)
	add_child(bot)
	car.call("enter", bot)


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


## Frame do mundo: sondas e limpeza em qualquer papel; depois, so onde a
## partida e simulada, a cidade pronta e o avanco do modo de jogo.
func _process(delta: float) -> void:
	_tick_probes_and_cleanup(delta)
	if NetworkSession.is_client() or smoke_test_mode:
		return
	if not _procedural_city_ready():
		# Cidade ainda montando: nada de wave/zumbi sobre predio inexistente.
		return
	if NetworkSession.weapons_lab:
		# Campo de armas: sem porta, loot aleatorio nem onda de zumbi.
		return
	_finish_city_setup()
	if NetworkSession.pvp_mode:
		# Mata-mata nao tem zumbi: sem isso o spawner do modo classico (que roda
		# quando survival_mode e falso) enchia o mapa de zumbi durante o PVP.
		return
	if NetworkSession.survival_mode:
		_tick_survival(delta)
		return
	_tick_classic_spawns(delta)


## Sonda de frame, auditoria de fluxo, medidor de atraso, visao dos jogadores
## e limpeza de cadaveres. Roda em todo papel, inclusive no cliente.
func _tick_probes_and_cleanup(delta: float) -> void:
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


## Duas coisas que so dao para fazer com a cidade INTEIRA montada, e por isso
## nao cabem no _ready. Idempotente: cada uma roda uma vez.
func _finish_city_setup() -> void:
	if not _city_doors_watched:
		# watch() no _ready corria com a cidade pela metade: as portas montam
		# DEPOIS e ficavam sem listener, e nenhuma mudanca replicava. Re-assina
		# os sinais com o mundo completo (watch e idempotente).
		_city_doors_watched = true
		door_state_replicator.watch(get_tree())
	if _initial_loot_spawned:
		return
	# Cidade pronta: agora as ancoras internas existem, entao o primeiro
	# lote de loot nasce DENTRO dos predios (e nao mais na rua).
	_initial_loot_spawned = true
	loot.spawn_scattered(survival_wave_controller.wave_index)


## Sobrevivencia: sala vazia, derrota, avanco da onda e reposicao de municao.
func _tick_survival(delta: float) -> void:
	_check_survival_room_reset()
	_check_survival_game_over()
	if survival_wave_controller.game_over:
		if survival_wave_controller.tick_game_over(delta, not get_tree().get_nodes_in_group("player").is_empty()):
			_restart_survival()
		return
	var perf_start := FramePerfProbe.begin()
	survival_wave_controller.tick(delta)
	FramePerfProbe.end("wave_spawn", perf_start)
	# Sem jogador nao ha onde espalhar (pick_clear_position gira em volta deles).
	if not get_tree().get_nodes_in_group("player").is_empty():
		_restock_class_ammo(delta)


## Modo classico (sem ondas): zumbi pinga no ritmo da agenda ate o teto.
func _tick_classic_spawns(delta: float) -> void:
	if not zombie_spawn_schedule.is_spawn_due(delta):
		return
	var alive_count := get_tree().get_nodes_in_group("zombies").size()
	if zombie_spawn_schedule.has_capacity(alive_count) and not _spawn_zombie():
		push_warning("Spawn de zumbi adiado: nenhum ponto autorizado esta livre.")


## Tick de fisica: o que vale para todos, depois o lado do cliente (envia
## input, consome fila de spawn) ou o do servidor (manda os snapshots).
func _physics_process(delta: float) -> void:
	perf_probe.record_physics_step()
	_open_loadout_menu_when_ready()
	if not NetworkSession.is_client():
		# Servidor e offline simulam o esquadrao; o cliente so aplica snapshot.
		swat.update(delta)
	# O smoke roda nos dois papeis: no servidor cria o esquadrao, no cliente
	# confere que os soldados aparecem e se movem.
	if swat_smoke != null:
		swat_smoke.tick(delta)
	if pvp.is_active():
		pvp.tick(delta)
	if NetworkSession.is_client():
		_tick_client_network(delta)
		return
	if NetworkSession.is_server():
		_tick_server_network(delta)


## Menu de arma do mata-mata: so no cliente e so depois que o jogador local
## existe (ele e criado a partir do roster, que chega depois da cena).
func _open_loadout_menu_when_ready() -> void:
	if not (NetworkSession.is_client() and NetworkSession.pvp_mode):
		return
	if loadout_menu != null or local_players.is_empty():
		return
	loadout_menu = LoadoutMenu.new()
	add_child(loadout_menu)
	loadout_menu.setup(local_players[0], Callable(self, "choose_loadout_local"), Callable(self, "pvp_status_text"))


## Cliente: IA do bot de teste, medidor de atraso, envio de input e a fila de
## spawn de zumbi (que entra aos poucos para nao dar hitch de instantiate).
func _tick_client_network(delta: float) -> void:
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		bot_ai.update(delta, get_tree())
	if lag_probe.is_enabled():
		_record_received_network_traffic()
		if lag_probe.tick(delta, _server_round_trip_ms()):
			print(JSON.stringify(lag_probe.build_report()))
			get_tree().quit(0)
			return
	input_elapsed += delta
	if input_elapsed >= INPUT_INTERVAL:
		input_elapsed = 0.0
		_submit_inputs.rpc_id(NetworkSession.SERVER_ID, _collect_local_inputs(delta))
	var drain_start := FramePerfProbe.begin()
	_drain_zombie_spawn_queue()
	FramePerfProbe.end("spawn_drain", drain_start)


## Servidor: estado do chao e progresso da onda a 2 Hz, snapshots a 20 Hz.
func _tick_server_network(delta: float) -> void:
	ground_state_elapsed += delta
	if ground_state_elapsed >= GROUND_STATE_INTERVAL:
		ground_state_elapsed = 0.0
		_send_ground_states()
		_send_wave_progress()
	snapshot_elapsed += delta
	if snapshot_elapsed < SNAPSHOT_INTERVAL:
		return
	# A fisica dedicada roda a 30 Hz. Preservar a sobra alterna 33/67 ms e fecha
	# 50 ms em media; zerar aqui degradaria uma meta de 20 Hz para 15 Hz.
	snapshot_elapsed = fmod(snapshot_elapsed, SNAPSHOT_INTERVAL)
	# So para quem ja carregou; antes um jogador carregando a cidade
	# congelava os snapshots de todos os outros ate terminar.
	if NetworkSession.loaded_peers.is_empty():
		return
	var snapshot_start := FramePerfProbe.begin()
	_send_door_states()
	_send_player_snapshots(_collect_player_states())
	FramePerfProbe.end("snapshot_players", snapshot_start)
	_send_car_snapshots(_collect_car_states())
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


func spawn_zombie_ragdoll(position: Vector3, rotation: float, velocity: Vector3, z_type: int = 0, appearance_hash: int = 0, source_name: String = "", limb_loss_mask: int = 0) -> void:
	if not source_name.is_empty() and is_instance_valid(ragdolls_by_zombie.get(source_name)):
		return
	var perf_start := FramePerfProbe.begin()
	var ragdoll := ZOMBIE_RAGDOLL_SCENE.instantiate()
	# Antes de entrar na arvore: _ready monta as partes ja no tamanho do zumbi.
	ragdoll.set("body_scale", ZombieMutator.body_scale_for(z_type))
	add_child(ragdoll)
	ragdoll.position = position
	ragdoll.rotation.y = rotation
	ragdoll.setup(velocity, z_type, appearance_hash, limb_loss_mask)
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


## Ponte de rede do esquadrao SWAT. A simulacao (soldados, formacao, leash do
## dono, expiracao) vive em SwatSquadDirector; aqui ficam os RPCs, que precisam
## de um no na arvore para o Godot rotear.
## Uso: chamado por PlayerThrowables via has_method("call_swat").
func call_swat(caller: Node3D, _direction: Vector3) -> void:
	if NetworkSession.is_client():
		return
	var squad_id := swat.begin_squad(caller)
	if not NetworkSession.is_server():
		return
	# Todos os conectados, nao so os "loaded": o esquadrao dura 20 s e quem
	# entrou agora tambem precisa ver os soldados (o snapshot so vai para
	# loaded_peers, e sem o no o cliente ignoraria os estados).
	for peer_id in multiplayer.get_peers():
		_enlist_swat_squad_rpc.rpc_id(int(peer_id), squad_id)


@rpc("authority", "call_remote", "reliable")
func _enlist_swat_squad_rpc(squad_id: int) -> void:
	if not NetworkSession.is_client():
		return
	swat.enlist(squad_id, null)


func broadcast_swat_retire(squad_id: int) -> void:
	_retire_swat_squad_rpc.rpc(squad_id)


@rpc("authority", "call_remote", "reliable")
func _retire_swat_squad_rpc(squad_id: int) -> void:
	swat.retire(squad_id)


## Chaves criadas pelo servidor (esquadrao SWAT e bots de PVP) nao vem do
## roster de peers reais: quem cria e libera sao as rotinas proprias, e o
## reconcile tem que deixar elas em paz. A checagem e por pertencimento, nao por
## faixa de id: o ENet sorteia id de peer de 32 bits e um jogador de verdade
## pode cair no mesmo valor reservado.
func _is_reserved_player_key(key: String) -> bool:
	if pvp.has_bot(key):
		return true
	for squad_value in swat.squads.values():
		if (squad_value as Dictionary)["keys"].has(key):
			return true
	return false


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
	pvp.register_player(player)


## Campo de testes de armas (--armas-lab): arena vazia e uma arma de crate de
## cada tipo no chao para pegar e testar. Uso: godot --path . -- --armas-lab
func _build_weapons_lab() -> void:
	SurvivalMapBuilder.build(self)
	var kinds: Array[int] = []
	for kind in WeaponStats.Kind.values():
		if WeaponStats.is_crate_weapon(kind):
			kinds.append(kind)
	var columns := 5
	var spacing := 3.0
	var origin := Vector3(-6.0, 0.05, -6.0)
	for index in kinds.size():
		var kind: int = kinds[index]
		var stats := WeaponStats.stats_for(kind)
		var position := origin + Vector3(float(index % columns) * spacing, 0.0, float(index / columns) * spacing)
		_add_ground_weapon(kind, int(stats["mag_size"]), int(stats["grant_reserve"]), int(stats["max_durability"]), position)
	print(JSON.stringify({"event": "weapons_lab", "weapons": kinds.size(), "players": local_players.size()}))


func _connect_crate_weapon_signals(player: Node) -> void:
	player.crate_weapon_dropped.connect(_on_crate_weapon_dropped.bind(player))
	player.crate_weapon_broken.connect(_on_crate_weapon_broken.bind(player))


## Quanto tempo a arma largada fica no chao no mata-mata. O padrao da pickup e
## 600 s, o tempo INTEIRO de uma partida: com respawn a cada 5 s e 50 abates, o
## mapa viraria um tapete de armas e a lista do chao (replicada inteira a cada
## mudanca) cresceria a partida toda. 45 s da para correr ate o corpo e pegar.
const PVP_DROP_LIFETIME_SECONDS := 45.0


## Drop da arma da mao (tecla de largar ou morte no mata-mata): no
## servidor/offline spawna a pickup no chao; clientes recebem o no pelo sync por
## nome no snapshot. O player vem por ultimo porque Callable.bind() anexa o
## argumento atado no FIM da lista.
## Uso: conectado ao sinal crate_weapon_dropped do jogador.
func _on_crate_weapon_dropped(kind: int, mag: int, reserve: int, durability: int, player: Node) -> void:
	if NetworkSession.is_client():
		return
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	var drop_position: Vector3 = player.global_position + forward.normalized() * 1.2 if not forward.is_zero_approx() else player.global_position
	drop_position.y = player.global_position.y
	var pickup := _add_ground_weapon(kind, mag, reserve, durability, drop_position)
	if NetworkSession.pvp_mode:
		pickup.lifetime_seconds = PVP_DROP_LIFETIME_SECONDS


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


## Ponte de rede do airdrop: o voo e cosmico no cliente e o crate chega pelo
## sync por nome. O lote de itens e o aviao vivem em WaveLootSpawner.
func broadcast_airdrop_flyby(plane_start: Vector3, plane_end: Vector3, drop_position: Vector3) -> void:
	for peer_id in NetworkSession.loaded_peers:
		_airdrop_flyby.rpc_id(int(peer_id), plane_start, plane_end, drop_position)


@rpc("authority", "call_remote", "reliable")
func _airdrop_flyby(plane_start: Vector3, plane_end: Vector3, drop_position: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	loot.show_flyby(plane_start, plane_end, drop_position)


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
		pvp.forget_player(key)
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
	if pvp.bot_count() > 0:
		# Quem entra no meio do mata-mata tambem precisa ver os bots.
		_spawn_pvp_bots_rpc.rpc_id(peer_id, pvp.bot_count())
	if survival_wave_controller.game_over:
		_restart_survival()
	_wave_state.rpc_id(peer_id, survival_wave_controller.wave_index, survival_wave_controller.total_kills, survival_wave_controller.alive_in_wave, survival_wave_controller.game_over)
	# Peer novo precisa da lista completa de itens no chao do primeiro sync.
	SupplyNetworkState.mark_dirty()
	GroundWeaponSync.mark_dirty()


## Todo mundo caido/eliminado = GAME OVER: horda zerada (zumbis limpos,
## contadores zero) e a partida espera novo jogador entrar. Sala vazia nao
## conta: servidor dedicado e um servico que espera, nao um jogo perdido.
func _check_survival_game_over() -> void:
	if survival_wave_controller.game_over:
		return
	if not SURVIVAL_WAVE_CONTROLLER_SCRIPT.everyone_is_down(get_tree().get_nodes_in_group("player")):
		return
	_clear_horde()
	survival_wave_controller.trigger_game_over()
	for peer_id in NetworkSession.loaded_peers:
		_game_over.rpc_id(int(peer_id))


## Sala dedicada: quando o ULTIMO jogador sai, a partida recomeca para quem
## entrar depois. Sala vazia desde que subiu mantem o mundo montado (inclusive
## a horda de --prespawn-zombies), por isso a checagem e de transicao.
## Uso: chamado todo frame no modo sobrevivencia.
func _check_survival_room_reset() -> void:
	var player_count := get_tree().get_nodes_in_group("player").size()
	var emptied: bool = SURVIVAL_WAVE_CONTROLLER_SCRIPT.room_emptied(_previous_player_count, player_count)
	_previous_player_count = player_count
	if not emptied:
		return
	print(JSON.stringify({"event": "room_reset", "reason": "ultimo_jogador_saiu"}))
	_clear_horde()
	_restart_survival()


## Tira a horda inteira do mundo e limpa os caches/filas de spawn.
## Uso: interno do game over e do reinicio da sala.
func _clear_horde() -> void:
	for zombie_node in zombies.get_children():
		zombie_cache.erase(String(zombie_node.name))
		zombie_node.queue_free()
	zombie_cache.clear()
	pending_zombie_spawns.clear()
	pending_zombie_names.clear()


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
	loot.spawn_scattered(0)


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
	pvp.register_player(player)
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
			"vehicle": {"steer": 0.0, "throttle": 0.0, "brake": true},
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
		if player == null:
			continue
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


## Carros dirigiveis: transform + vida/gasolina/estado a 10 Hz (junto do snapshot
## de jogadores). O cliente congela a fisica do carro e interpola este estado.
## Uso: _tick_server_network
func _collect_car_states() -> Array:
	var states: Array = []
	for car in get_tree().get_nodes_in_group("drivable_cars"):
		if car.has_method("get_network_state"):
			var state: Dictionary = car.call("get_network_state")
			state["driver_key"] = _occupant_key(car.get("driver"))
			state["gunner_key"] = _occupant_key(car.get("gunner"))
			states.append(state)
	return states


## Chave de rede (`peer:slot`) do ocupante de um assento, ou "" quando e um bot
## (CarBotDriver) ou nao ha ninguem. Uso: _collect_car_states
func _occupant_key(occupant: Variant) -> String:
	if occupant == null or not (occupant is Node) or not is_instance_valid(occupant):
		return ""
	var node := occupant as Node
	var peer_id: Variant = node.get("owner_peer_id")
	var slot: Variant = node.get("local_slot")
	if peer_id == null or slot == null:
		return ""
	return _player_key(int(peer_id), int(slot))


func _send_car_snapshots(states: Array) -> void:
	if states.is_empty():
		return
	for peer_id in NetworkSession.loaded_peers:
		_apply_car_snapshot.rpc_id(int(peer_id), states)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_car_snapshot(states: Array) -> void:
	if not NetworkSession.is_client():
		return
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var car := _find_drivable_car_by_name(String(state.get("name", "")))
		if car == null:
			continue
		car.call("apply_network_state", state)
		_apply_car_occupancy(car, String(state.get("driver_key", "")), String(state.get("gunner_key", "")))


## No cliente, liga os proxies dos jogadores ao carro (`driver`/`gunner` no carro
## e `driving_car`/`riding_car` no jogador) para a camera FPS (DriverEye), o HUD e
## a pose. Uso: _apply_car_snapshot
func _apply_car_occupancy(car: Node3D, driver_key: String, gunner_key: String) -> void:
	_set_car_seat(car, "driver", "driving_car", driver_key)
	_set_car_seat(car, "gunner", "riding_car", gunner_key)


## Aplica um assento: solta o ocupante antigo e prende o novo (pelo key). Uso:
## interno de _apply_car_occupancy
func _set_car_seat(car: Node3D, car_field: String, player_field: String, key: String) -> void:
	var current: Variant = car.get(car_field)
	if current is Node and is_instance_valid(current):
		var leaving := current as Node
		if _occupant_key(leaving) != key and leaving.get(player_field) == car:
			leaving.set(player_field, null)
	if key.is_empty():
		car.set(car_field, null)
		return
	var player: Variant = network_players.get(key)
	if player == null or not is_instance_valid(player):
		car.set(car_field, null)
		return
	car.set(car_field, player)
	(player as Node).set(player_field, car)


## Carro dirigivel pelo nome: a cidade gerada e deterministica nos dois lados,
## entao o nome (`DrivableCar0`) identifica o mesmo carro. Uso: _apply_car_snapshot
func _find_drivable_car_by_name(car_name: String) -> Node:
	if car_name.is_empty():
		return null
	for car in get_tree().get_nodes_in_group("drivable_cars"):
		if car.name == car_name:
			return car
	return null


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
	# A variante e decidida ANTES da posicao: puxador e espreitador preferem
	# nascer dentro de predio (emboscada) e o locator precisa saber disso.
	var variant := variant_override
	if variant < 0 and NetworkSession.survival_mode and survival_wave_controller != null:
		var roll := posmod(spawn_index * 37 + NetworkSession.world_seed * 13, 100)
		variant = survival_wave_controller.schedule.pick_variant(survival_wave_controller.wave_index, roll)
	var prefer_indoor := ZOMBIE_SPAWN_LOCATOR_SCRIPT.prefers_indoor(variant)
	var spawn_position: Vector3 = position_override as Vector3 if position_override is Vector3 else zombie_spawn_locator.pick_spawn_position(get_tree(), prefer_indoor)
	if spawn_position == ZOMBIE_SPAWN_LOCATOR_SCRIPT.INVALID_SPAWN_POSITION:
		return false
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "%s%d" % [ZOMBIE_SNAPSHOT_CODEC_SCRIPT.NAME_PREFIX, spawn_index]
	zombie.set_meta("network_id", spawn_index)
	# Sobrevivencia: a onda sorteia a variante (mix percentual por fase) e o
	# hash sincroniza o visual para os clientes pelo snapshot.
	if variant >= 0:
		zombie.set("forced_variant", variant)
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
	loot.add_item(supply_kind, AMMO_LOOT_DIRECTOR_SCRIPT.drop_amount_for(supply_kind), ground_position)


## Reposicao periodica: completa o minimo de municao de cada classe no mapa.
func _restock_class_ammo(delta: float) -> void:
	if not ammo_loot_director.is_restock_due(delta):
		return
	for supply_kind in AMMO_LOOT_DIRECTOR_SCRIPT.kinds_to_restock(AMMO_LOOT_DIRECTOR_SCRIPT.count_supplies(get_tree())):
		loot.spawn_item(loot_rng, supply_kind, AMMO_LOOT_DIRECTOR_SCRIPT.amount_for(supply_kind))


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
		return pvp.hud_text() if pvp.is_active() else pvp_state_text
	return survival_wave_controller.get_hud_text() if NetworkSession.survival_mode else ""


## Ponte de rede do mata-mata. A simulacao inteira (times, bots, respawn, rota
## entre as bases) vive em PvpServerDirector; aqui ficam so os RPCs, que
## precisam de um no na arvore para o Godot rotear, e o estado replicado que o
## menu de arma e a captura de telas leem por nome deste script.
## Uso: godot --headless --path . -- --server --pvp --pvp-bots=4
func broadcast_pvp_bots(count: int) -> void:
	for peer_id in multiplayer.get_peers():
		_spawn_pvp_bots_rpc.rpc_id(int(peer_id), count)


@rpc("authority", "call_remote", "reliable")
func _spawn_pvp_bots_rpc(count: int) -> void:
	if not NetworkSession.is_client():
		return
	pvp.create_client_bots(count)


func broadcast_pvp_state(text: String) -> void:
	for peer_id in NetworkSession.loaded_peers:
		_pvp_state.rpc_id(int(peer_id), text)


@rpc("authority", "call_remote", "reliable")
func _pvp_state(text: String) -> void:
	if not NetworkSession.is_client():
		return
	pvp_state_text = text


## Arma escolhida pelo jogador local (menu de loadout). No cliente vai por RPC;
## offline resolve direto, que e o mesmo caminho do servidor.
## Uso: conectado ao LoadoutMenu.
func choose_loadout_local(kind: int) -> void:
	if NetworkSession.is_client():
		_request_loadout.rpc_id(NetworkSession.SERVER_ID, kind, 0)
		return
	if NetworkSession.is_offline() and not local_players.is_empty():
		last_loadout_message = pvp.choose_loadout(local_players[0], kind)


## Ultima resposta do servidor a escolha de arma (o menu mostra essa linha).
## Uso: var texto := main.pvp_status_text()
func pvp_status_text() -> String:
	return last_loadout_message


@rpc("any_peer", "call_remote", "reliable")
func _request_loadout(kind: int, slot: int) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var allowed_slots := int(NetworkSession.peer_slots.get(sender_id, 0))
	if slot < 0 or slot >= allowed_slots:
		return
	var player = network_players.get(_player_key(sender_id, slot))
	if player == null:
		return
	_pvp_loadout_result.rpc_id(sender_id, kind, pvp.choose_loadout(player, kind))


@rpc("authority", "call_remote", "reliable")
func _pvp_loadout_result(kind: int, rejection: String) -> void:
	last_loadout_message = rejection
	if not rejection.is_empty():
		print(JSON.stringify({"event": "pvp_loadout_adiado", "kind": kind, "reason": rejection}))


## Transicao de onda: o barato roda na hora (vidas, estado do HUD) e o que
## varre o mundo (suprimentos, airdrop, loot) entra escalonado por timers.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func _on_wave_transition(wave_index: int) -> void:
	_reset_wave_lives(wave_index)
	_broadcast_wave_state(wave_index)
	_schedule_wave_task(0.12, func() -> void: if wave_supply_controller != null: wave_supply_controller.refresh_wave(wave_index))
	_schedule_wave_task(0.24, func() -> void: if airdrop_controller != null: airdrop_controller.on_wave_started(wave_index))
	_schedule_wave_task(0.36, func() -> void: loot.spawn_scattered(wave_index))
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


## Coletor comeu o cadaver: sai da lista e o corpo some, entao o healer nao
## revive mais. Uso: chamado por ZombieCollector.try_absorb_nearby.
func consume_zombie_corpse(corpse: Node) -> bool:
	if NetworkSession.is_client() or not is_instance_valid(corpse) or not corpses.has(corpse):
		return false
	corpses.erase(corpse)
	var corpse_name := String(corpse.name)
	corpse.queue_free()
	_remove_zombie_ragdoll(corpse_name)
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
	# Servidor com mais de 4 jogadores: procura um ponto livre em volta do
	# marcador. O offset fixo caia dentro de parede/movel em alguns marcadores e
	# o jogador nascia preso (visto no teste de 8 peers: moved=false).
	var offset: Vector3 = PlayerCapacity.spawn_offset(slot, PLAYER_SPAWN_POINTS.size())
	if offset == Vector3.ZERO:
		return base
	for step in 12:
		var candidate: Vector3 = base + offset.rotated(Vector3.UP, TAU * float(step) / 12.0)
		if _spawn_point_is_free(candidate):
			return candidate
	return base


## Ponto de spawn livre de parede/movel (esfera do tamanho do boneco).
## Uso: if _spawn_point_is_free(ponto): return ponto
func _spawn_point_is_free(candidate: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var sphere := SphereShape3D.new()
	sphere.radius = PlayerCapacity.SPAWN_FREE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 0.6)
	query.collision_mask = 1
	return space.intersect_shape(query, 1).is_empty()


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
