class_name GroundWeaponSync
extends RefCounted

## Sincroniza armas no chao (dropadas e crates de airdrop) por NOME, nao por
## indice: o grupo cresce/shrink dinamicamente e indices dessincronizariam
## servidor e cliente. Cada entrada = [nome, x, y, z, crate(0/1), payload].
## Payload de crate = Array[int] de kinds; payload de dropada = kind, mag,
## reserve, durability.
## Uso:
##   var estados := GroundWeaponSync.collect(tree)
##   GroundWeaponSync.apply(tree, estados)


## Lista deterministica (por ordem do grupo) das armas no chao.
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
			entries.append([String(node.name), node.global_position.x, node.global_position.y, node.global_position.z, 0, [int(pickup.weapon_kind), pickup.mag, pickup.reserve, pickup.durability]])
	return entries


## Concilia o cliente: spawna o que falta pelo nome, remove o que sumiu
## (coletado no servidor) e evita duplicar nos existentes.
## Uso: GroundWeaponSync.apply(tree, estados)
static func apply(tree: SceneTree, entries: Array) -> void:
	if tree == null or tree.current_scene == null:
		return
	var current_names: Dictionary = {}
	for node in tree.get_nodes_in_group("ground_weapons"):
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
	var is_crate := int(entry[4]) == 1
	var node: Node3D = null
	if is_crate:
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
	else:
		var payload: Array = entry[5]
		if payload.size() < 4 or not WeaponStats.is_crate_weapon(int(payload[0])):
			return null
		var pickup := GroundWeaponPickup.new()
		pickup.name = node_name
		pickup.setup(int(payload[0]), int(payload[1]), int(payload[2]), int(payload[3]))
		node = pickup
	parent.add_child(node)
	node.global_position = position
	return node
