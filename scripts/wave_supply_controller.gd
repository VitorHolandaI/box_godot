class_name WaveSupplyController
extends RefCounted

const BUILDING_SUPPLY_CHANCE_PERCENT := 70

var scene_tree: SceneTree
var world_seed: int


func _init(tree: SceneTree, seed: int) -> void:
	scene_tree = tree
	world_seed = seed


## Reabastece quatro pontos da Safehouse e sorteia os demais interiores.
## Uso: controller.refresh_wave(2)
func refresh_wave(wave_index: int) -> void:
	for supply_node in scene_tree.get_nodes_in_group("wave_supply_pickups"):
		var supply := supply_node as Area3D
		if supply == null or not supply.has_method("set_available"):
			continue
		var available := supply.is_in_group("safehouse_supply_points")
		if not available:
			var roll := posmod(String(supply.get_path()).hash() + world_seed * 31 + wave_index * 1009, 100)
			available = roll < BUILDING_SUPPLY_CHANCE_PERCENT
		supply.call("set_available", available)
