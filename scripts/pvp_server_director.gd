class_name PvpServerDirector
extends RefCounted

## Mata-mata (--pvp) do lado que simula: bots, rota entre as duas bases,
## rodadas, compra e o estado que vai para o HUD dos clientes. Saiu do main.gd
## (2407 linhas) para o mata-mata parar de disputar espaco com a sobrevivencia.
##
## O `world` e o no da partida (scenes/main.tscn): ele continua dono da arvore
## de nos, dos RPCs e do dicionario de jogadores de rede. No cliente o diretor
## existe mas `pvp_match` fica nulo: ali ele so guarda as chaves dos bots, que
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
## elas). Cada time nasce nos marcadores fixos PlayerSpawn1..4 da sua casa e so
## compra DENTRO dela. A casa central continua sendo a da sobrevivencia.
const TEAM_SAFEHOUSES := ["PvpSafehouseA", "PvpSafehouseB"]
## Fallback quando a cidade nao tem as casas (modo legacy/teste).
const TEAM_BASE_FALLBACK := [Vector3(-58.5, 1.18, -58.5), Vector3(58.5, 1.18, 58.5)]
## Raio da zona de compra em volta da casa (a casa tem 12,8 m de lado). Subiu
## para 9 m porque os bots nascem no quintal, na frente da porta (7,6 m).
const BASE_RADIUS := 9.0
## Bots de PVP nascem no QUINTAL, na frente da porta da propria base: nascer
## dentro da casa dependia de o bot achar a saida com movimento sem pathfinding,
## e ele ficava preso num canto interno oscilando ate estourar a rodada
## (medido: 80 s parado com o alvo a 126 m).
const BOT_YARD_DISTANCE := 7.6
## Espalhamento lateral entre os bots do mesmo time, no quintal.
const BOT_YARD_SPREAD := 1.4
## Distancia para considerar um waypoint da rota alcancado (o alvo passa a ser o
## proximo). Uso: ver bot_hunt_position.
const WAYPOINT_ARRIVE_RADIUS := 6.0
## Rota entre as duas casas pelo ANEL DE RUAS do perimetro (as ruas ficam em
## -72/-24/24/72 e os quarteiroes vao ate 69, entao o anel externo e o unico
## caminho sem predio no meio). As duas portas davam para o mesmo lado (Z local):
## a casa B foi girada 180 graus, entao cada porta cai a ~4 m da sua rua de
## perimetro. O time 0 desce a rua de baixo, sobe a direita e entra na casa B
## pela porta; o time 1 percorre a mesma rota ao contrario, de frente um com o
## outro.
const STREET_ROUTE := [
	Vector3(-58.5, 1.3, -72.0),
	Vector3(72.0, 1.3, -72.0),
	Vector3(72.0, 1.3, 72.0),
	Vector3(58.5, 1.3, 72.0),
	Vector3(58.5, 1.3, 58.5),
]

## No da partida (scenes/main.tscn): arvore de nos, RPCs e jogadores de rede.
var world: Node3D
## Economia, placar e fases. Nulo no cliente, que so recebe o estado pronto.
var pvp_match: PvpMatch = null
## Chaves dos bots criados aqui, no formato do dicionario de jogadores de rede.
var bot_keys: Dictionary = {}
## Contagem para comecar uma partida nova depois do fim (0 = sem partida).
var restart_left := 0.0
## Gira os marcadores fixos de spawn de cada time (nao empilha os 4 no mesmo).
var spawn_counters: Array[int] = [0, 0]
## Rota invertida (time 1) preguicosa: ver _reversed_route().
var reversed_route: Array = []
## Waypoint atual de cada bot (chave -> indice), monotonico por rodada.
var bot_route_index: Dictionary = {}
## Cadencia do broadcast de estado (2 Hz num servidor de 30 Hz).
var _state_elapsed := 0.0


func _init(world_node: Node3D = null) -> void:
	world = world_node


## Comeca a partida. So no servidor/offline: e o lado que simula.
## Uso: if not NetworkSession.is_client(): pvp.start_match()
func start_match() -> void:
	pvp_match = PvpMatch.new()


## Verdadeiro onde a partida e simulada (servidor/offline).
func is_active() -> bool:
	return pvp_match != null


func is_buy_phase() -> bool:
	return pvp_match != null and pvp_match.phase == PvpMatch.Phase.BUY


func hud_text() -> String:
	return pvp_match.hud_text() if pvp_match != null else ""


func bot_count() -> int:
	return bot_keys.size()


func has_bot(key: String) -> bool:
	return bot_keys.has(key)


