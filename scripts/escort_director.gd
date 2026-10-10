# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortDirector
extends Node3D

## Modo escolta (experimental, NetworkSession.escort_mode): 3 NPC da familia
## esperam num ponto da rua (ponto A) ate um jogador chegar perto e apertar E.
## So entao eles caminham ate a entrada da safehouse central (ponto B) — e a
## horda, que ja pinga pelo spawner classico, passa a cacar os tres. Vitoria:
## os tres chegam; derrota: os tres morrem. A simulacao roda so no servidor;
## clientes recebem os estados por replicate_state.
## Uso: godot --headless --path . -- --server --escort

const FAMILY_MEMBER_SCRIPT := preload("res://scripts/escort_family_member.gd")
const ESCORT_ROUTE_SCRIPT := preload("res://scripts/escort_route.gd")
const SPAWN_PROFILE_SCRIPT := preload("res://scripts/escort_spawn_profile.gd")
const SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
const MERCHANT_SCRIPT := preload("res://scripts/escort_merchant.gd")

## Variacoes da familia: nome, cor da blusa (tambem a cor no minimapa), escala
## do modelo (crianca menor) e tom de pele. O seed sorteia 3 sem repetir, entao
## a familia pode ser pai/mae/filho ou avo/avo/avoa/neto, etc.
const FAMILY_ROLES: Array[Dictionary] = [
	{"name": "Familiar-Pai", "shirt": Color(0.25, 0.4, 0.75), "skin": Color(0.78, 0.56, 0.42), "scale": 1.0},
	{"name": "Familiar-Mae", "shirt": Color(0.85, 0.35, 0.45), "skin": Color(0.88, 0.68, 0.52), "scale": 0.96},
	{"name": "Familiar-Filho", "shirt": Color(0.9, 0.78, 0.25), "skin": Color(0.82, 0.6, 0.45), "scale": 0.78},
	{"name": "Familiar-Filha", "shirt": Color(0.6, 0.4, 0.85), "skin": Color(0.9, 0.72, 0.6), "scale": 0.74},
	{"name": "Familiar-Avo", "shirt": Color(0.75, 0.75, 0.72), "skin": Color(0.72, 0.52, 0.4), "scale": 0.94},
	{"name": "Familiar-Avoa", "shirt": Color(0.82, 0.72, 0.78), "skin": Color(0.8, 0.6, 0.5), "scale": 0.9},
]
const FAMILY_SIZE := 3
## Limite fisico do mapa (muro) e folga que a familia nunca cruza.
const MAP_HALF_EXTENT := 96.0
const MAP_MARGIN := 10.0
## Distancia em que o E de um jogador vale como "quero comecar a escolta".
const START_INTERACT_RADIUS := 4.5
## Raio de "chegou" no ponto B (o minimapa/marcador usa o mesmo centro).
const ARRIVAL_RADIUS := 2.5
## Quanto a frente da porta da safehouse e o ponto de chegada: a familia tem de
## PASSAR pela porta (bug antigo: paravam na calcada de fora).
const SAFEHOUSE_DOOR_CLEARANCE := 2.5
## Quanto o ponto B entra porta adentro. Com o B so na frente da porta o trio
## "chegava do lado de fora e nao entrava na base".
const SAFEHOUSE_ENTRY_DEPTH := 4.5
## Inicio da escolta: canto SUDOESTE do mapa, na rua externa. Daqui a rota faz
## a serpentina (zigue-zague em S) pelas oito ruas e termina na safehouse da
## ponta leste. As esquinas vivem no EscortRoute.
const ESCORT_START := Vector3(-72.0, 1.2, -72.0)
## Modo teste: familia imortal enquanto safe zone/checkpoints nao existem.
## Trocar para false quando o balanceamento de verdade comecar (ver
## EscortFamilyMember.take_damage).
const TEST_INVULNERABLE := true
## Alvo de duracao do trajeto em segundos: o comprimento total da serpentina define
## o passo dos civis, entao a missao dura ~este tempo (10 min) em vez de acabar
## em 3 minutos num pula-pula reto.
const ZIGZAG_TARGET_SECONDS := 600.0
const ZIGZAG_MIN_SPEED := 1.3
const ZIGZAG_MAX_SPEED := 3.0
## Tempo logo apos sair da casa em que a familia so anda: sem mirar/atirar, para
## nao voltar pra dentro da casa e ficar atirando de la com a horda na porta.
const EXIT_HOLD_FIRE_SECONDS := 6.0
## Vagas laterais da formacao: o trio anda lado a lado, nao em fila indiana.
## Estreitas de proposito: a rua do corredor tem ~3,5 m de meio-vao e vaga
## larga jogava o civil para dentro do lote vizinho.
const FORMATION_OFFSETS: Array[float] = [-1.2, 0.0, 1.2]
## Variacao de passo por vaga (o grupo estica e encolhe sem andar colado).
const FORMATION_SPEEDS: Array[float] = [0.96, 1.04, 1.0]
## Parada da escolta: o predio do lote do checkpoint (casa/mercearia gerada) faz
## as vezes da casinha. Folga em frente a porta, quanto anda porta adentro e o
## raio de busca da porta em volta do lote.
const SHELTER_DOOR_CLEARANCE := 2.5
const SHELTER_INSIDE_DEPTH := 2.0
const SHELTER_FIND_RADIUS := 16.0
## Onde a familia deixa a rua e vira de frente para o vao. Longe o bastante da
## fachada para a ultima perna ser RETA na normal da porta: chegando na diagonal
## o civil raspava a ombreira, o desvio de parede o levava rodeando o predio e o
## resgate acabava teleportando ele para dentro (medido em 2026-09-28).
const SHELTER_APPROACH_DISTANCE := 6.5
## Distancia da porta em que um civil andando faz a porta abrir (ele nao tem E).
const SHELTER_DOOR_OPEN_RADIUS := 3.0
## Profundidade do predio sintetico de fallback (lote sem predio procedural).
const SHELTER_DEPTH := 11.0
## Zumbi dentro deste raio do ponto de parada e jogado de volta para a rua.
const SHELTER_INTERIOR_RADIUS := 6.0
const SHELTER_EVICT_DISTANCE := 9.0
## Rota picotada de 24 em 24 m: trecho longo acumula desvio de obstaculo e o
## NPC encosta no predio (licao medida no roteamento dos bots de PVP).
const ROUTE_STEP := 24.0
## Anel de busca de piso aberto em volta de um candidato (passo e voltas).
const GROUND_SEARCH_STEP := 3.0
const GROUND_SEARCH_RINGS := 4

