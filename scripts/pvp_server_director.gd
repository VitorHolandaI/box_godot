# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PvpServerDirector
extends RefCounted

## Mata-mata por times (--pvp) do lado que simula: times, bots, rota entre as
## duas bases, respawn com invulnerabilidade, escolha de arma e o estado que vai
## para o HUD dos clientes. As REGRAS vivem em TdmMatch; aqui fica o mundo.
##
## O `world` e o no da partida (scenes/main.tscn): ele continua dono da arvore
## de nos, dos RPCs e do dicionario de jogadores de rede. No cliente o diretor
## existe mas `tdm_match` fica nulo: ali ele so guarda as chaves dos bots, que
## chegam pelo RPC e precisam existir para o snapshot achar o no.
##
## Uso:
##   var pvp := PvpServerDirector.new(self)
##   pvp.start_match()          # so no servidor/offline
##   pvp.tick(delta)            # no _physics_process

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
## Ids reservados dos bots (negativos, fora do sorteio do ENet).
const BOT_PEER_ID_BASE := -2000
const RESTART_SECONDS := 10.0
## Bases dos dois times: uma safehouse por canto OPOSTO do mapa (~165 m entre
## elas). Cada time nasce nos marcadores fixos PlayerSpawn1..4 da sua casa. A
## casa central continua sendo a da sobrevivencia.
const TEAM_SAFEHOUSES := ["PvpSafehouseA", "PvpSafehouseB"]
## Fallback quando a cidade nao tem as casas (modo legacy/teste).
const TEAM_BASE_FALLBACK := [Vector3(-58.5, 1.18, -58.5), Vector3(58.5, 1.18, 58.5)]
## Raio da zona de base (a casa tem 12,8 m de lado). Subiu para 9 m porque os
## bots nascem no quintal, na frente da porta (7,6 m). Dentro dela a troca de
## arma vale na hora; fora, so no proximo respawn.
const BASE_RADIUS := 9.0
## Bots de PVP nascem no QUINTAL, na frente da porta da propria base: nascer
## dentro da casa dependia de o bot achar a saida com movimento sem pathfinding,
## e ele ficava preso num canto interno oscilando ate estourar a partida
## (medido: 80 s parado com o alvo a 126 m).
const BOT_YARD_DISTANCE := 7.6
## Espalhamento lateral entre os bots do mesmo time, no quintal.
const BOT_YARD_SPREAD := 1.4
## Distancia para considerar um waypoint da rota alcancado (o alvo passa a ser o
## proximo). Tem que ser MENOR que a distancia do quintal ate a primeira esquina
## (5,9 m): com 6,0 m o bot ja nascia "no" waypoint 0, pulava direto para o
## waypoint 1 la no outro canto e cortava o quarteirao na diagonal em vez de
## entrar na rua — medido: os dois bots do time 0 travados em (-44,5, -58,0)
## por 120 s, sem sair de casa.
const WAYPOINT_ARRIVE_RADIUS := 4.0
## Esquinas do ANEL DE RUAS do perimetro (as ruas ficam em -72/-24/24/72 e os
## quarteiroes vao ate 69, entao o anel externo e o unico caminho sem predio no
## meio). As duas portas davam para o mesmo lado (Z local): a casa B foi girada
## 180 graus, entao cada porta cai a ~4 m da sua rua de perimetro. O time 0 desce
## a rua de baixo, sobe a direita e entra na casa B pela porta; o time 1 percorre
## a mesma rota ao contrario, de frente um com o outro.
const ROUTE_CORNERS := [
	Vector3(-58.5, 1.3, -72.0),
	Vector3(72.0, 1.3, -72.0),
	Vector3(72.0, 1.3, 72.0),
	Vector3(58.5, 1.3, 72.0),
	Vector3(58.5, 1.3, 58.5),
]
## Distancia entre waypoints intermediarios da rota. O bot anda em LINHA RETA
## para o waypoint (nao ha navmesh neste projeto, so a sonda curta de
## PvpNavigation), entao um trecho de 144 m acumula desvio de obstaculo ate o bot
## sair da rua e encostar num predio — medido: o time 1 travado em x=-28,9 por
## 80 s. Picotado de 24 em 24 m cada trecho e curto o bastante para o desvio
## voltar para a rua.
const ROUTE_STEP := 24.0

