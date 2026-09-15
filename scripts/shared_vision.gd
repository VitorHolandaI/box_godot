class_name SharedVision
extends RefCounted

## Visao compartilhada entre aliados: um zumbi fica visivel para todos se
## QUALQUER jogador vivo da partida o enxerga (cone ou bolha de proximidade e
## linha de visao livre). Antes so os jogadores locais contavam, e o zumbi que
## o aliado online via continuava invisivel na sua tela.
## Uso:
##   var visible := SharedVision.is_seen_by_any(SharedVision.observers(tree), zombie, ja_visivel, precisa_ray, ray_check)

## Ray de oclusao de visao so dentro de 20m: alem disso o dissolve ja cobre
## e o estado anterior persiste (zumbi visto continua, oculto segue oculto).
const RAY_MAX_RANGE_SQ := 400.0


## Todos os jogadores validos da partida (locais e aliados de rede).
## Uso: var observadores := SharedVision.observers(get_tree())
static func observers(tree: SceneTree) -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for node in tree.get_nodes_in_group("player"):
		var player := node as CharacterBody3D
		if player != null and is_instance_valid(player) and not player.is_queued_for_deletion():
			result.append(player)
	return result


## Verdadeiro quando algum observador enxerga o zumbi. `has_clear_line` recebe
## (observador, zumbi) e so e chamado quando `needs_ray` e o observador esta perto.
## Uso: SharedVision.is_seen_by_any(players, zombie, false, true, _has_clear_player_vision)
static func is_seen_by_any(observer_list: Array[CharacterBody3D], zombie: Node3D, already_visible: bool, needs_ray: bool, has_clear_line: Callable) -> bool:
	for player in observer_list:
		if not is_instance_valid(player) or not player.can_see_position(zombie.global_position):
			continue
		if player.global_position.distance_squared_to(zombie.global_position) > RAY_MAX_RANGE_SQ:
			if already_visible:
				return true
			continue
		if not needs_ray or bool(has_clear_line.call(player, zombie)):
			return true
	return false