signal escort_finished(victory: bool)

var status_text := "A familia espera: aproxime-se e aperte E para comecar a escolta."
var members: Array[EscortFamilyMember] = []
## Papeis sorteados para esta partida (nome/blusa/escala); ver FAMILY_ROLES.
var family_roles: Array[Dictionary] = []
var point_a := Vector3.ZERO
var point_b := Vector3.ZERO
var mission_started := false
var finished_victory := false
var finished_defeat := false

var _spawn_locator = SPAWN_LOCATOR_SCRIPT.new()
## Ultimo ponto antes do B: a frente da porta (ver _build_street_route).
var _route_via := Vector3.ZERO
## Para onde a porta da safehouse olha; diz por qual rua a familia entra.
var _safehouse_outward := Vector3.ZERO
## Indices da rota no fim de cada perna da serpentina (esquinas = checkpoints).
var checkpoint_indices: Array[int] = []
## Indices da rota onde o civil fica passivo (dentro da casa e saida dela).
var no_fire_route_indices := {}
## Indices do FUNIL da porta (os 5 pontos da parada): ali o trio anda em fila e
## so troca de waypoint ao chegar de verdade, para entrar no vao de frente.
var funnel_route_indices := {}
## Checkpoint que a familia esta liberando (indice em checkpoint_indices).
var next_checkpoint := 0
## true enquanto a familia espera o E na zona segura.
var waiting_at_checkpoint := false
## Geometria da parada de cada checkpoint: porta do predio do lote (ou um
## fallback sintetico se o lote veio vazio). Ver _place_shelters.
var _shelter_sites: Array[Dictionary] = []
## Onde cada mercador foi posto (x/z/yaw); vai no estado para o cliente montar os
## mercadores dele, senao a loja nao abre (o diretor so roda no servidor).
var merchant_spots: Array[Dictionary] = []


func _ready() -> void:
	# O minimapa acha o ponto B por este grupo.
	add_to_group("escort_director")


## Uso: diretor.start(get_tree(), self, NetworkSession.world_seed)
func start(tree: SceneTree, root: Node, world_seed: int) -> void:
	point_a = _clamp_to_map(ESCORT_START)
	_pick_safehouse_door_points(tree, root)
	_place_shelters()
	_place_merchants(root)
	family_roles = _pick_roles(world_seed)
	_spawn_family(root)
	_rebuild_waiting_text()
	print(JSON.stringify({
		"event": "escort_started",
		"point_a": [point_a.x, point_a.z],
		"point_b": [point_b.x, point_b.z],
		"members": members.size(),
		"roles": family_roles.map(func(role: Dictionary) -> String: return String(role["name"])),
	}))


