# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieFlockCoordinator
extends Node

## Coordenador de enxame/horda inspirado na arquitetura de Days Gone.
## Agrupa celulas vizinhas em hordas persistentes, mantem um unico cerebro,
## sincroniza os drones e aplica LOD e separacao suave.

const CELL_SIZE := 16.0
const SEPARATION_CELL_SIZE := 2.0
const MAX_SEPARATION_NEIGHBORS := 24
const HORDE_LINK_RADIUS_SQ := 12.0 * 12.0
const LOD_NEAR_DIST_SQ := 484.0 # 22.0 * 22.0
const LOD_MID_DIST_SQ := 2500.0 # 50.0 * 50.0
const PLAYER_SCAN_INTERVAL := 0.25
const FLOCK_UPDATE_INTERVAL := 0.2
const CHASE_HEARTBEAT_INTERVAL := 10.0
const FLOCK_ENABLED := true
## Hordas prontas sao aplicadas aos poucos: no maximo ~N zumbis por tick (uma
## horda inteira nunca e partida). Antes a passada inteira caia num frame so e
## deu pico de 24 ms na VPS com 200 zumbis.
const FLOCK_ZOMBIES_PER_TICK := 80
## Duas celulas de 16 m ligam se algum par esta perto; amontoadas, comparar
## todos contra todos era 200x200. Amostra no maximo N membros de cada lado.
const LINK_SAMPLE_PER_CELL := 12

static var instance: ZombieFlockCoordinator = null
## Diagnostico de zumbis travados (`-- --debug-stuck-zombies`), lido tambem por zombie.gd.
static var debug_stuck_zombies := "--debug-stuck-zombies" in OS.get_cmdline_user_args()

var _spatial_cells: Dictionary = {}
var _cached_players: Array[CharacterBody3D] = []
var _player_scan_timer := 0.0
var _flock_update_elapsed := 0.0
var _horde_members: Dictionary = {}
var _next_horde_id := 1
var _random_source := RandomNumberGenerator.new()
var _chase_heartbeat_elapsed := 0.0
## Lideres de cluster da ultima passada do enxame (0.2s); canal do som.
var _leader_cache: Array[CharacterBody3D] = []
var _pending_hordes: Array = []
## G7-fase1: luzes de interior so nos predios com alguem perto (~2 Hz).
const LIGHT_TOGGLE_INTERVAL := 0.5
const LIGHT_MARGIN := 10.0
const LIGHT_OFF_TICKS := 2

var _light_toggle_elapsed := 0.0
var _light_off_ticks: Dictionary = {}


## Som no mapa (tiro, grito de screamer) chega apenas aos lideres de cluster:
## cada um investiga e o cerebro da horda passa o alvo para os seguidores,
## em vez de 600 zumbis rodando hear_gunshot por call_group.
## Uso: coordinator.notify_sound(origem_tiro, 65.0)
func notify_sound(origin: Vector3, radius: float) -> void:
	for leader in _leader_cache:
		if is_instance_valid(leader) and not bool(leader.get("is_dead")):
			leader.call("hear_gunshot", origin, radius)


## G7-fase1 (cosmetico/local): predio com jogador (de qualquer peer) perto do
## volume com margem = luz ON; vazio por 2 ticks seguidos = OFF. Cada tela
## decide pela sua propria renderizacao; safehouse nunca apaga. Headless
## dedicado pula tudo. Reduz de ~100-200 para <20 OmniLights ativas.
## Uso: roda sozinho via _physics_process a cada LIGHT_TOGGLE_INTERVAL.
func _update_building_lights(delta: float) -> void:
	if NetworkSession.is_server():
		return
	_light_toggle_elapsed += delta
	if _light_toggle_elapsed < LIGHT_TOGGLE_INTERVAL:
		return
	_light_toggle_elapsed = 0.0
	# get_living_players poda o cache: um peer que desconectou deixa o Node
	# liberado em _cached_players, e o cast dele estourava com 8 peers.
	var relevant_players: Array = get_living_players(get_tree())
	for building_value in get_tree().get_nodes_in_group("visibility_building"):
		var building := building_value as Node
		if building == null or String(building.name).begins_with("CentralSafehouse"):
			continue
		var bounds: Variant = _building_visibility_bounds(building)
		if bounds == null:
			continue
		var key := String(building.get_path())
		if _any_player_in_bounds(relevant_players, bounds as AABB):
			_light_off_ticks.erase(key)
			ProceduralBuildingAssembler.set_building_lights_enabled(building, true)
			continue
		var off_ticks := int(_light_off_ticks.get(key, 0)) + 1
		_light_off_ticks[key] = off_ticks
		if off_ticks >= LIGHT_OFF_TICKS:
			ProceduralBuildingAssembler.set_building_lights_enabled(building, false)


