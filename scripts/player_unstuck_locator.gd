class_name PlayerUnstuckLocator
extends RefCounted

## Procura onde colocar um jogador preso: primeiro acima (de LIFT_STEPS em
## LIFT_STEPS), depois num anel ao redor. Um ponto serve quando a capsula do
## boneco nao encosta em nada do mundo estatico nesse lugar. Zumbis e outros
## jogadores sao ignorados: sair por cima de uma horda tambem vale.
## Uso:
##   var target := PlayerUnstuckLocator.find_free_position(player)
##   if target != PlayerUnstuckLocator.NO_FREE_POSITION: player.global_position = target

const NO_FREE_POSITION := Vector3.INF
const LIFT_STEPS: Array[float] = [1.5, 2.5, 3.5, 4.5]
const RING_DISTANCES: Array[float] = [1.5, 3.0]
const RING_DIRECTIONS := 8
const RING_LIFT := 0.3
# Camadas de personagens (jogadores = 2, zumbis = 4) nao bloqueiam o destino.
const CHARACTER_LAYERS := 2 | 4


## Primeiro ponto livre acima ou ao redor do jogador, ou NO_FREE_POSITION.
## Uso: var target := PlayerUnstuckLocator.find_free_position(player)
static func find_free_position(player: CharacterBody3D) -> Vector3:
	var origin := player.global_position
	for lift in LIFT_STEPS:
		var candidate := origin + Vector3.UP * lift
		if is_position_free(player, candidate):
			return candidate
	for distance in RING_DISTANCES:
		for step in RING_DIRECTIONS:
			var angle := TAU * float(step) / float(RING_DIRECTIONS)
			var candidate := origin + Vector3(cos(angle) * distance, RING_LIFT, sin(angle) * distance)
			if is_position_free(player, candidate):
				return candidate
	return NO_FREE_POSITION


## Verdadeiro quando a capsula do jogador, com a origem em `candidate`, nao
## sobrepoe nenhuma colisao do mundo.
## Uso: if PlayerUnstuckLocator.is_position_free(player, Vector3(0, 3, 0)): ...
static func is_position_free(player: CharacterBody3D, candidate: Vector3) -> bool:
	var shape_node := player.get_node_or_null("CollisionShape") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		push_error("Jogador '%s' sem CollisionShape; esperado no filho 'CollisionShape' com forma definida." % player.name)
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = Transform3D(Basis.IDENTITY, candidate + shape_node.position)
	query.collision_mask = player.collision_mask & ~CHARACTER_LAYERS
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