## Jogador saiu: tira do placar para a rodada nao esperar por um fantasma.
func forget_player(key: String) -> void:
	if pvp_match != null:
		pvp_match.remove_player(key)


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
	bot.set_color_index(index + 1)
	bot.set("input_device_name", "Bot PVP %d" % (index + 1))
	if simulate:
		bot.reset_pvp_loadout()
	world.network_players[key] = bot
	bot_keys[key] = true
	if simulate:
		register_player(bot)
		# O time so existe depois do register: e ele que decide a casa/marcador.
		bot.global_position = spawn_position_for(bot)
		bot.set_spawn_position(bot.global_position)


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
		_bot_try_buy(bot)
		if pvp_match.phase == PvpMatch.Phase.BUY:
			bot.apply_network_input(PvpMatch.frozen_input({}))
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
	if pvp_match == null or not is_instance_valid(bot):
		return team_base(1)
	var key := key_for_player(bot)
	var team: int = pvp_match.team_of(key)
	var enemy_team := 0 if team == 1 else 1
	var route: Array = STREET_ROUTE if team == 0 else _reversed_route()
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


## Rota do time 1 montada UMA vez. Antes ela era criada a cada chamada, e a
## chamada roda por bot a cada tick (4 bots a 30 Hz = 120 Arrays por segundo).
func _reversed_route() -> Array:
	if reversed_route.is_empty():
		for index in range(STREET_ROUTE.size() - 1, -1, -1):
			reversed_route.append(STREET_ROUTE[index])
	return reversed_route


## Bot compra na fase de compra, na propria base, a arma mais cara que couber.
## E o mesmo caminho do humano (money -> spend -> equipar), so sem menu.
func _bot_try_buy(bot: Node) -> void:
	if pvp_match == null or pvp_match.phase != PvpMatch.Phase.BUY:
		return
	if not in_buy_zone(bot):
		return
	var key := key_for_player(bot)
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
	if not request_purchase(bot, wanted).is_empty():
		return
	print(JSON.stringify({"event": "pvp_buy", "key": key, "kind": wanted, "price": WeaponStats.price_for(wanted)}))


## Entra na partida com a economia inicial e a janela de compra aberta.
## Uso: chamado no spawn de cada jogador (servidor/offline).
func register_player(player: Node) -> void:
	if pvp_match == null or not is_instance_valid(player):
		return
	var key := key_for_player(player)
	if key.is_empty():
		return
	pvp_match.register_player(key)
	player.set("pvp_money", pvp_match.money_of(key))
	PvpDeathWiring.connect_once(player, self)


## Chave de rede do jogador ("" quando nao esta no dicionario).
func key_for_player(player: Node) -> String:
	for key in world.network_players:
		if world.network_players[key] == player:
			return String(key)
	return ""


## Abate: credita quem matou, conta a morte e encerra a partida quando alguem
## chega no alvo. Callable.bind anexa a vitima no FIM da lista.
## Uso: conectado ao sinal pvp_died de cada jogador (ver PvpDeathWiring).
func _on_pvp_died(killer: Node, victim: Node) -> void:
	if pvp_match == null:
		return
	var killer_key := key_for_player(killer) if is_instance_valid(killer) else ""
	var victim_key := key_for_player(victim)
	if victim_key.is_empty():
		return
	pvp_match.register_kill(killer_key, victim_key)
	print(JSON.stringify({"event": "pvp_kill", "killer": killer_key, "victim": victim_key, "team_kills": pvp_match.kills_of(killer_key)}))
	_check_round_end()


## A rodada acaba quando um time inteiro cai (o outro leva); o tempo estourando
## e tratado no tick. Uso: chamado a cada abate.
func _check_round_end() -> void:
	if pvp_match.phase != PvpMatch.Phase.LIVE:
		return
	var alive := _alive_per_team()
	if alive[0] > 0 and alive[1] > 0:
		return
	if alive[0] == 0 and alive[1] == 0:
		pvp_match.finish_round(-1, "eliminacao")
		return
	pvp_match.finish_round(0 if alive[0] > 0 else 1, "eliminacao")


## Vivos por time (decide a rodada). Bots de SWAT nao contam.
func _alive_per_team() -> Array[int]:
	var alive: Array[int] = [0, 0]
	for key in world.network_players.keys():
		var player = world.network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		if bool(player.get("is_eliminated")):
			continue
		var team: int = pvp_match.team_of(String(key))
		if team >= 0 and team < alive.size():
			alive[team] += 1
	return alive


func _announce_end() -> void:
	restart_left = RESTART_SECONDS
	print(JSON.stringify({"event": "pvp_over", "winner_team": pvp_match.match_winner(), "score": pvp_match.team_score_text(), "standings": pvp_match.standings()}))