## AABB do volume de visibilidade do predio com a margem de luz, ou null se o
## predio nao tem meta de visibilidade. Uso: var b := _building_visibility_bounds(predio)
func _building_visibility_bounds(building: Node) -> Variant:
	var min_value: Variant = building.get_meta("visibility_min", null)
	var max_value: Variant = building.get_meta("visibility_max", null)
	if not (min_value is Vector3 and max_value is Vector3):
		return null
	var margin := Vector3.ONE * LIGHT_MARGIN
	var bounds_min := (min_value as Vector3) - margin
	return AABB(bounds_min, (max_value as Vector3) + margin - bounds_min)


## Algum jogador vivo dentro do volume? Uso: if _any_player_in_bounds(players, aabb)
func _any_player_in_bounds(players: Array, bounds: AABB) -> bool:
	for player in players:
		if not is_instance_valid(player):
			continue
		var player_node := player as Node3D
		if player_node != null and bounds.has_point(player_node.global_position):
			return true
	return false


## Canal estatico de som: usa o coordenador quando existe (mundo real) e cai
## no caminho antigo em testes/mundos sem enxame.
## Uso: ZombieFlockCoordinator.relay_sound(get_tree(), origem, raio)
static func relay_sound(tree: SceneTree, origin: Vector3, radius: float) -> void:
	if instance == null:
		tree.call_group("zombies", "hear_gunshot", origin, radius)
		return
	instance.notify_sound(origin, radius)


## Lista de jogadores vivos em cache (0.25s): evita que cada zumbi refaca o
## scan do grupo por melee/sentidos. Uso: ZombieFlockCoordinator.get_living_players(tree)
static func get_living_players(tree: SceneTree) -> Array:
	if instance != null and not instance._cached_players.is_empty():
		# Podem ter sido liberados (peer desconectou) desde a ultima passada:
		# prune antes de servir, senao o cast de objeto liberado estoura.
		var pruned: Array[CharacterBody3D] = []
		for player in instance._cached_players:
			if is_instance_valid(player) and not player.is_queued_for_deletion():
				pruned.append(player)
		instance._cached_players = pruned
		return pruned
	var players: Array = []
	for node in tree.get_nodes_in_group("player"):
		var player := node as CharacterBody3D
		if player != null and is_instance_valid(player) and not bool(player.get("is_eliminated")) and int(player.get("health")) > 0:
			players.append(player)
	return players


func _enter_tree() -> void:
	instance = self
	_random_source.randomize()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	_update_building_lights(delta)
	if not FLOCK_ENABLED:
		return
	_flock_update_elapsed += delta
	var perf_start := FramePerfProbe.begin()
	if _pending_hordes.is_empty() and _flock_update_elapsed >= FLOCK_UPDATE_INTERVAL:
		var update_delta := _flock_update_elapsed
		_flock_update_elapsed = 0.0
		_update_cached_players(update_delta)
		_update_flock_clusters()
		_log_chase_heartbeat(update_delta)
	_drain_pending_hordes()
	FramePerfProbe.end("flock", perf_start)


## Aplica lideranca e boids das hordas enfileiradas ate o limite do tick.
## Uso: chamado em _physics_process; testes chamam _physics_process(0.2).
func _drain_pending_hordes() -> void:
	var processed := 0
	while not _pending_hordes.is_empty():
		var next_size := (_pending_hordes.back() as Array).size()
		# A primeira horda do tick sempre roda, mesmo maior que o teto.
		if processed > 0 and processed + next_size > FLOCK_ZOMBIES_PER_TICK:
			return
		var horde: Array[CharacterBody3D] = _pending_hordes.pop_back()
		processed += horde.size()
		_process_cluster(horde)