## No da partida (scenes/main.tscn): arvore de nos, RPCs e jogadores de rede.
var world: Node3D
## Placar, times e relogio. Nulo no cliente, que so recebe o estado pronto.
var tdm_match: TdmMatch = null
## Chaves dos bots criados aqui, no formato do dicionario de jogadores de rede.
var bot_keys: Dictionary = {}
## Contagem para comecar uma partida nova depois do fim (0 = sem partida).
var restart_left := 0.0
## Gira os marcadores fixos de spawn de cada time (nao empilha os 4 no mesmo).
var spawn_counters: Array[int] = [0, 0]
## Rota do time 0 e a invertida do time 1, montadas UMA vez: ver _route_for().
var forward_route: Array = []
var reversed_route: Array = []
## Waypoint atual de cada bot (chave -> indice), monotonico por vida.
var bot_route_index: Dictionary = {}
## Cadencia do broadcast de estado (2 Hz num servidor de 30 Hz).
var _state_elapsed := 0.0
## Jogadores na sala no frame anterior: a sala reinicia na TRANSICAO para vazia,
## mesma regra da sobrevivencia (ver Main._check_survival_room_reset).
var _previous_player_count := 0


func _init(world_node: Node3D = null) -> void:
	world = world_node


## Comeca a partida. So no servidor/offline: e o lado que simula.
## Uso: if not NetworkSession.is_client(): pvp.start_match()
func start_match() -> void:
	tdm_match = TdmMatch.new()
	print(JSON.stringify({
		"event": "pvp_match_started",
		"score_limit": TdmMatch.SCORE_LIMIT,
		"match_seconds": TdmMatch.MATCH_SECONDS,
		"respawn_seconds": TdmMatch.RESPAWN_SECONDS,
		"spawn_protection_seconds": TdmMatch.SPAWN_PROTECTION_SECONDS,
	}))


## Verdadeiro onde a partida e simulada (servidor/offline).
func is_active() -> bool:
	return tdm_match != null


func hud_text() -> String:
	return tdm_match.hud_text() if tdm_match != null else ""


func bot_count() -> int:
	return bot_keys.size()


func has_bot(key: String) -> bool:
	return bot_keys.has(key)


## Jogador saiu: tira do placar para o time nao contar um fantasma.
func forget_player(key: String) -> void:
	if tdm_match != null:
		tdm_match.remove_player(key)


## Espera a cidade em etapas terminar antes de criar os bots: eles nascem no
## quintal da base, que so existe depois da montagem.
## Uso: pvp.spawn_bots_when_ready.call_deferred(count)
func spawn_bots_when_ready(count: int) -> void:
	while not world.call("_procedural_city_ready"):
		await world.get_tree().create_timer(0.1).timeout
	spawn_bots(count)


func spawn_bots(count: int) -> void:
	if not NetworkSession.pvp_mode or count <= 0:
		return
	for index in count:
		_create_bot(index, NetworkSession.is_server() or NetworkSession.is_offline())
	# O cliente so cria jogador do roster de peers; os bots sao do servidor,
	# entao precisam do RPC para existir do outro lado (senao o estado deles
	# chega no snapshot e nao ha no para receber: o humano nao ve os bots).
	if NetworkSession.is_server():
		world.call("broadcast_pvp_bots", count)
	print(JSON.stringify({"event": "pvp_bots_spawned", "count": bot_keys.size()}))


## Bots no cliente: proxies sem simulacao, so para o snapshot ter onde chegar.
func create_client_bots(count: int) -> void:
	for index in count:
		_create_bot(index, false)


## Cria (ou reaproveita) o no de um bot. `simulate` so no lado que simula: no
## cliente o bot e um proxy como qualquer jogador de rede.
func _create_bot(index: int, simulate: bool) -> void:
	var key := "%d:%d" % [BOT_PEER_ID_BASE - index, 0]
	if bot_keys.has(key):
		return
	var bot = PLAYER_SCENE.instantiate()
	bot.name = "PvpBot_%d" % index
	bot.local_slot = index
	bot.simulation_enabled = simulate
	bot.owner_peer_id = BOT_PEER_ID_BASE - index
	bot.reads_local_input = false
	bot.is_local_controller = false
	bot.position = _bot_yard_spawn(index)
	world.players_node.add_child(bot, true)
	bot.set_spawn_position(bot.global_position)
	bot.set("input_device_name", "Bot PVP %d" % (index + 1))
	world.network_players[key] = bot
	bot_keys[key] = true
	if not simulate:
		return
	# A arma vai ANTES do register: e o register que faz o primeiro respawn, e o
	# respawn e quem equipa o loadout.
	bot.choose_pvp_loadout(_bot_loadout_for(index))
	register_player(bot)


