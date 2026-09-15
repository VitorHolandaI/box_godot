class_name DoorNetworkState
extends RefCounted


## Collects non-default door states using deterministic scene paths.
## Usage: var states := DoorNetworkState.collect(get_tree())
static func collect(tree: SceneTree) -> Dictionary:
	var states: Dictionary = {}
	var scene := tree.current_scene
	if scene == null:
		return states
	for door in tree.get_nodes_in_group("destructible_door"):
		if not is_instance_valid(door):
			continue
		var is_open := bool(door.get("is_open"))
		var is_destroyed := bool(door.get("is_destroyed"))
		if is_open or is_destroyed:
			states[str(scene.get_path_to(door))] = [is_open, is_destroyed]
	return states


## Applies the server snapshot and resets doors absent from it to closed.
## Usage: DoorNetworkState.apply(get_tree(), snapshot_states)
static func apply(tree: SceneTree, states: Dictionary) -> void:
	var scene := tree.current_scene
	if scene == null:
		return
	for door in tree.get_nodes_in_group("destructible_door"):
		if not is_instance_valid(door) or not door.has_method("apply_network_state"):
			continue
		var state: Variant = states.get(str(scene.get_path_to(door)), [false, false])
		if not state is Array or state.size() != 2:
			continue
		door.apply_network_state(bool(state[0]), bool(state[1]))


## Aplica mudancas pontuais recebidas do servidor; caminhos que nao existem
## neste cliente sao ignorados.
## Usage: DoorNetworkState.apply_changes(get_tree(), {"GeneratedCity/Lot_3/House_A/Door_h_75_0_1": [true, false]})
static func apply_changes(tree: SceneTree, changes: Dictionary) -> void:
	var scene := tree.current_scene
	if scene == null:
		return
	for path in changes:
		var state: Variant = changes[path]
		var door := scene.get_node_or_null(NodePath(str(path)))
		if door == null or not door.has_method("apply_network_state") or not state is Array or state.size() != 2:
			continue
		door.apply_network_state(bool(state[0]), bool(state[1]))