## Diagnostico com --debug-stuck-zombies: prova que houve perseguicao quando o
## log de zumbis travados sai vazio (sem alvo vivo, nenhum zumbi e medido).
func _log_chase_heartbeat(delta: float) -> void:
	if not debug_stuck_zombies or NetworkSession.is_client():
		return
	_chase_heartbeat_elapsed += delta
	if _chase_heartbeat_elapsed < CHASE_HEARTBEAT_INTERVAL:
		return
	_chase_heartbeat_elapsed = 0.0
	var alive := 0
	var chasing := 0
	var most_stalled := 0.0
	for node in get_tree().get_nodes_in_group("zombies"):
		if bool(node.get("is_dead")):
			continue
		alive += 1
		if is_instance_valid(node.get("alert_target")):
			chasing += 1
			most_stalled = maxf(most_stalled, float(node.get("progress_watch").no_progress_seconds))
	print(JSON.stringify({"event": "zombie_chase_heartbeat", "alive": alive, "chasing": chasing, "players_alive": _cached_players.size(), "max_no_progress_seconds": most_stalled}))


func _update_cached_players(delta: float) -> void:
	_player_scan_timer -= delta
	if _player_scan_timer > 0.0:
		return
	_player_scan_timer = PLAYER_SCAN_INTERVAL
	_cached_players.clear()
	for node in get_tree().get_nodes_in_group("player"):
		# Validade ANTES do cast: um no liberado no meio do frame quebra o as.
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var p := node as CharacterBody3D
		if p != null and not bool(p.get("is_eliminated")) and int(p.get("health")) > 0:
			_cached_players.append(p)


func _update_flock_clusters() -> void:
	_spatial_cells.clear()
	var zombie_nodes := get_tree().get_nodes_in_group("zombies")
	if zombie_nodes.is_empty():
		return

	# Lideres validos desta passada: o relay de som (tiro/grito) so acorda
	# eles em vez de 600 zumbis por call_group.
	_leader_cache.clear()
	for node in zombie_nodes:
		var z := node as CharacterBody3D
		if z == null or not is_instance_valid(z) or z.is_queued_for_deletion() or bool(z.get("is_dead")):
			continue
		if bool(z.get("is_cluster_leader")):
			_leader_cache.append(z)

	# Agrupamento espacial em celulas de 16m
	for node in zombie_nodes:
		var z := node as CharacterBody3D
		if z == null or not is_instance_valid(z) or z.is_queued_for_deletion() or bool(z.get("is_dead")):
			continue
		# Client proxies still need visual LOD even though they do not run AI or Boids.
		_apply_distance_lod(z)
		if not bool(z.get("simulation_enabled")):
			continue
		var cell_x := int(floor(z.global_position.x / CELL_SIZE))
		var cell_z := int(floor(z.global_position.z / CELL_SIZE))
		var key := Vector2i(cell_x, cell_z)
		if not _spatial_cells.has(key):
			var list: Array[CharacterBody3D] = []
			_spatial_cells[key] = list
		var list_ref: Array[CharacterBody3D] = _spatial_cells[key]
		list_ref.append(z)

	_horde_members.clear()
	_process_connected_hordes()


func _process_connected_hordes() -> void:
	var visited_cells: Dictionary = {}
	for key_value in _spatial_cells:
		var start_cell: Vector2i = key_value
		if visited_cells.has(start_cell):
			continue
		var pending_cells: Array[Vector2i] = [start_cell]
		var horde: Array[CharacterBody3D] = []
		while not pending_cells.is_empty():
			var current_cell: Vector2i = pending_cells.pop_back()
			if visited_cells.has(current_cell):
				continue
			visited_cells[current_cell] = true
			var cell_members: Array[CharacterBody3D] = _spatial_cells[current_cell]
			horde.append_array(cell_members)
			for offset_x in range(-1, 2):
				for offset_z in range(-1, 2):
					var neighbor := current_cell + Vector2i(offset_x, offset_z)
					if visited_cells.has(neighbor) or not _spatial_cells.has(neighbor):
						continue
					if _cells_are_linked(current_cell, neighbor):
						pending_cells.append(neighbor)
		_pending_hordes.append(horde)


func _cells_are_linked(first_cell: Vector2i, second_cell: Vector2i) -> bool:
	var first_members: Array[CharacterBody3D] = _spatial_cells[first_cell]
	var second_members: Array[CharacterBody3D] = _spatial_cells[second_cell]
	var first_stride := maxi(floori(float(first_members.size()) / LINK_SAMPLE_PER_CELL), 1)
	var second_stride := maxi(floori(float(second_members.size()) / LINK_SAMPLE_PER_CELL), 1)
	for first_index in range(0, first_members.size(), first_stride):
		var first = first_members[first_index]
		if not is_instance_valid(first) or bool(first.get("is_dead")):
			continue
		for second_index in range(0, second_members.size(), second_stride):
			var second = second_members[second_index]
			if not is_instance_valid(second) or bool(second.get("is_dead")):
				continue
			if first.global_position.distance_squared_to(second.global_position) <= HORDE_LINK_RADIUS_SQ:
				return true
	return false


