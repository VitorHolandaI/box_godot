class_name SupplyNetworkState
extends RefCounted

## Alteracao local de suprimento marca o snapshot como sujo: o estado so
## viaja quando muda (todo pacote de jogador era reenviado igual a 10Hz).
static var dirty := true


static func mark_dirty() -> void:
	dirty = true


## Coleta indices dos suprimentos indisponiveis em ordem deterministica.
## Uso: var states := SupplyNetworkState.collect(tree)
static func collect(tree: SceneTree) -> Array[int]:
	var states: Array[int] = []
	var root := tree.current_scene
	if root == null:
		return states
	var supply_nodes := tree.get_nodes_in_group("wave_supply_pickups")
	for index in supply_nodes.size():
		var supply_node = supply_nodes[index]
		if not root.is_ancestor_of(supply_node):
			continue
		if not bool(supply_node.get("is_available")):
			states.append(index)
	return states


## Aplica disponibilidade sem confiar em indices ausentes ou invalidos.
## Uso: SupplyNetworkState.apply(tree, states)
static func apply(tree: SceneTree, states: Array) -> void:
	var root := tree.current_scene
	if root == null:
		return
	var supply_nodes := tree.get_nodes_in_group("wave_supply_pickups")
	for supply_node in supply_nodes:
		if root.is_ancestor_of(supply_node) and supply_node.has_method("apply_network_state"):
			supply_node.call("apply_network_state", true)
	for index_value in states:
		var index := int(index_value)
		if index < 0 or index >= supply_nodes.size():
			continue
		var supply = supply_nodes[index]
		if root.is_ancestor_of(supply) and supply.has_method("apply_network_state"):
			supply.call("apply_network_state", false)
