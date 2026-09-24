# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name GroundWeaponSync
extends RefCounted

## Sincroniza itens no chao por NOME, nao por indice: armas dropadas,
## crates de airdrop (grupo "ground_weapons") e suprimentos espalhados
## (grupo "ground_supplies"). Cada entrada = [nome, x, y, z, tipo, payload]:
## tipo 0 = dropada [kind, mag, reserve, durability, segundos_restantes]; 1 = crate [kinds];
## 2 = item de vida/municao [kind, amount].
## Uso:
##   var estados := GroundWeaponSync.collect(tree)
##   GroundWeaponSync.apply(tree, estados)


## Alteracao de qualquer no do chao marca a lista como suja.
static var dirty := true


static func mark_dirty() -> void:
	dirty = true

## Lista deterministica (por ordem do grupo) dos itens no chao.
## Uso: var estados := GroundWeaponSync.collect(tree)
static func collect(tree: SceneTree) -> Array:
	var entries: Array = []
	if tree == null or tree.current_scene == null:
		return entries
	for node in tree.get_nodes_in_group("ground_weapons"):
		if not tree.current_scene.is_ancestor_of(node):
			continue
		if node is AirSupplyPickup:
			var crate := node as AirSupplyPickup
			var kinds: Array = []
			for kind in crate.weapon_kinds:
				kinds.append(int(kind))
			entries.append([String(node.name), node.global_position.x, node.global_position.y, node.global_position.z, 1, kinds])
		elif node is GroundWeaponPickup:
			var pickup := node as GroundWeaponPickup
			entries.append([String(node.name), node.global_position.x, node.global_position.y, node.global_position.z, 0, [int(pickup.weapon_kind), pickup.mag, pickup.reserve, pickup.durability, roundi(pickup.remaining_lifetime())]])
	for node in tree.get_nodes_in_group("ground_supplies"):
		if not tree.current_scene.is_ancestor_of(node):
			continue
		if node is GroundSupplyPickup:
			var supply := node as GroundSupplyPickup
			entries.append([String(node.name), node.global_position.x, node.global_position.y, node.global_position.z, 2, [int(supply.supply_kind), supply.amount]])
	return entries


## Concilia o cliente: spawna o que falta pelo nome, remove o que sumiu
## (coletado no servidor) e evita duplicar nos existentes.
## Uso: GroundWeaponSync.apply(tree, estados)
static func apply(tree: SceneTree, entries: Array) -> void:
	if tree == null or tree.current_scene == null:
		return
	var current_names: Dictionary = {}
	for group_name in ["ground_weapons", "ground_supplies"]:
		for node in tree.get_nodes_in_group(group_name):
			if tree.current_scene.is_ancestor_of(node):
				current_names[String(node.name)] = node
	var expected_names: Dictionary = {}
	for entry_value in entries:
		if not entry_value is Array or (entry_value as Array).size() < 6:
			continue
		var entry: Array = entry_value
		var node_name := String(entry[0])
		var node: Node = current_names.get(node_name)
		if node == null:
			node = _spawn_from_entry(tree.current_scene, entry)
		if node != null:
			expected_names[node_name] = true
	for node_name in current_names:
		if expected_names.has(node_name):
			continue
		var stale := current_names[node_name] as Node
		if stale != null:
			stale.queue_free()


static func _spawn_from_entry(parent: Node, entry: Array) -> Node:
	var node_name := String(entry[0])
	var position := Vector3(float(entry[1]), float(entry[2]), float(entry[3]))
	var entry_kind := int(entry[4])
	var node: Node3D = null
	match entry_kind:
		1:
			var crate := AirSupplyPickup.new()
			crate.name = node_name
			var kinds: Array[int] = []
			for kind_value in (entry[5] as Array):
				var kind := int(kind_value)
				if WeaponStats.is_crate_weapon(kind):
					kinds.append(kind)
			crate.setup(kinds)
			crate.starts_landed = position.y <= 0.1
			node = crate
		2:
			var payload: Array = entry[5]
			if payload.size() < 2:
				return null
			var supply := GroundSupplyPickup.new()
			supply.name = node_name
			supply.setup(int(payload[0]), int(payload[1]))
			node = supply
		_:
			var payload: Array = entry[5]
			if payload.size() < 4 or not WeaponStats.is_crate_weapon(int(payload[0])):
				return null
			var pickup := GroundWeaponPickup.new()
			pickup.name = node_name
			pickup.setup(int(payload[0]), int(payload[1]), int(payload[2]), int(payload[3]))
			# Tempo restante (5o campo): o cliente pisca junto com o sumico no servidor.
			if payload.size() >= 5:
				pickup.lifetime_seconds = float(payload[4])
			node = pickup
	parent.add_child(node)
	node.global_position = position
	return node