## Avanca a partida: fases/rodadas, IA dos bots, respawn e broadcast do estado.
## Uso: chamado em _physics_process no servidor/offline.
func tick(delta: float) -> void:
	if pvp_match == null:
		return
	var phase_before: int = pvp_match.phase
	var round_before: int = pvp_match.round_index
	_close_round_if_due(delta)
	pvp_match.tick(delta)
	_tick_bots(delta)
	_tick_players(delta)
	if round_before != pvp_match.round_index or (phase_before != pvp_match.phase and pvp_match.phase == PvpMatch.Phase.BUY):
		print(JSON.stringify({"event": "pvp_round", "round": pvp_match.round_index, "score": pvp_match.team_score_text(), "rodada_anterior": pvp_match.last_round_report()}))
	if pvp_match.is_over() and restart_left <= 0.0 and phase_before != PvpMatch.Phase.MATCH_END:
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


## Fecha a rodada por morte de todo mundo ou por tempo estourado.
func _close_round_if_due(delta: float) -> void:
	if pvp_match.phase != PvpMatch.Phase.LIVE:
		return
	if _alive_per_team() == [0, 0]:
		# Ninguem vivo (rodada travada em 0x0 por morte simultanea/queda).
		pvp_match.finish_round(-1, "sem_vivos")
		return
	if float(pvp_match.phase_left) <= delta:
		# Tempo estourou: quem tem mais gente viva leva a rodada.
		pvp_match.finish_round_by_time(_alive_per_team())


## Dinheiro, relogios e respawn de cada jogador de verdade.
func _tick_players(delta: float) -> void:
	for key in world.network_players.keys().duplicate():
		var player = world.network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		player.tick_pvp(delta)
		player.set("pvp_money", pvp_match.money_of(String(key)))
		# Estilo CS: quem morre fica fora ate o fim da rodada; o respawn
		# acontece quando a proxima fase de compra abre (senao a rodada nunca
		# fecha, porque o time eliminado volta em 3 s).
		if pvp_match.phase != PvpMatch.Phase.BUY:
			continue
		if not bool(player.get("is_eliminated")):
			continue
		player.pvp_respawn_at(spawn_position_for(player))


## Estado da partida para os clientes (HUD e dica do menu de compra), 2 Hz.
func _broadcast_state() -> void:
	if not NetworkSession.is_server():
		return
	_state_elapsed += 1.0 / 30.0
	if _state_elapsed < 0.5:
		return
	_state_elapsed = 0.0
	var in_buy := pvp_match.phase == PvpMatch.Phase.BUY
	world.call("broadcast_pvp_state", pvp_match.hud_text(), in_buy, pvp_match.phase_left if in_buy else 0.0)


## Partida nova: economia zerada, placar limpo e todo mundo na base.
func _start_new_match() -> void:
	pvp_match = PvpMatch.new()
	restart_left = 0.0
	for key in world.network_players.keys().duplicate():
		var player = world.network_players.get(key)
		if not is_instance_valid(player) or bool(player.get("is_swat_bot")):
			continue
		register_player(player)
		player.set("pvp_kills", 0)
		player.set("pvp_deaths", 0)
		player.pvp_respawn_at(spawn_position_for(player))
	print(JSON.stringify({"event": "pvp_restart"}))


## Ponto de spawn do jogador: anel na base do time dele (lados opostos do mapa).
func spawn_position_for(player: Node) -> Vector3:
	var key := key_for_player(player)
	var team: int = pvp_match.team_of(key) if not key.is_empty() else 0
	if team < 0 or team >= TEAM_SAFEHOUSES.size():
		team = 0
	spawn_counters[team] += 1
	if bot_keys.has(key):
		# Bot nasce e RENASCE no quintal: sair da casa com movimento sem
		# pathfinding prendia ele num canto interno ate estourar a rodada. O
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


## Verdadeiro quando o jogador esta DENTRO da propria safehouse (zona de compra).
func in_buy_zone(player: Node) -> bool:
	var key := key_for_player(player)
	var team: int = pvp_match.team_of(key) if not key.is_empty() else -1
	if team < 0:
		return false
	var position := (player as Node3D).global_position
	var base := team_base(team)
	return Vector2(position.x - base.x, position.z - base.z).length() <= BASE_RADIUS


## Compra pedida pelo cliente: valida fase, base, dinheiro e arma; desconta e
## equipa. Devolve "" quando deu certo, ou o motivo da recusa para o cliente.
func request_purchase(player: Node, kind: int) -> String:
	if pvp_match == null or not is_instance_valid(player):
		return "Sem partida de PVP."
	var key := key_for_player(player)
	var price := WeaponStats.price_for(kind)
	var rejection := pvp_match.buy_rejection(key, price)
	if not rejection.is_empty():
		return rejection
	if not in_buy_zone(player):
		return "Compre na sua base (zona azul no mapa)."
	if not player.equip_crate_weapon(kind):
		return "Nao deu para equipar %s." % WeaponStats.stats_for(kind).get("label", kind)
	pvp_match.spend(key, price)
	player.set("pvp_money", pvp_match.money_of(key))
	return ""