## Arma fixa do bot, girando o arsenal pelo indice: cada bot do time aparece
## com uma arma diferente sem sorteio (o servidor precisa ser determinista para
## o teste de fumaca comparar duas execucoes).
func _bot_loadout_for(index: int) -> int:
	var arsenal := WeaponStats.loadout_kinds()
	if arsenal.is_empty():
		return 0
	return arsenal[posmod(index * 3 + 5, arsenal.size())]


## Alimenta a IA dos bots (o lado que simula; o cliente so ve o snapshot).
func _tick_bots(delta: float) -> void:
	var slot := 0
	for key in bot_keys.keys().duplicate():
		var bot = world.network_players.get(key)
		if not is_instance_valid(bot):
			bot_keys.erase(key)
			world.network_players.erase(key)
			forget_player(String(key))
			continue
		if bool(bot.get("is_eliminated")):
			continue
		var rumo := bot_hunt_position(bot)
		bot.apply_network_input(world.bot_ai.collect_pvp_input(bot, world.get_tree(), slot, delta, rumo))
		slot += 1


## Posicao de nascimento do bot: no quintal, na frente da porta da base do time.
## O lado da porta segue a rotacao da casa (time 0 em -Z, time 1 em +Z).
func _bot_yard_spawn_for_team(team: int, slot: int) -> Vector3:
	var base := team_base(team)
	var door_sign := -1.0 if team == 0 else 1.0
	var lateral := (float(posmod(slot, 4)) - 1.5) * BOT_YARD_SPREAD
	return Vector3(base.x + lateral, base.y + 1.0, base.z + door_sign * BOT_YARD_DISTANCE)


## Chute inicial (antes do register o time ainda nao existe): por paridade.
func _bot_yard_spawn(index: int) -> Vector3:
	return _bot_yard_spawn_for_team(0 if index % 2 == 0 else 1, index)


## Proxima esquina da rota do bot ate o lado inimigo (anda para a frente quando
## chega perto). Sem rota definida para o time, devolve a base inimiga.
func bot_hunt_position(bot: Node) -> Vector3:
	if tdm_match == null or not is_instance_valid(bot):
		return team_base(1)
	var key := key_for_player(bot)
	var team: int = tdm_match.team_of(key)
	var enemy_team := 0 if team == 1 else 1
	var route: Array = _route_for(team)
	if route.is_empty():
		return team_base(enemy_team)
	var position := (bot as Node3D).global_position
	var index: int = int(bot_route_index.get(key, 0))
	# Avanca o indice de forma MONOTONICA. Recalcular "a primeira esquina nao
	# alcancada" a cada tick fazia o bot oscilar no limite do raio: ao andar para
	# a esquina 2 a esquina 1 voltava a ficar fora do raio e ele voltava (medido:
	# vai e volta em volta de (-53,-68) por minutos).
	while index < route.size() - 1 and position.distance_to(route[index]) <= WAYPOINT_ARRIVE_RADIUS:
		index += 1
	bot_route_index[key] = index
	if index == route.size() - 1 and position.distance_to(route[index]) <= WAYPOINT_ARRIVE_RADIUS:
		# Fim da rota: empurra para dentro da base inimiga.
		return team_base(enemy_team)
	return route[index]


## Rota do time, montada UMA vez. A chamada roda por bot a cada tick (4 bots a
## 30 Hz = 120 Arrays por segundo), entao nada de montar por chamada.
func _route_for(team: int) -> Array:
	if forward_route.is_empty():
		forward_route = paved_route()
		for index in range(forward_route.size() - 1, -1, -1):
			reversed_route.append(forward_route[index])
	return forward_route if team == 0 else reversed_route


## Esquinas do anel picotadas de ROUTE_STEP em ROUTE_STEP, para o bot nunca ter
## um alvo a mais de um quarteirao de distancia em linha reta.
## Uso: var rota := PvpServerDirector.paved_route()
static func paved_route() -> Array:
	var paved: Array = [ROUTE_CORNERS[0]]
	for index in range(1, ROUTE_CORNERS.size()):
		var from: Vector3 = ROUTE_CORNERS[index - 1]
		var to: Vector3 = ROUTE_CORNERS[index]
		var steps := int(ceil(from.distance_to(to) / ROUTE_STEP))
		for step in range(1, steps + 1):
			paved.append(from.lerp(to, float(step) / float(steps)))
	return paved


