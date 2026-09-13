class_name ZombieFlockCoordinator
extends Node

## Coordenador de enxame/horda inspirado na arquitetura de Days Gone.
## Agrupa zumbis em celulas espaciais, elege lideres (ponta de lanca),
## sincroniza alvos e aplica LOD de processamento sensorial e separacao suave.

const CELL_SIZE := 16.0
const LOD_NEAR_DIST_SQ := 484.0 # 22.0 * 22.0
const LOD_MID_DIST_SQ := 2500.0 # 50.0 * 50.0
const PLAYER_SCAN_INTERVAL := 0.25

static var instance: ZombieFlockCoordinator = null

var _spatial_cells: Dictionary = {}
var _cached_players: Array[CharacterBody3D] = []
var _player_scan_timer := 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	_update_cached_players(delta)
	_update_flock_clusters()


func _update_cached_players(delta: float) -> void:
	_player_scan_timer -= delta
	if _player_scan_timer > 0.0:
		return
	_player_scan_timer = PLAYER_SCAN_INTERVAL
	_cached_players.clear()
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as CharacterBody3D
		if p != null and not bool(p.get("is_eliminated")) and int(p.get("health")) > 0:
			_cached_players.append(p)


func _update_flock_clusters() -> void:
	_spatial_cells.clear()
	var zombie_nodes := get_tree().get_nodes_in_group("zombies")
	if zombie_nodes.is_empty():
		return

	# Agrupamento espacial em celulas de 16m
	for node in zombie_nodes:
		var z := node as CharacterBody3D
		if z == null or not is_instance_valid(z) or z.is_queued_for_deletion() or bool(z.get("is_dead")) or not bool(z.get("simulation_enabled")):
			continue
		var cell_x := int(floor(z.global_position.x / CELL_SIZE))
		var cell_z := int(floor(z.global_position.z / CELL_SIZE))
		var key := Vector2i(cell_x, cell_z)
		if not _spatial_cells.has(key):
			var list: Array[CharacterBody3D] = []
			_spatial_cells[key] = list
		var list_ref: Array[CharacterBody3D] = _spatial_cells[key]
		list_ref.append(z)

		# Atualizacao de LOD de distancia em relacao ao jogador mais proximo
		_apply_distance_lod(z)

	# Processa cada celula da horda (Lider vs Seguidores + Repulsao suave)
	for key in _spatial_cells:
		var cluster: Array[CharacterBody3D] = _spatial_cells[key]
		_process_cluster(cluster)


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

	if min_dist_sq <= LOD_NEAR_DIST_SQ:
		zombie.set("lod_level", 0) # NEAR
	elif min_dist_sq <= LOD_MID_DIST_SQ:
		zombie.set("lod_level", 1) # MID
	else:
		zombie.set("lod_level", 2) # FAR


func _process_cluster(cluster: Array[CharacterBody3D]) -> void:
	var valid_cluster: Array[CharacterBody3D] = []
	for z in cluster:
		if is_instance_valid(z) and not z.is_queued_for_deletion() and not bool(z.get("is_dead")):
			valid_cluster.append(z)
	if valid_cluster.is_empty():
		return

	var leader: CharacterBody3D = valid_cluster[0]
	leader.set("is_cluster_leader", true)

	var raw_target: Variant = leader.get("alert_target")
	var leader_target: CharacterBody3D = raw_target if (is_instance_valid(raw_target) and raw_target is CharacterBody3D) else null
	var has_alert: bool = leader_target != null
	var leader_forget: float = float(leader.get("alert_forget_timer"))
	var leader_sound: Vector3 = leader.get("sound_investigate_position") as Vector3
	var leader_sound_timer: float = float(leader.get("sound_investigate_timer"))
	var leader_is_sound: bool = bool(leader.get("is_investigating_sound"))
	var leader_wander_dir: Vector3 = leader.get("wander_direction") as Vector3
	var leader_wander_t: float = float(leader.get("wander_time"))

	for i in range(1, valid_cluster.size()):
		var follower: CharacterBody3D = valid_cluster[i]
		follower.set("is_cluster_leader", false)
		if has_alert and is_instance_valid(leader_target):
			follower.set("alert_target", leader_target)
			follower.set("alert_forget_timer", leader_forget)
		elif leader_is_sound and leader_sound_timer > 0.0:
			follower.set("sound_investigate_position", leader_sound)
			follower.set("sound_investigate_timer", leader_sound_timer)
			follower.set("is_investigating_sound", true)
		elif follower.get("alert_target") == null:
			follower.set("wander_direction", leader_wander_dir)
			follower.set("wander_time", leader_wander_t)

	_apply_boids_flocking(cluster)


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
		if z != null and not z.is_queued_for_deletion() and not bool(z.get("is_dead")):
			center_of_mass += z.global_position
			avg_velocity += z.velocity
			active_count += 1.0

	if active_count > 0.0:
		center_of_mass /= active_count
		avg_velocity /= active_count

	for a in cluster:
		if a == null or a.is_queued_for_deletion() or bool(a.get("is_dead")):
			continue

		var a_pos := a.global_position

		# 1. Separacao (Repulsao por distancia)
		var separation := Vector3.ZERO
		for b in cluster:
			if a == b or b == null or b.is_queued_for_deletion() or bool(b.get("is_dead")):
				continue
			var diff := a_pos - b.global_position
			diff.y = 0.0
			var dist_sq := diff.length_squared()
			if dist_sq > 0.0001 and dist_sq < 2.56: # Raio de 1.6m
				var dist := sqrt(dist_sq)
				separation += (diff / dist) * (1.6 - dist)

		# 2. Alinhamento (Igualar velocidade e fluxo com o bando)
		var alignment := (avg_velocity - a.velocity) * 0.2
		alignment.y = 0.0

		# 3. Coesao (Manter zumbis unidos ao enxame)
		var cohesion := (center_of_mass - a_pos) * 0.1
		cohesion.y = 0.0

		# Forca de bando resultante aplicada ao vetor de movimento
		var boids_force := separation * 1.6 + alignment * 0.4 + cohesion * 0.2
		a.set("flock_separation_vector", boids_force)


## Notifica em O(1) todos os zumbis da mesma celula espacial sobre um alvo detectado.
## Uso:
##   ZombieFlockCoordinator.instance.alert_cluster(zombie, player)
func alert_cluster(source_zombie: CharacterBody3D, target: CharacterBody3D) -> void:
	if source_zombie == null or target == null:
		return
	var cell_x := int(floor(source_zombie.global_position.x / CELL_SIZE))
	var cell_z := int(floor(source_zombie.global_position.z / CELL_SIZE))
	var key := Vector2i(cell_x, cell_z)
	if not _spatial_cells.has(key):
		return
	var cluster: Array[CharacterBody3D] = _spatial_cells[key]
	for z in cluster:
		if is_instance_valid(z) and not bool(z.get("is_dead")):
			z.set("alert_target", target)
			z.set("alert_forget_timer", 6.0)
