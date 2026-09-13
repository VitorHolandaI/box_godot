class_name ZombieSpawnLocator
extends RefCounted

const FOREST_INNER_RADIUS := 100.0
const FOREST_OUTER_RADIUS := 112.0
const MIN_PLAYER_DISTANCE := 45.0
const MIN_ZOMBIE_DISTANCE := 4.0
const INTERIOR_SPAWN_CHANCE := 0.3
const INVALID_SPAWN_POSITION := Vector3(0.0, -1000.0, 0.0)
const SURVIVAL_INNER_RADIUS := 18.0
const SURVIVAL_OUTER_RADIUS := 27.0
const SURVIVAL_MIN_PLAYER_DISTANCE := 8.0
const SURVIVAL_MIN_ZOMBIE_DISTANCE := 1.2

var random_source: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	random_source = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		random_source.randomize()


## Chooses an authorized interior or distant-forest zombie spawn.
## Usage: var position := locator.pick_spawn_position(get_tree())
func pick_spawn_position(tree: SceneTree) -> Vector3:
	if NetworkSession.survival_mode:
		return _pick_survival_position(tree)
	if random_source.randf() < INTERIOR_SPAWN_CHANCE:
		var interior_position: Variant = _pick_interior_position(tree)
		if interior_position != null:
			return interior_position as Vector3
	return _pick_forest_position(tree)


func _pick_survival_position(tree: SceneTree) -> Vector3:
	for _attempt in 48:
		var angle := random_source.randf_range(0.0, TAU)
		var radius := random_source.randf_range(SURVIVAL_INNER_RADIUS, SURVIVAL_OUTER_RADIUS)
		var candidate := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		if _is_survival_clear(candidate, tree):
			return candidate
	return INVALID_SPAWN_POSITION


func _is_survival_clear(candidate: Vector3, tree: SceneTree) -> bool:
	for player_node in tree.get_nodes_in_group("player"):
		var player := player_node as Node3D
		if player != null and candidate.distance_to(player.global_position) < SURVIVAL_MIN_PLAYER_DISTANCE:
			return false
	for zombie_node in tree.get_nodes_in_group("zombies"):
		var zombie := zombie_node as Node3D
		if zombie != null and candidate.distance_to(zombie.global_position) < SURVIVAL_MIN_ZOMBIE_DISTANCE:
			return false
	return true


func _pick_interior_position(tree: SceneTree) -> Variant:
	var markers := tree.get_nodes_in_group("zombie_interior_spawn")
	if markers.is_empty():
		return null
	var first_index := random_source.randi_range(0, markers.size() - 1)
	for offset in markers.size():
		var marker := markers[(first_index + offset) % markers.size()] as Marker3D
		if marker == null or not is_instance_valid(marker) or marker.is_queued_for_deletion():
			continue
		if _is_far_from_players(marker.global_position, tree) and _is_clear_of_zombies(marker.global_position, tree):
			return marker.global_position
	return null


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


func _is_far_from_players(candidate: Vector3, tree: SceneTree) -> bool:
	for player_node in tree.get_nodes_in_group("player"):
		var player := player_node as Node3D
		if player != null and candidate.distance_to(player.global_position) < MIN_PLAYER_DISTANCE:
			return false
	return true


func _is_clear_of_zombies(candidate: Vector3, tree: SceneTree) -> bool:
	for zombie_node in tree.get_nodes_in_group("zombies"):
		var zombie := zombie_node as Node3D
		if zombie != null and candidate.distance_to(zombie.global_position) < MIN_ZOMBIE_DISTANCE:
			return false
	return true
