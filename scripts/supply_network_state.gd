class_name SupplyNetworkState
extends RefCounted


## Coleta disponibilidade dos suprimentos por caminho deterministico.
## Uso: var states := SupplyNetworkState.collect(tree)
static func collect(tree: SceneTree) -> Dictionary:
	var states: Dictionary = {}
	var root := tree.current_scene
	if root == null:
		return states
	for supply_node in tree.get_nodes_in_group("wave_supply_pickups"):
		if not root.is_ancestor_of(supply_node):
			continue
		states[String(root.get_path_to(supply_node))] = bool(supply_node.get("is_available"))
	return states


## Aplica disponibilidade sem confiar em caminhos ausentes ou invalidos.
## Uso: SupplyNetworkState.apply(tree, states)
static func apply(tree: SceneTree, states: Dictionary) -> void:
	var root := tree.current_scene
	if root == null:
		return
	for path_value in states:
		var supply := root.get_node_or_null(NodePath(String(path_value)))
		if supply != null and supply.has_method("apply_network_state"):
			supply.call("apply_network_state", bool(states[path_value]))