func _apply_distance_lod(zombie: CharacterBody3D) -> void:
	if not is_instance_valid(zombie) or zombie.is_queued_for_deletion():
		return
	if _cached_players.is_empty():
		zombie.set("lod_level", 2) # FAR
		return
	var min_dist_sq := 1e9
	var pos := zombie.global_position
	for p in _cached_players:
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		var d_sq := pos.distance_squared_to(p.global_position)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq

	zombie.set("player_distance_sq", min_dist_sq)
	if min_dist_sq <= LOD_NEAR_DIST_SQ:
		zombie.set("lod_level", 0) # NEAR
	elif min_dist_sq <= LOD_MID_DIST_SQ:
		zombie.set("lod_level", 1) # MID
	else:
		zombie.set("lod_level", 2) # FAR


func _process_cluster(cluster: Array[CharacterBody3D]) -> void:
	var valid_cluster: Array[CharacterBody3D] = []
	for z in cluster:
		if is_instance_valid(z) and _is_active(z):
			valid_cluster.append(z)
	if valid_cluster.is_empty():
		return

	var leader := _elect_leader(valid_cluster)
	_stamp_horde(valid_cluster, leader)
	_share_leader_intent(valid_cluster, leader)
	_apply_boids_flocking(valid_cluster)


## Lider do grupo: sorteia entre os lideres que ja existiam (a horda mantem o
## dono e o id entre frames) e, sem nenhum, entre os membros.
## Uso: var leader := _elect_leader(valid_cluster)
func _elect_leader(valid_cluster: Array[CharacterBody3D]) -> CharacterBody3D:
	var previous_leaders: Array[CharacterBody3D] = []
	for zombie in valid_cluster:
		if bool(zombie.get("is_cluster_leader")) and int(zombie.get("horde_id")) > 0:
			previous_leaders.append(zombie)
	if previous_leaders.is_empty():
		return valid_cluster[_random_source.randi_range(0, valid_cluster.size() - 1)]
	return previous_leaders[_random_source.randi_range(0, previous_leaders.size() - 1)]


## Carimba o id da horda e quem e o lider em todos os membros do grupo.
## Uso: _stamp_horde(valid_cluster, leader)
func _stamp_horde(valid_cluster: Array[CharacterBody3D], leader: CharacterBody3D) -> void:
	var assigned_horde_id := int(leader.get("horde_id"))
	if assigned_horde_id <= 0:
		assigned_horde_id = _next_horde_id
		_next_horde_id += 1
	for zombie in valid_cluster:
		zombie.set("horde_id", assigned_horde_id)
		zombie.set("is_cluster_leader", zombie == leader)
	_horde_members[assigned_horde_id] = valid_cluster


## Os seguidores copiam a intencao do lider: o alvo dele, o barulho que ele
## ouviu ou, sem nada disso, a direcao de vagar. E o que faz a horda andar
## junta em vez de cada zumbi decidir sozinho.
## Uso: _share_leader_intent(valid_cluster, leader)
func _share_leader_intent(valid_cluster: Array[CharacterBody3D], leader: CharacterBody3D) -> void:
	var raw_target: Variant = leader.get("alert_target")
	var leader_target: CharacterBody3D = raw_target if (is_instance_valid(raw_target) and raw_target is CharacterBody3D) else null
	var leader_sound_timer: float = float(leader.get("sound_investigate_timer"))
	var chases: bool = leader_target != null
	var investigates: bool = bool(leader.get("is_investigating_sound")) and leader_sound_timer > 0.0
	for follower in valid_cluster:
		if follower == leader:
			continue
		if chases:
			follower.set("alert_target", leader_target)
			follower.set("alert_forget_timer", float(leader.get("alert_forget_timer")))
			continue
		if investigates:
			follower.set("sound_investigate_position", leader.get("sound_investigate_position"))
			follower.set("sound_investigate_timer", leader_sound_timer)
			follower.set("is_investigating_sound", true)
			continue
		follower.set("alert_target", null)
		follower.set("alert_forget_timer", 0.0)
		follower.set("is_investigating_sound", false)
		follower.set("wander_direction", leader.get("wander_direction"))
		follower.set("wander_time", float(leader.get("wander_time")))