## Entra na partida: time, cor do uniforme, sinal de morte e o primeiro nascimento
## NA BASE DO TIME. Sem esse nascimento o jogador caia no spawn generico do mapa
## (o mesmo do survival), longe da propria base e sem invulnerabilidade.
## Uso: chamado no spawn de cada jogador (servidor/offline).
func register_player(player: Node) -> void:
	if tdm_match == null or not is_instance_valid(player):
		return
	var key := key_for_player(player)
	if key.is_empty():
		return
	var is_new := not tdm_match.has_player(key)
	tdm_match.register_player(key)
	player.set_pvp_team(tdm_match.team_of(key))
	PvpDeathWiring.connect_once(player, self)
	if not is_new:
		return
	# O time so existe depois do register: e ele que decide a casa.
	var base_spawn := spawn_position_for(player)
	player.set_spawn_position(base_spawn)
	player.pvp_respawn_at(base_spawn)


## Chave de rede do jogador ("" quando nao esta no dicionario).
func key_for_player(player: Node) -> String:
	for key in world.network_players:
		if world.network_players[key] == player:
			return String(key)
	return ""


## Abate: pontua o time de quem matou e conta a morte. Callable.bind anexa a
## vitima no FIM da lista.
## Uso: conectado ao sinal pvp_died de cada jogador (ver PvpDeathWiring).
func _on_pvp_died(killer: Node, victim: Node) -> void:
	if tdm_match == null:
		return
	var killer_key := key_for_player(killer) if is_instance_valid(killer) else ""
	var victim_key := key_for_player(victim)
	if victim_key.is_empty():
		return
	tdm_match.register_kill(killer_key, victim_key)
	print(JSON.stringify({
		"event": "pvp_kill",
		"killer": killer_key,
		"victim": victim_key,
		"placar": tdm_match.team_score_text(),
	}))


## Verdadeiro so na TRANSICAO de sala ocupada para sala vazia (nao no estado
## "vazia"), senao o servidor dedicado reiniciaria a partida a cada frame parado.
func _room_just_emptied(players_now: int) -> bool:
	return _previous_player_count > 0 and players_now == 0


## Quantos jogadores de verdade (bots de PVP contam, SWAT nao) estao na sala.
## Uso: if pvp.room_player_count() == 0: ...
func room_player_count() -> int:
	var total := 0
	for key in world.network_players.keys():
		var player = world.network_players.get(key)
		if is_instance_valid(player) and not bool(player.get("is_swat_bot")):
			total += 1
	return total


func _announce_end() -> void:
	restart_left = RESTART_SECONDS
	print(JSON.stringify({
		"event": "pvp_over",
		"winner_team": tdm_match.winner(),
		"score": tdm_match.team_score_text(),
		"standings": tdm_match.standings(),
	}))


## Avanca a partida: relogio, IA dos bots, respawn e broadcast do estado.
## Sala VAZIA nao consome relogio: o servidor dedicado e um servico que espera
## jogador (mesma regra de SurvivalWaveController.everyone_is_down).
## Uso: chamado em _physics_process no servidor/offline.
func tick(delta: float) -> void:
	if tdm_match == null:
		return
	var players_now := room_player_count()
	if _room_just_emptied(players_now):
		# Ultimo jogador saiu: placar novo para quem entrar depois, em vez de
		# achar uma partida no fim com o placar de outra gente.
		_start_new_match()
	_previous_player_count = players_now
	if players_now == 0:
		return
	var was_over := tdm_match.is_over()
	tdm_match.tick(delta)
	_tick_bots(delta)
	_tick_players(delta)
	if tdm_match.is_over() and not was_over and restart_left <= 0.0:
		_announce_end()
	if restart_left <= 0.0:
		_broadcast_state()
		return
	restart_left -= delta
	if restart_left > 0.0:
		_broadcast_state()
		return
	restart_left = 0.0
	_start_new_match()


