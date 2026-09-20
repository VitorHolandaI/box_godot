class_name DoorStateReplicator
extends RefCounted

## Lado servidor da replicacao das portas dos predios. Antes o estado de todas
## as portas abertas/quebradas ia em cada snapshot nao confiavel de jogadores
## (1445 bytes, acima do MTU de 1392): pacote perdido fazia o cliente fechar a
## porta de novo, e ela parecia travada e indestrutivel. Agora vao so as
## mudancas (confiaveis) e um estado completo por jogador que entra.
## Uso:
##   replicator.watch(get_tree())
##   for peer_id in replicator.take_unsynced_peers(loaded_ids): send_full(peer_id)
##   var changes := replicator.take_changes()

var _pending_changes: Dictionary = {}
var _synced_peers: Dictionary = {}
var _scene: Node = null


## Passa a ouvir todas as portas ja presentes na cena atual.
## Uso: replicator.watch(get_tree())
func watch(tree: SceneTree) -> void:
	_scene = tree.current_scene
	for door in tree.get_nodes_in_group("destructible_door"):
		if not door.has_signal("network_state_changed"):
			continue
		if not door.is_connected("network_state_changed", _on_door_state_changed):
			door.connect("network_state_changed", _on_door_state_changed)


## Mudancas desde a ultima chamada, {caminho_na_cena: [aberta, quebrada, giro]}.
## Uso: var changes := replicator.take_changes()
func take_changes() -> Dictionary:
	var changes := _pending_changes
	_pending_changes = {}
	return changes


## Jogadores carregados que ainda nao receberam o estado completo; ja os marca
## como sincronizados. Quem saiu e esquecido para receber de novo ao voltar.
## Uso: var new_peers := replicator.take_unsynced_peers([2, 5])
func take_unsynced_peers(loaded_peer_ids: Array) -> Array[int]:
	var loaded: Dictionary = {}
	for peer_id in loaded_peer_ids:
		loaded[int(peer_id)] = true
	for peer_id in _synced_peers.keys():
		if not loaded.has(peer_id):
			_synced_peers.erase(peer_id)
	var unsynced: Array[int] = []
	for peer_id in loaded_peer_ids:
		if not _synced_peers.has(int(peer_id)):
			_synced_peers[int(peer_id)] = true
			unsynced.append(int(peer_id))
	return unsynced


func _on_door_state_changed(door: Node) -> void:
	if _scene == null or not is_instance_valid(door) or not _scene.is_ancestor_of(door):
		return
	_pending_changes[str(_scene.get_path_to(door))] = [bool(door.get("is_open")), bool(door.get("is_destroyed")), float(door.get("swing_direction"))]
