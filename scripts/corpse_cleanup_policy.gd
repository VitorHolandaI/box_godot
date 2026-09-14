class_name CorpseCleanupPolicy
extends RefCounted

## Decide quais cadaveres podem sumir: so os que estao longe de todos os
## jogadores (fora da tela). Um teto de seguranca remove primeiro os mais
## distantes, nunca o corpo recem-caido ao lado do jogador.
## Uso:
##   var indices := CorpseCleanupPolicy.pick_removals(corpos, jogadores, 50.0, 60)

const KEEP_DISTANCE := 50.0
const HARD_CAP := 60


## Indices (em ordem decrescente) dos cadaveres a remover.
## Uso: for index in CorpseCleanupPolicy.pick_removals(corpse_positions, player_positions): ...
static func pick_removals(corpse_positions: Array[Vector3], player_positions: Array[Vector3], keep_distance: float = KEEP_DISTANCE, hard_cap: int = HARD_CAP) -> Array[int]:
	if keep_distance <= 0.0 or hard_cap < 0:
		push_error("Politica de cadaveres invalida: distancia=%.1f teto=%d; esperado distancia > 0 e teto >= 0." % [keep_distance, hard_cap])
		return []
	var removals: Array[int] = []
	var kept: Array[Dictionary] = []
	for index in corpse_positions.size():
		var distance := _nearest_player_distance(corpse_positions[index], player_positions)
		if distance > keep_distance:
			removals.append(index)
		else:
			kept.append({"index": index, "distance": distance})
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) > float(b["distance"]))
	var overflow := kept.size() - hard_cap
	for position in maxi(overflow, 0):
		removals.append(int(kept[position]["index"]))
	removals.sort()
	removals.reverse()
	return removals


static func _nearest_player_distance(point: Vector3, player_positions: Array[Vector3]) -> float:
	# Sem jogador (tela de espera) nada e considerado longe; so o teto age.
	if player_positions.is_empty():
		return 0.0
	var nearest := INF
	for player_position in player_positions:
		nearest = minf(nearest, point.distance_to(player_position))
	return nearest