## Relogios e respawn de cada jogador. No mata-mata contínuo quem morre volta
## sozinho em TdmMatch.RESPAWN_SECONDS, na propria base e invulneravel — nao ha
## rodada para esperar (o formato antigo deixava o morto fora ate a proxima).
func _tick_players(delta: float) -> void:
	for key in world.network_players.keys().duplicate():
		var player = world.network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		player.tick_pvp(delta)
		if tdm_match.is_over() or not bool(player.get("is_eliminated")):
			continue
		if float(player.get("pvp_respawn_left")) > 0.0:
			continue
		player.pvp_respawn_at(spawn_position_for(player))


## Estado da partida para os clientes (HUD e menu de loadout), 2 Hz.
func _broadcast_state() -> void:
	if not NetworkSession.is_server():
		return
	_state_elapsed += 1.0 / 30.0
	if _state_elapsed < 0.5:
		return
	_state_elapsed = 0.0
	world.call("broadcast_pvp_state", tdm_match.hud_text())


## Partida nova: placar limpo, times refeitos e todo mundo de volta na base (o
## proprio register_player faz o nascimento).
func _start_new_match() -> void:
	tdm_match = TdmMatch.new()
	restart_left = 0.0
	for key in world.network_players.keys().duplicate():
		var player = world.network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		player.set("pvp_kills", 0)
		player.set("pvp_deaths", 0)
		register_player(player)
	print(JSON.stringify({"event": "pvp_restart"}))


## Ponto de spawn do jogador: base do time dele (lados opostos do mapa).
func spawn_position_for(player: Node) -> Vector3:
	var key := key_for_player(player)
	var team: int = tdm_match.team_of(key) if not key.is_empty() else 0
	if team < 0 or team >= TEAM_SAFEHOUSES.size():
		team = 0
	spawn_counters[team] += 1
	if bot_keys.has(key):
		# Bot nasce e RENASCE no quintal: sair da casa com movimento sem
		# pathfinding prendia ele num canto interno ate o fim da partida. O
		# indice da rota volta ao comeco para ele refazer o caminho das ruas.
		bot_route_index.erase(key)
		return _bot_yard_spawn_for_team(team, spawn_counters[team])
	# Humano: marcador FIXO da safehouse do time, girando entre os 4 para nao
	# empilhar.
	var slot := posmod(spawn_counters[team], 4) + 1
	var marker := world.get_node_or_null("GeneratedCity/%s/PlayerSpawn%d" % [TEAM_SAFEHOUSES[team], slot]) as Marker3D
	if marker != null:
		return marker.global_position
	return TEAM_BASE_FALLBACK[team]


## Centro (no chao) da safehouse do time; fallback se a casa nao existir.
func team_base(team: int) -> Vector3:
	if team < 0 or team >= TEAM_SAFEHOUSES.size():
		return TEAM_BASE_FALLBACK[0]
	var house := world.get_node_or_null("GeneratedCity/" + TEAM_SAFEHOUSES[team]) as Node3D
	if house != null:
		return house.global_position
	return TEAM_BASE_FALLBACK[team]


## Verdadeiro quando o jogador esta DENTRO da propria base. So muda o quando da
## troca de arma: dentro vale na hora, fora vale no proximo respawn.
func in_base_zone(player: Node) -> bool:
	if tdm_match == null:
		return false
	var key := key_for_player(player)
	var team: int = tdm_match.team_of(key) if not key.is_empty() else -1
	if team < 0:
		return false
	var position := (player as Node3D).global_position
	var base := team_base(team)
	return Vector2(position.x - base.x, position.z - base.z).length() <= BASE_RADIUS


## Escolha de arma do jogador: sem preco e sem fase, e so guardar o pedido. Vale
## na hora quando ele esta na propria base (ou ainda protegido do respawn);
## caso contrario entra na proxima vida — trocar de fuzil no meio do tiroteio
## seria arma infinita de graca.
## Devolve "" quando equipou agora, ou a mensagem que o HUD mostra.
## Uso: var aviso := pvp.choose_loadout(player, WeaponStats.Kind.AK47)
func choose_loadout(player: Node, kind: int) -> String:
	if tdm_match == null or not is_instance_valid(player):
		return "Sem partida de mata-mata."
	if not WeaponStats.is_crate_weapon(kind):
		return "Arma desconhecida."
	player.choose_pvp_loadout(kind)
	var label := String(WeaponStats.stats_for(kind).get("label", kind))
	if not in_base_zone(player) and float(player.get("spawn_protection_left")) <= 0.0:
		return "%s equipada no proximo respawn." % label
	if not player.equip_crate_weapon(kind):
		return "Nao deu para equipar %s." % label
	return ""
