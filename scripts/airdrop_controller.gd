class_name AirdropController
extends RefCounted

## Decide quando e onde cai o crate de armas: nas ondas-alvo da agenda,
## escolhe rua aberta a ~40m de um jogador local, evitando predios e
## zumbis. So roda onde a partida e autoritativa (local ou servidor).
## Uso:
##   var controller := AirdropController.new()
##   controller.setup(get_tree(), world_seed)
##   controller.airdrop_requested.connect(_launch_airdrop)

signal airdrop_requested(drop_position: Vector3, kinds: Array[int])

const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const MIN_PLAYER_DISTANCE := 6.0
const MIN_ZOMBIE_DISTANCE := 1.5
## Anel primario perto do jogador; tentativas seguintes alargam o raio para
## achar rua aberta mesmo com a horda inteira despejada em cima dele.
const MIN_DROP_RADIUS := 28.0
const MAX_DROP_RADIUS := 48.0
const ATTEMPTS_PER_RING := 32
const BUILDING_MARGIN := 1.0
const INVALID_DROP_POSITION := Vector3(0.0, -1000.0, 0.0)

var scene_tree: SceneTree
var world_seed: int
var schedule = SCHEDULE_SCRIPT.new()


func _init(tree: SceneTree = null, seed_value: int = 0) -> void:
	scene_tree = tree
	world_seed = seed_value


## Dispara o airdrop da onda, se ela for uma onda de crate.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func on_wave_started(wave_index: int) -> void:
	if scene_tree == null or not schedule.is_airdrop_wave(wave_index):
		return
	var drop_position := pick_drop_position(scene_tree)
	if drop_position == INVALID_DROP_POSITION:
		# Horda varreu o anel inteiro: avisa em vez de pular em silencio.
		push_warning("Airdrop da onda %d adiado: nenhum ponto de queda livre encontrado." % (wave_index + 1))
		return
	airdrop_requested.emit(drop_position, schedule.crate_kinds_for_wave(wave_index, world_seed))


## Ponto aberto perto de um jogador: rua livre de predios, longe de
## outros jogadores e de zumbis.
## Uso: var pos := controller.pick_drop_position(get_tree())
func pick_drop_position(tree: SceneTree) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 104729 + tree.get_frame_count()
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return INVALID_DROP_POSITION
	var origin_player := players[rng.randi() % players.size()] as Node3D
	if origin_player == null:
		return INVALID_DROP_POSITION
	for attempt in 96:
		var radius := rng.randf_range(MIN_DROP_RADIUS, MAX_DROP_RADIUS)
		if attempt >= ATTEMPTS_PER_RING * 2:
			radius = rng.randf_range(MAX_DROP_RADIUS * 2.5, MAX_DROP_RADIUS * 3.5)
		elif attempt >= ATTEMPTS_PER_RING:
			radius = rng.randf_range(MAX_DROP_RADIUS, MAX_DROP_RADIUS * 2.5)
		var angle := rng.randf_range(0.0, TAU)
		var candidate := origin_player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _is_drop_clear(candidate, tree):
			return Vector3(candidate.x, 0.02, candidate.z)
	return INVALID_DROP_POSITION


func _is_drop_clear(candidate: Vector3, tree: SceneTree) -> bool:
	for player_node in tree.get_nodes_in_group("player"):
		var player := player_node as Node3D
		if player != null and _distance_2d(candidate, player.global_position) < MIN_PLAYER_DISTANCE:
			return false
	for zombie_node in tree.get_nodes_in_group("zombies"):
		var zombie := zombie_node as Node3D
		if zombie != null and _distance_2d(candidate, zombie.global_position) < MIN_ZOMBIE_DISTANCE:
			return false
	return not _is_inside_building(candidate, tree)


## Distancia horizontal (XZ) entre dois pontos.
static func _distance_2d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Bloco visivel de predio: o crate nao deve cair dentro/na borda de casa.
static func _is_inside_building(candidate: Vector3, tree: SceneTree) -> bool:
	for building_node in tree.get_nodes_in_group("visibility_building"):
		var node := building_node as Node
		if node == null:
			continue
		var min_value: Variant = node.get_meta("visibility_min", null)
		var max_value: Variant = node.get_meta("visibility_max", null)
		if min_value is Vector3 and max_value is Vector3:
			var box_min := min_value as Vector3
			var box_max := max_value as Vector3
			if candidate.x >= box_min.x - BUILDING_MARGIN and candidate.x <= box_max.x + BUILDING_MARGIN \
					and candidate.z >= box_min.z - BUILDING_MARGIN and candidate.z <= box_max.z + BUILDING_MARGIN \
					and candidate.y >= box_min.y - BUILDING_MARGIN:
				return true
	return false
