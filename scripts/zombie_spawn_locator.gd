# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieSpawnLocator
extends RefCounted

const FOREST_INNER_RADIUS := 100.0
const FOREST_OUTER_RADIUS := 112.0
const MIN_PLAYER_DISTANCE := 45.0
const MIN_ZOMBIE_DISTANCE := 4.0
const INVALID_SPAWN_POSITION := Vector3(0.0, -1000.0, 0.0)
const NAVIGATION_SCRIPT: GDScript = preload("res://scripts/procedural/navigation/building_navigation.gd")
const SPAWN_CLEARANCE_RADIUS := 0.7
const STATIC_WORLD_MASK := 1
## Emboscada em casa: predios entram nesse grupo (city_assembler.gd).
const BUILDING_GROUP := "visibility_building"
const INDOOR_SAMPLE_RADIUS := 9.0
const INDOOR_ATTEMPTS := 24
## Dentro de casa o zumbi pode nascer mais perto do player que no anel (18 m em
## vez de 45): e emboscada, mas ainda longe de aparecer na cara dele.
const MIN_INDOOR_PLAYER_DISTANCE := 18.0

var random_source: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	random_source = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		random_source.randomize()


## Chooses a distant-forest zombie spawn, always among the trees so zombies
## must path out toward the players instead of being trapped inside houses.
## Sobrevivencia e classico usam o mesmo anel: spawn fora dos muros, longe
## do player (>= 45 m), e a horda entra correndo da floresta aos poucos.
## Usage: var position := locator.pick_spawn_position(get_tree())
func pick_spawn_position(tree: SceneTree, prefer_indoor: bool = false) -> Vector3:
	if prefer_indoor:
		var indoor := _pick_indoor_position(tree)
		if indoor != INVALID_SPAWN_POSITION:
			return indoor
	# Sem ponto interno util, cai no anel de sempre: nunca fica sem spawn.
	return _pick_forest_position(tree)


## Variantes de emboscada: nascem dentro de predio quando ha ponto, para
## surpreender quem entra - puxador de longe e espreitador invisivel.
## Uso: if ZombieSpawnLocator.prefers_indoor(tipo): var p := locator.pick_spawn_position(tree, true)
static func prefers_indoor(zombie_type: int) -> bool:
	return zombie_type == ZombieMutator.Type.SMOKER or zombie_type == ZombieMutator.Type.STALKER


## O contrario do is_open_ground: piso INTERNO (o navmesh do predio cobre o
## interior) e sem corpo dentro de parede. Uso: locator.is_indoor_ground(pos, get_tree())
func is_indoor_ground(candidate: Vector3, tree: SceneTree) -> bool:
	if NAVIGATION_SCRIPT.find_for_position(tree, candidate) == null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = SPAWN_CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, candidate)
	query.collision_mask = STATIC_WORLD_MASK
	return tree.root.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Sorteia predios e tenta pontos no piso interno deles. INVALID quando nenhum
## serve (chamador cai no spawn de fora dos muros).
func _pick_indoor_position(tree: SceneTree) -> Vector3:
	var buildings := tree.get_nodes_in_group(BUILDING_GROUP)
	if buildings.is_empty():
		return INVALID_SPAWN_POSITION
	for _attempt in INDOOR_ATTEMPTS:
		var building_value: Variant = buildings[random_source.randi() % buildings.size()]
		var building := building_value as Node3D
		if building == null:
			continue
		var offset := Vector3(
			random_source.randf_range(-INDOOR_SAMPLE_RADIUS, INDOOR_SAMPLE_RADIUS),
			1.0,
			random_source.randf_range(-INDOOR_SAMPLE_RADIUS, INDOOR_SAMPLE_RADIUS)
		)
		var candidate := building.global_position + offset
		if not _is_far_from_players(candidate, tree, MIN_INDOOR_PLAYER_DISTANCE):
			continue
		if not _is_clear_of_zombies(candidate, tree):
			continue
		if is_indoor_ground(candidate, tree):
			return candidate
	return INVALID_SPAWN_POSITION


func _pick_forest_position(tree: SceneTree) -> Vector3:
	for _attempt in 24:
		var angle := random_source.randf_range(0.0, TAU)
		var radius := random_source.randf_range(FOREST_INNER_RADIUS, FOREST_OUTER_RADIUS)
		var candidate := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		if _is_far_from_players(candidate, tree) and _is_clear_of_zombies(candidate, tree):
			return candidate

	# Random attempts can miss a valid point, but the final choice must still
	# honor the same player and zombie clearance rules.
	for radius_step in 6:
		var radius := lerpf(FOREST_INNER_RADIUS, FOREST_OUTER_RADIUS, float(radius_step) / 5.0)
		for angle_step in 72:
			var angle := TAU * float(angle_step) / 72.0
			var candidate := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
			if _is_far_from_players(candidate, tree) and _is_clear_of_zombies(candidate, tree):
				return candidate
	return INVALID_SPAWN_POSITION


## Ponto na rua: fora do volume de qualquer predio com navmesh (inclusive a
## margem da calcada) e sem colisao estatica no raio do corpo. O anel de spawn
## da sobrevivencia cruza lotes, e zumbis nasciam dentro de paredes e casas.
## Uso: if locator.is_open_ground(Vector3(20.0, 1.0, 5.0), get_tree()): spawn()
func is_open_ground(candidate: Vector3, tree: SceneTree) -> bool:
	if NAVIGATION_SCRIPT.find_for_position(tree, candidate) != null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = SPAWN_CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, candidate)
	query.collision_mask = STATIC_WORLD_MASK
	return tree.root.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _is_far_from_players(candidate: Vector3, tree: SceneTree, min_distance: float = MIN_PLAYER_DISTANCE) -> bool:
	for player_node in tree.get_nodes_in_group("player"):
		var player := player_node as Node3D
		if player != null and candidate.distance_to(player.global_position) < min_distance:
			return false
	return true


func _is_clear_of_zombies(candidate: Vector3, tree: SceneTree) -> bool:
	for zombie_node in tree.get_nodes_in_group("zombies"):
		var zombie := zombie_node as Node3D
		if zombie != null and candidate.distance_to(zombie.global_position) < MIN_ZOMBIE_DISTANCE:
			return false
	return true