## Sorteia FAMILY_SIZE papeis civis distintos pelo seed do mundo. Uso: start.
func _pick_roles(world_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var pool := FAMILY_ROLES.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < FAMILY_SIZE and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove_at(index)
	return picked


func tick(delta: float, tree: SceneTree) -> void:
	if finished_victory or finished_defeat:
		return
	if not mission_started:
		# Dev: --escort-autostart comeca a escolta sem precisar do E (o headless
		# nao tem input; tambem e util para testar a rota inteira sozinho) e
		# libera cada checkpoint sozinho.
		if _autostart_enabled() or _player_pressed_interact_near_family(tree):
			begin_mission()
		return
	_check_arrivals()
	_open_shelter_doors()
	_check_group_status()
	_update_checkpoints(tree)
	_debug_progress(delta)


## Diagnostico temporario (--escort-debug): a cada 1 s diz onde cada civil esta,
## em qual waypoint, se anda e se esta com medo.
var _debug_elapsed := 0.0


func _debug_progress(delta: float) -> void:
	if not ("--escort-debug" in OS.get_cmdline_user_args()):
		return
	_debug_elapsed += delta
	if _debug_elapsed < 1.0:
		return
	_debug_elapsed = 0.0
	for member in members:
		if not is_instance_valid(member):
			continue
		print(JSON.stringify({
			"event": "escort_debug_member",
			"name": String(member.name),
			"pos": [snappedf(member.global_position.x, 0.1), snappedf(member.global_position.z, 0.1)],
			"waypoint": member._route_index,
			"of": member.route.size(),
			"walking": member.walking,
			"targetable": member.targetable,
			"speed": snappedf(Vector3(member.velocity.x, 0.0, member.velocity.z).length(), 0.01),
			"no_progress": snappedf(member._progress_watch.no_progress_seconds, 0.1),
			"blocked": snappedf(member._progress_watch.blocked_seconds, 0.1),
			"in_route": member._indoor_router.has_route,
			"detour": member._wall_detour.is_active(),
			"touch": member._debug_touch,
			"panic": member.is_panicked(),
			"hold_fire": snappedf(member.hold_fire_seconds, 0.1),
			"escaped": member.escaped,
			"to_b": snappedf(Vector2(member.global_position.x - point_b.x, member.global_position.z - point_b.z).length(), 0.1),
		}))


## A familia so sai do ponto A quando um jogador chega perto e aperta E; depois
## disso ela caminha de checkpoint em checkpoint (cada esquina da serpentina),
## esperando um novo E dentro da zona segura.
## Uso: diretor.begin_mission()
func begin_mission() -> void:
	if mission_started:
		return
	mission_started = true
	var walk_route := _build_zigzag_route(point_a, point_b)
	# Ritmo dos civis: a rota da a volta no mapa, entao um passo civil lento
	# (nao o trote de 3 m/s) faz o trajeto durar ~10 min, com tempo de defender.
	var walk_speed := clampf(_route_length(walk_route) / ZIGZAG_TARGET_SECONDS, ZIGZAG_MIN_SPEED, ZIGZAG_MAX_SPEED)
	next_checkpoint = 0
	waiting_at_checkpoint = false
	var first_halt := checkpoint_indices[0] if not checkpoint_indices.is_empty() else -1
	for member in members:
		if not is_instance_valid(member):
			continue
		member.route = walk_route.duplicate()
		member.walk_speed = walk_speed
		member.halt_route_index = first_halt
		member.no_fire_indices = no_fire_route_indices.duplicate()
		member.funnel_indices = funnel_route_indices.duplicate()
		member.hold_fire_seconds = 0.0
		member.walking = true
		member.targetable = true
	_rebuild_walking_text()


## Rota serpentina HORIZONTAL: sai do canto sudoeste, anda a rua de baixo
## inteira para o leste, sobe uma rua, volta pela horizontal seguinte, e no fim
## entra na safehouse pela rua de cima. So a PONTA de cada fileira tem casa. Cada trecho e picotado (ROUTE_STEP) porque nao
## ha navmesh: quem contorna obstaculo e o ZombieWallDetour do civil.
##
## A familia SO sai do asfalto para entrar na casa do checkpoint, e volta para a
## MESMA esquina antes de seguir. Sem esse retorno a perna seguinte partia de
## dentro da casa e cortava por cima dos lotes (medido em 2026-09-28: 493 m dos
## 860 m fora de rua, atravessando predios).
## Uso: var rota := _build_zigzag_route(director.point_a, director.point_b)
func _build_zigzag_route(start: Vector3, finish: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = [start]
	var markers: Array[int] = []
	# Pontos onde a familia fica passiva: parada dentro da casa E a saida dela.
	var no_fire_points: Array[int] = []
	# Pontos do funil da porta (a parada inteira, entrada e saida).
	var funnel_points: Array[int] = []
	var corners := _route_corner_points()
	for index in corners.size():
		points.append(corners[index])
		var checkpoint: int = ESCORT_ROUTE_SCRIPT.CHECKPOINT_CORNER_INDICES.find(index)
		if checkpoint < 0:
			# Virada de subida entre duas fileiras: a familia dobra e segue.
			continue
		var site := _shelter_sites[checkpoint] if checkpoint < _shelter_sites.size() else {}
		if site.is_empty():
			markers.append(points.size() - 1)
			continue
		# Vira de frente para o vao antes de entrar: a perna final e reta.
		points.append(site["approach_far"])
		points.append(site["approach"])
		points.append(site["inside"])
		# Sai da casa pelo mesmo vao antes de seguir para a proxima esquina.
		points.append(site["approach"])
		points.append(site["approach_far"])
		markers.append(points.size() - 3)
		no_fire_points.append(points.size() - 3)
		no_fire_points.append(points.size() - 2)
		no_fire_points.append(points.size() - 1)
		for offset in [5, 4, 3, 2, 1]:
			funnel_points.append(points.size() - offset)
		# Volta ao asfalto da esquina antes da proxima perna (ver docstring).
		points.append(corners[index])
	# Entrada da safehouse: desce a rua ate a linha da porta e so entao cruza o
	# vao em linha reta. Sem isso o trio cortava o quarteirao na diagonal.
	if _route_via != Vector3.ZERO:
		points.append_array(final_street_approach(points[points.size() - 1], _route_via, _safehouse_outward))
		points.append(_route_via)
	points.append(finish)
	var route: Array[Vector3] = []
	checkpoint_indices.clear()
	no_fire_route_indices.clear()
	funnel_route_indices.clear()
	var finish_index := points.size() - 1
	var via_index := finish_index - 1 if _route_via != Vector3.ZERO else -1
	var markers_lookup := {}
	for marker in markers:
		markers_lookup[marker] = true
	var no_fire_lookup := {}
	for point_index in no_fire_points:
		no_fire_lookup[point_index] = true
	var funnel_lookup := {}
	for point_index in funnel_points:
		funnel_lookup[point_index] = true
	for index in range(1, points.size()):
		_append_subdivided_leg(route, points[index - 1], points[index])
		# O waypoint marcado no fim desta perna e onde a familia para.
		if index != finish_index and index != via_index and markers_lookup.has(index):
			checkpoint_indices.append(route.size() - 1)
		if no_fire_lookup.has(index):
			no_fire_route_indices[route.size() - 1] = true
		if funnel_lookup.has(index):
			funnel_route_indices[route.size() - 1] = true
	if route.is_empty():
		route.append(finish)
	return route


## Pontas de fileira com casa, na ordem da rota: sao os checkpoints.
func _escort_checkpoint_corners() -> Array[Vector3]:
	return _at_route_height(ESCORT_ROUTE_SCRIPT.checkpoint_corners())


## TODAS as viradas da serpentina, com e sem casa. Uso: _build_zigzag_route.
func _route_corner_points() -> Array[Vector3]:
	return _at_route_height(ESCORT_ROUTE_SCRIPT.route_corners())


## Poe uma lista de pontos na altura que a familia anda. Uso interno.
func _at_route_height(corners: Array[Vector3]) -> Array[Vector3]:
	var placed: Array[Vector3] = []
	for corner in corners:
		placed.append(Vector3(corner.x, point_a.y, corner.z))
	return placed


## Acha, por checkpoint, a parada no predio procedural do lote: a porta DA RUA
## vira o ponto de entrada e a familia espera logo porta adentro. Sem predio ou
## porta externa no lote, cai no fallback sintetico _shelter_geometry.
func _place_shelters() -> void:
	_shelter_sites.clear()
	var corners := _escort_checkpoint_corners()
	var lot_centers: Array = ESCORT_ROUTE_SCRIPT.checkpoint_lot_centers()
	for index in corners.size():
		if index >= lot_centers.size():
			_shelter_sites.append({})
			continue
		var lot_center: Vector2 = lot_centers[index]
		var site := _find_shelter_site(lot_center, corners[index])
		if site.is_empty():
			site = _shelter_geometry(lot_center, corners[index])
		_shelter_sites.append(site)
		var site_position: Vector3 = site["position"]
		print(JSON.stringify({
			"event": "escort_shelter",
			"index": _shelter_sites.size(),
			"position": [snappedf(site_position.x, 0.1), snappedf(site_position.z, 0.1)],
			"used_building_door": site.has("door"),
		}))
	print(JSON.stringify({"event": "escort_shelters_placed", "count": _shelter_sites.size()}))


## Poe um mercador de preto dentro de cada casa de checkpoint, 1,3 m ao lado da
## parada (o vao e estreito). Persiste a missao toda; a loja (EscortShopMenu)
## abre por proximidade. Uso: start.
func _place_merchants(root: Node) -> void:
	for index in _shelter_sites.size():
		var site: Dictionary = _shelter_sites[index]
		if site.is_empty():
			continue
		var direction: Vector3 = site["door_direction"]
		var lateral := Vector3(-direction.z, 0.0, direction.x)
		var spot: Vector3 = site["inside"] + lateral * 1.3
		var yaw := float(site.get("yaw", 0.0))
		var merchant := MERCHANT_SCRIPT.new_merchant(root, "EscortMerchant%d" % (index + 1))
		merchant.global_position = Vector3(spot.x, point_a.y, spot.z)
		merchant.rotation.y = yaw
		merchant_spots.append({"x": spot.x, "z": spot.z, "yaw": yaw})
		print(JSON.stringify({
			"event": "escort_merchant",
			"index": index + 1,
			"position": [snappedf(spot.x, 0.1), snappedf(spot.z, 0.1)],
		}))


## Porta da rua do predio do lote, com a parada derivada dela: o approach fica
## na calcada em frente e o inside logo porta adentro.
## Devolve {} se o lote nao tem porta externa. Uso: interno de _place_shelters.
func _find_shelter_site(lot_center: Vector2, corner: Vector3) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var lot_position := Vector3(lot_center.x, point_a.y, lot_center.y)
	var door := _nearest_shelter_door(tree, lot_position, SHELTER_FIND_RADIUS, corner)
	if door == null:
		return {}
	var site := shelter_points(door.global_position, _door_wall_normal(door), corner)
	site["position"] = lot_position
	site["door"] = door
	return site


## Normal da PAREDE da porta, em mundo. A folha gira ao abrir, entao a base vem
## do predio (o pai), nao do no da porta. Uso: interno de _find_shelter_site.
func _door_wall_normal(door: Node3D) -> Vector3:
	var local := Vector3.BACK
	if door.has_method("wall_normal"):
		local = door.call("wall_normal")
	var building := door.get_parent() as Node3D
	var basis := building.global_transform.basis if building != null else door.global_transform.basis
	var normal := basis * local
	normal.y = 0.0
	return normal.normalized() if normal.length_squared() > 0.0001 else Vector3.BACK


## Os pontos da parada a partir da porta, TODOS na reta da normal dela:
## `approach_far` onde se deixa a rua, `approach` na calcada e `inside` porta
## adentro. Entrar de frente e o que faz o civil passar pelo vao em vez de
## raspar a fachada. A direcao sai da NORMAL DA PAREDE, nao da
## direcao porta -> esquina: com a porta de lado essa direcao antiga metia o
## approach dentro da casa e o inside no quintal (relato de 2026-09-28).
## Pura: da para testar sem cena.
## Uso: var parada := EscortDirector.shelter_points(porta, normal, esquina)
static func shelter_points(door_position: Vector3, door_normal: Vector3, corner: Vector3) -> Dictionary:
	var outward := Vector3(door_normal.x, 0.0, door_normal.z)
	outward = outward.normalized() if outward.length_squared() > 0.0001 else Vector3.BACK
	# A normal pode apontar para dentro; quem manda e o lado onde esta a rua.
	if outward.dot(Vector3(corner.x - door_position.x, 0.0, corner.z - door_position.z)) < 0.0:
		outward = -outward
	var eye := door_position + Vector3(0.0, 1.0, 0.0)
	return {
		"yaw": atan2(-outward.x, -outward.z),
		"door_direction": outward,
		"approach_far": eye + outward * SHELTER_APPROACH_DISTANCE,
		"approach": eye + outward * SHELTER_DOOR_CLEARANCE,
		"inside": eye - outward * SHELTER_INSIDE_DEPTH,
	}


## Elbow de rua antes da porta da safehouse: desce pela rua da ultima esquina
## ate a linha de rua que passa em frente a porta e so entao anda ate ela.
## `outward` e para onde a porta olha. Devolve [] quando a esquina ja esta nessa
## linha. Pura: da para testar sem cena.
## Uso: var entrada := EscortDirector.final_street_approach(esquina, via, normal)
static func final_street_approach(last_corner: Vector3, via: Vector3, outward: Vector3) -> Array[Vector3]:
	var crosswise := absf(outward.z) >= absf(outward.x)
	var door_axis := via.z if crosswise else via.x
	var street := _road_line_toward(door_axis, outward.z if crosswise else outward.x)
	var elbow := Vector3(last_corner.x, via.y, street) if crosswise else Vector3(street, via.y, last_corner.z)
	var entrance := Vector3(via.x, via.y, street) if crosswise else Vector3(street, via.y, via.z)
	var points: Array[Vector3] = []
	if elbow.distance_to(last_corner) > 0.01:
		points.append(elbow)
	if entrance.distance_to(elbow) > 0.01:
		points.append(entrance)
	return points


## Linha de rua mais proxima de um valor, do lado para onde `side` aponta (a
## rua de onde se chega na porta). Uso: interno de final_street_approach.
static func _road_line_toward(value: float, side: float) -> float:
	var best := ESCORT_ROUTE_SCRIPT.ROAD_LINES[0] as float
	var best_distance := INF
	for line in ESCORT_ROUTE_SCRIPT.ROAD_LINES:
		var offset := float(line) - value
		if side > 0.0 and offset < 0.0:
			continue
		if side < 0.0 and offset > 0.0:
			continue
		if absf(offset) < best_distance:
			best = float(line)
			best_distance = absf(offset)
	return best


## Porta DA RUA mais proxima da esquina, entre as do lote (raio a partir do
## centro dele). So porta externa entra: o predio procedural cria uma porta
## destrutivel para todo vao da planta, e a interna fica mais perto do centro do
## lote — sem o filtro a familia era mandada para dentro de um quarto (medido em
## 2026-09-28: 6 de 6 checkpoints pegaram porta interna).
## Uso: interno de _find_shelter_site.
func _nearest_shelter_door(tree: SceneTree, center: Vector3, radius: float, corner: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in tree.get_nodes_in_group("exterior_door"):
		var door := node as Node3D
		if door == null or not is_instance_valid(door):
			continue
		if Vector2(door.global_position.x - center.x, door.global_position.z - center.z).length() > radius:
			continue
		var to_corner := Vector2(door.global_position.x - corner.x, door.global_position.z - corner.z).length()
		if to_corner < best_distance:
			best = door
			best_distance = to_corner
	return best


## Geometria sintetica do checkpoint (fallback sem predio no lote): porta virada
## para a esquina, approach na frente e parada porta adentro.
func _shelter_geometry(lot_center: Vector2, corner: Vector3) -> Dictionary:
	var site := Vector3(lot_center.x, 0.0, lot_center.y)
	var to_corner := Vector3(corner.x - site.x, 0.0, corner.z - site.z)
	to_corner = to_corner.normalized() if to_corner.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	# Mesma convencao do player: a frente e o local -Z, entao este yaw aponta a
	# porta para a esquina.
	var facade := site + to_corner * (SHELTER_DEPTH * 0.5)
	var fallback := shelter_points(facade, to_corner, corner)
	fallback["position"] = site
	return fallback


## Abre a porta do predio do checkpoint quando um civil andando chega perto: a
## porta procedural so abre com E e o civil nao tem E. Uso: tick.
func _open_shelter_doors() -> void:
	for site in _shelter_sites:
		if site.is_empty():
			continue
		var door = site.get("door")
		if door == null or not is_instance_valid(door) or bool(door.get("is_destroyed")):
			continue
		for member in members:
			if not is_instance_valid(member) or member.is_eliminated or member.escaped or not member.walking:
				continue
			if member.global_position.distance_to(door.global_position) <= SHELTER_DOOR_OPEN_RADIUS:
				door.open_for(member)
				break


## Comprimento andavel da rota (soma dos trechos), usado para escolher o passo
## que faz a escolta durar ZIGZAG_TARGET_SECONDS. Uso: var metros := _route_length(rota)
func _route_length(route: Array[Vector3]) -> float:
	var total := 0.0
	for index in range(1, route.size()):
		total += route[index - 1].distance_to(route[index])
	return total


## Acrescenta o trecho picotado de ROUTE_STEP em ROUTE_STEP, preso ao mapa.
func _append_subdivided_leg(route: Array[Vector3], from: Vector3, to: Vector3) -> void:
	var steps := maxi(1, int(ceil(from.distance_to(to) / ROUTE_STEP)))
	for step in range(1, steps + 1):
		route.append(_clamp_to_map(from.lerp(to, float(step) / float(steps))))


func living_count() -> int:
	var living := 0
	for member in members:
		if is_instance_valid(member) and not member.is_eliminated and not member.escaped:
			living += 1
	return living


## A horda so pinga enquanto a familia anda: parada (antes do E ou no checkpoint)
## nenhum zumbi novo nasce. Uso: main._tick_escort antes de _tick_classic_spawns.
func allows_spawns() -> bool:
	# Depois do fim (vitoria/derrota) a horda para de nascer, senao o servidor
	# fica repondo ate o teto para sempre com a missao ja encerrada.
	if finished_victory or finished_defeat:
		return false
	return mission_started and not waiting_at_checkpoint


## Teto/intervalo/mix da horda para o trecho atual (cresce por checkpoint).
## Uso: var p := diretor.spawn_profile()
func spawn_profile() -> Dictionary:
	return SPAWN_PROFILE_SCRIPT.profile(next_checkpoint)


## Variante sorteada para um spawn, pelo mix da fase atual (deterministico).
## Uso: var tipo := diretor.pick_zombie_variant(indice_do_spawn)
func pick_zombie_variant(spawn_index: int) -> int:
	var roll := posmod(spawn_index * 37 + NetworkSession.world_seed * 13, 100)
	return SPAWN_PROFILE_SCRIPT.pick_variant(next_checkpoint, roll)


func hud_text() -> String:
	return status_text


## Estado completo para os clientes; main.gd roteia como o estado da onda.
## Uso: EscortDirector.state_for_network()
func state_for_network() -> Dictionary:
	var family_states: Array[Dictionary] = []
	for member in members:
		family_states.append({
			"name": String(member.name),
			"x": member.global_position.x,
			"y": member.global_position.y,
			"z": member.global_position.z,
			"health": member.health,
			"eliminated": member.is_eliminated,
			"escaped": member.escaped,
			"walking": member.walking,
			"scale": member.model_scale,
			"tint_r": member.tint.r,
			"tint_g": member.tint.g,
			"tint_b": member.tint.b,
		})
	return {
		"points": {"a_x": point_a.x, "a_z": point_a.z, "b_x": point_b.x, "b_z": point_b.z},
		"family": family_states,
		"merchants": merchant_spots,
		"status": status_text,
		"started": mission_started,
		"victory": finished_victory,
		"defeat": finished_defeat,
	}


## Procura membro pelo nome para o cliente acertar o fantasma certo.
## Uso: diretor.member_by_name("Familiar-Pai")
func member_by_name(member_name: String) -> EscortFamilyMember:
	for member in members:
		if is_instance_valid(member) and String(member.name) == member_name:
			return member
	return null


func _spawn_family(root: Node) -> void:
	if family_roles.is_empty():
		family_roles = _pick_roles(0)
	var member_index := 0
	for role in family_roles:
		var member := FAMILY_MEMBER_SCRIPT.new_civilian(root, String(role["name"]), role["shirt"], float(role["scale"]))
		member.global_position = point_a + _formation_position(member_index)
		member.formation_offset = FORMATION_OFFSETS[member_index % FORMATION_OFFSETS.size()]
		member.speed_factor = FORMATION_SPEEDS[member_index % FORMATION_SPEEDS.size()]
		member.walking = false
		member.targetable = false
		member.invulnerable = TEST_INVULNERABLE
		member.knocked_down.connect(_on_member_knocked_down)
		members.append(member)
		member_index += 1


## Posicao inicial da vaga na formacao (espalha o trio no ponto de partida).
func _formation_position(index: int) -> Vector3:
	var offset := FORMATION_OFFSETS[index % FORMATION_OFFSETS.size()]
	return Vector3(0.0, 0.0, offset)


func _on_member_knocked_down(member: EscortFamilyMember) -> void:
	print(JSON.stringify({"event": "escort_member_down", "member": String(member.name), "living": living_count()}))


## Varre os jogadores vivos: E apertado dentro do raio de algum familiar conta
## como pedido. Vale para iniciar a escolta E para liberar um checkpoint.
## Uso: dentro de tick; o pedido e consumido sempre (mesmo longe).
func _player_pressed_interact_near_family(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not is_instance_valid(player):
			continue
		if not player.has_method("consume_interact_request"):
			continue
		# Consome SEMPRE (mesmo longe): um E apertado longe da familia nao pode
		# ficar pendente e disparar a escolta quando alguem chegar depois.
		if not bool(player.call("consume_interact_request")):
			continue
		for member in members:
			if not is_instance_valid(member) or member.is_eliminated:
				continue
			if player.global_position.distance_to(member.global_position) <= START_INTERACT_RADIUS:
				return true
	return false


## Calcula os dois pontos da porta da safehouse: `_route_via` na frente dela
## (fora) e `point_b` porta adentro (o destino de verdade). Sem a casa na
## arvore, cai no centro do mapa.
func _pick_safehouse_door_points(tree: SceneTree, root: Node) -> void:
	var door := _find_safehouse_door(root)
	if door == null:
		_route_via = Vector3.ZERO
		_safehouse_outward = Vector3.ZERO
		point_b = _clamp_to_map(Vector3(0.0, 1.0, 0.0))
		return
	var outward := -door.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized()
	_safehouse_outward = outward
	var approach := door.global_position + outward * SAFEHOUSE_DOOR_CLEARANCE
	approach.y = 1.0
	_route_via = _closest_open_ground(tree, _clamp_to_map(approach))
	var interior := door.global_position - outward * SAFEHOUSE_ENTRY_DEPTH
	interior.y = 1.0
	point_b = _clamp_to_map(interior)


func _find_safehouse_door(root: Node) -> Node3D:
	var house := root.get_node_or_null("GeneratedCity/CentralSafehouse")
	if house == null:
		return null
	return house.get_node_or_null("SafehouseDoor") as Node3D


## Prende o ponto dentro do muro com folga, para a rota nunca furar o limite.
func _clamp_to_map(point: Vector3) -> Vector3:
	var limit := MAP_HALF_EXTENT - MAP_MARGIN
	point.x = clampf(point.x, -limit, limit)
	point.z = clampf(point.z, -limit, limit)
	return point


## Piso aberto mais perto do candidato: busca em anel (8 direcoes por volta).
func _closest_open_ground(tree: SceneTree, candidate: Vector3) -> Vector3:
	if _spawn_locator.is_open_ground(candidate, tree):
		return candidate
	for ring in range(1, GROUND_SEARCH_RINGS + 1):
		var radius := GROUND_SEARCH_STEP * float(ring)
		for step in 8:
			var angle := TAU * float(step) / 8.0
			var probe := candidate + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			probe = _clamp_to_map(probe)
			if _spawn_locator.is_open_ground(probe, tree):
				return probe
	return candidate


func _check_arrivals() -> void:
	for member in members:
		if not is_instance_valid(member) or member.is_eliminated or member.escaped:
			continue
		var planar := member.global_position - point_b
		if Vector2(planar.x, planar.z).length() <= ARRIVAL_RADIUS:
			member.escaped = true
			print(JSON.stringify({"event": "escort_member_escaped", "member": String(member.name)}))


func _check_group_status() -> void:
	# Vitoria ANTES da derrota: com o trio escapado, living_count() zera e
	# checar derrota primeiro marcaria a partida como perdida.
	if _all_escaped():
		finished_victory = true
		status_text = "VITORIA! A familia chegou a salvo."
		escort_finished.emit(true)
		return
	if _all_eliminated():
		finished_defeat = true
		status_text = "DERROTA! A familia inteira morreu."
		escort_finished.emit(false)
		return
	if waiting_at_checkpoint:
		# Nao sobrescreve o "aperte E": o texto do checkpoint fica na tela.
		return
	if _any_escaped():
		status_text = "%d de %d chegaram; leve o restante ate o ponto B." % [living_count(), FAMILY_SIZE]
	else:
		status_text = "Escolta: %d de %d vivos, rumo ao ponto B." % [living_count(), FAMILY_SIZE]


## Checkpoints: com a familia parada, so o E a libera; senao, quando todos os
## vivos chegam na esquina, a zona segura liga e ela para.
func _update_checkpoints(tree: SceneTree) -> void:
	if waiting_at_checkpoint:
		# --escort-hold (dev) segura cada checkpoint: o autostart inicia a missao
		# mas a familia espera o E, para inspecionar a parada + mercador.
		if _player_pressed_interact_near_family(tree) or (_autostart_enabled() and not _hold_enabled()):
			_release_checkpoint()
		return
	if next_checkpoint >= checkpoint_indices.size():
		return
	if _all_members_reached_halt():
		_activate_checkpoint(tree)


## Flag de dev: --escort-autostart (ver tick). Uso: interno de tick/checkpoints.
func _autostart_enabled() -> bool:
	return "--escort-autostart" in OS.get_cmdline_user_args()


## Dev (--escort-hold): espera o E mesmo com autostart ligado, para inspecionar
## as paradas. Uso: interno de _update_checkpoints.
func _hold_enabled() -> bool:
	return "--escort-hold" in OS.get_cmdline_user_args()


func _activate_checkpoint(tree: SceneTree) -> void:
	waiting_at_checkpoint = true
	for member in members:
		if is_instance_valid(member):
			member.walking = false
	var corner := checkpoint_corner_position()
	var inside_cleared := _clear_shelter_interior(next_checkpoint)
	var door_shut := _shut_shelter_door(next_checkpoint)
	status_text = "Checkpoint %d/%d: aperte E para a familia seguir." % [next_checkpoint + 1, checkpoint_indices.size()]
	print(JSON.stringify({
		"event": "escort_checkpoint",
		"index": next_checkpoint + 1,
		"of": checkpoint_indices.size(),
		"corner": [corner.x, corner.z],
		"zombies_within_25m": _zombies_within(corner, 25.0),
		"zombies_inside_cleared": inside_cleared,
		"door_shut": door_shut,
	}))


## Porta de verdade da parada de um checkpoint (o lote pode nao ter tido uma e
## a parada ter caido no fallback sintetico). Uso: interno.
func _shelter_door(checkpoint_index: int) -> Node3D:
	if checkpoint_index < 0 or checkpoint_index >= _shelter_sites.size():
		return null
	var door = _shelter_sites[checkpoint_index].get("door")
	if door == null or not is_instance_valid(door):
		return null
	return door as Node3D


## Fecha a porta com a familia toda dentro: enquanto ela espera o E o checkpoint
## e abrigo de verdade, e nao um vao aberto com a horda entrando atras (relato
## de 2026-09-28). Quem quiser entrar agora arromba ou abre no E.
## Devolve true se a porta ficou fechada. Uso: _activate_checkpoint.
func _shut_shelter_door(checkpoint_index: int) -> bool:
	var door := _shelter_door(checkpoint_index)
	if door == null or not door.has_method("close_for"):
		return false
	door.call("close_for")
	return not bool(door.get("is_open"))


## Reabre a porta na saida, pelo civil que vai passar (a folha gira para fora,
## para longe de quem esta dentro). Uso: _release_checkpoint, antes de andar.
func _open_shelter_door(checkpoint_index: int) -> void:
	var door := _shelter_door(checkpoint_index)
	if door == null or not door.has_method("open_for"):
		return
	door.call("open_for", _first_living_member())


## Primeiro familiar de pe, ou null. Uso: quem precisa de "alguem da familia".
func _first_living_member() -> EscortFamilyMember:
	for member in members:
		if is_instance_valid(member) and not member.is_eliminated and not member.escaped:
			return member
	return null


## Zumbi que entrou atras da familia enquanto a porta estava aberta e jogado de
## volta para a rua quando ela para. O predio procedural nao e uma caixa
## conhecida, entao usa um raio em volta do ponto de parada. Uso interno.
func _clear_shelter_interior(checkpoint_index: int) -> int:
	if checkpoint_index < 0 or checkpoint_index >= _shelter_sites.size():
		return 0
	var site: Dictionary = _shelter_sites[checkpoint_index]
	if site.is_empty():
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var center: Vector3 = site["inside"]
	var door_direction: Vector3 = site["door_direction"]
	var exit := center + door_direction * SHELTER_EVICT_DISTANCE
	var moved := 0
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or not is_instance_valid(zombie):
			continue
		var flat := Vector2(zombie.global_position.x - center.x, zombie.global_position.z - center.z)
		if flat.length() > SHELTER_INTERIOR_RADIUS:
			continue
		zombie.global_position = Vector3(exit.x, zombie.global_position.y, exit.z)
		moved += 1
	return moved


## Diagnostico: quantos zumbis estao num raio (prova de que eles rodeiam a casa
## e nao entram). Uso: interno de _activate_checkpoint/_debug_progress.
func _zombies_within(center: Vector3, radius: float) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var count := 0
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or not is_instance_valid(zombie):
			continue
		if zombie.global_position.distance_to(center) <= radius:
			count += 1
	return count


func _release_checkpoint() -> void:
	# Abre ANTES de mandar andar: civil empurrando folha fechada nao progride, o
	# vigia estoura em RESCUE_SECONDS e ele e teleportado.
	_open_shelter_door(next_checkpoint)
	next_checkpoint += 1
	var halt := checkpoint_indices[next_checkpoint] if next_checkpoint < checkpoint_indices.size() else -1
	for member in members:
		if not is_instance_valid(member) or member.is_eliminated or member.escaped:
			continue
		member.halt_route_index = halt
		member.walking = true
		# Prioridade e sair da casa: segura o tiro por um tempo para o civil
		# se afastar em vez de voltar pra dentro e atirar de la.
		member.hold_fire_seconds = EXIT_HOLD_FIRE_SECONDS
	waiting_at_checkpoint = false
	_rebuild_walking_text()


## Todos os vivos chegaram no waypoint do checkpoint (morto/escapado nao conta).
func _all_members_reached_halt() -> bool:
	var any_living := false
	for member in members:
		if not is_instance_valid(member) or member.is_eliminated or member.escaped:
			continue
		any_living = true
		if not member.has_reached_halt():
			return false
	return any_living


## Esquina da serpentina do checkpoint atual (onde a familia para).
func checkpoint_corner_position() -> Vector3:
	if checkpoint_indices.is_empty():
		return point_b
	var waypoint_index := checkpoint_indices[mini(next_checkpoint, checkpoint_indices.size() - 1)]
	for member in members:
		if is_instance_valid(member) and waypoint_index < member.route.size():
			return member.route[waypoint_index]
	return point_b


func _all_eliminated() -> bool:
	for member in members:
		if not is_instance_valid(member) or not member.is_eliminated:
			return false
	return true


func _all_escaped() -> bool:
	for member in members:
		if not is_instance_valid(member) or not member.escaped:
			return false
	return true


func _any_escaped() -> bool:
	for member in members:
		if is_instance_valid(member) and member.escaped:
			return true
	return false


func _rebuild_waiting_text() -> void:
	status_text = "A familia espera um grupo: chegue perto e aperte E para escoltar."


func _rebuild_walking_text() -> void:
	status_text = "Escolta: %d de %d vivos, rumo a safehouse." % [living_count(), FAMILY_SIZE]
