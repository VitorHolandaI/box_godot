class_name SharedVision
extends RefCounted

## Visao compartilhada entre aliados: um zumbi fica visivel para todos se esta
## no raio de visao (PlayerCharacter.VIEW_RADIUS) de QUALQUER jogador vivo da
## partida. Sem cone e sem raio de oclusao: so distancia, para centenas de
## zumbis nao custarem FPS.
## Uso:
##   var visible := SharedVision.is_seen_by_any(SharedVision.observers(tree), zombie)


## Todos os jogadores validos da partida (locais e aliados de rede).
## Uso: var observadores := SharedVision.observers(get_tree())
static func observers(tree: SceneTree) -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	for node in tree.get_nodes_in_group("player"):
		var player := node as CharacterBody3D
		if player != null and is_instance_valid(player) and not player.is_queued_for_deletion():
			result.append(player)
	return result


## Verdadeiro quando o zumbi esta no raio de visao de algum observador.
## Uso: SharedVision.is_seen_by_any(players, zombie)
static func is_seen_by_any(observer_list: Array[CharacterBody3D], zombie: Node3D) -> bool:
	for player in observer_list:
		if is_instance_valid(player) and player.can_see_position(zombie.global_position):
			return true
	return false