## Aplica os tres principios classicos de Boids de Craig Reynolds:
## 1. Separacao: evita sobreposicao de corpos entre vizinhos.
## 2. Alinhamento: unifica o vetor de velocidade e fluxo da horda.
## 3. Coesao: atrai os membros suavemente em direcao ao centro de massa da celula.
func _apply_boids_flocking(cluster: Array[CharacterBody3D]) -> void:
	if cluster.size() <= 1:
		cluster[0].set("flock_separation_vector", Vector3.ZERO)
		return

	var center_of_mass := Vector3.ZERO
	var avg_velocity := Vector3.ZERO
	var active_count := 0.0

	for z in cluster:
		if _is_active(z):
			center_of_mass += z.global_position
			avg_velocity += z.velocity
			active_count += 1.0

	if active_count > 0.0:
		center_of_mass /= active_count
		avg_velocity /= active_count

	var separation_cells: Dictionary = {}
	for z in cluster:
		if not _is_active(z):
			continue
		var separation_key := _get_separation_cell(z.global_position)
		if not separation_cells.has(separation_key):
			var members: Array[CharacterBody3D] = []
			separation_cells[separation_key] = members
		var members_ref: Array[CharacterBody3D] = separation_cells[separation_key]
		members_ref.append(z)

	for a in cluster:
		if not _is_active(a):
			continue
		var a_pos := a.global_position
		# 1. Separacao (repulsao por distancia, so nas celulas vizinhas)
		var separation := _separation_force(a, a_pos, separation_cells)
		# 2. Alinhamento (igualar velocidade e fluxo com o bando)
		var alignment := (avg_velocity - a.velocity) * 0.2
		alignment.y = 0.0
		# 3. Coesao (manter zumbis unidos ao enxame)
		var cohesion := (center_of_mass - a_pos) * 0.1
		cohesion.y = 0.0
		# Forca de bando resultante aplicada ao vetor de movimento
		a.set("flock_separation_vector", separation * 1.6 + alignment * 0.4 + cohesion * 0.2)


## Repulsao de um zumbi pelos vizinhos das 9 celulas em volta, com teto de
## MAX_SEPARATION_NEIGHBORS vizinhos: na horda amontoada o custo e quadratico
## sem esse teto. Uso: var separation := _separation_force(zumbi, pos, celulas)
func _separation_force(zombie: CharacterBody3D, position: Vector3, separation_cells: Dictionary) -> Vector3:
	var separation := Vector3.ZERO
	var neighbor_count := 0
	var separation_cell := _get_separation_cell(position)
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			var neighbors: Variant = separation_cells.get(separation_cell + Vector2i(offset_x, offset_z))
			if neighbors == null:
				continue
			for b in neighbors as Array[CharacterBody3D]:
				if zombie == b or not _is_active(b):
					continue
				var diff := position - b.global_position
				diff.y = 0.0
				var dist_sq := diff.length_squared()
				if dist_sq > 0.0001 and dist_sq < 2.56: # Raio de 1.6m
					var dist := sqrt(dist_sq)
					separation += (diff / dist) * (1.6 - dist)
				neighbor_count += 1
				if neighbor_count >= MAX_SEPARATION_NEIGHBORS:
					return separation
	return separation


## Zumbi que ainda conta para o bando: vivo, valido e nao marcado para sumir.
## Uso: if not _is_active(zombie): continue
func _is_active(zombie: CharacterBody3D) -> bool:
	return zombie != null and not zombie.is_queued_for_deletion() and not bool(zombie.get("is_dead"))


func _get_separation_cell(position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(position.x / SEPARATION_CELL_SIZE)),
		int(floor(position.z / SEPARATION_CELL_SIZE))
	)


## Notifica todos os drones da horda persistente sobre um alvo detectado.
## Uso:
##   ZombieFlockCoordinator.instance.alert_cluster(zombie, player)
func alert_cluster(source_zombie: CharacterBody3D, target: CharacterBody3D) -> void:
	if source_zombie == null or target == null:
		return
	var source_horde_id := int(source_zombie.get("horde_id"))
	if not _horde_members.has(source_horde_id):
		return
	var cluster: Array[CharacterBody3D] = _horde_members[source_horde_id]
	for z in cluster:
		if is_instance_valid(z) and not bool(z.get("is_dead")):
			z.set("alert_target", target)
			z.set("alert_forget_timer", 6.0)
