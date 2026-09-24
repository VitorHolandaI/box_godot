# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name SafehouseDoorSync
extends RefCounted

## Estado de TODAS as portas de safehouse num inteiro, um bit por porta.
##
## Antes viajava so a porta da casa central, num `bool` solto no snapshot de
## jogador. No mata-mata cada base tem a sua porta, e elas ficavam FECHADAS para
## sempre no cliente: o cliente nunca decide sozinho (SafehouseDoor sai cedo do
## _physics_process quando e cliente) e ninguem mandava o estado delas.
##
## A ordem dos bits e o caminho do no, ordenado. Servidor e cliente montam a
## mesma cidade a partir da mesma seed (CityGenerator roda nos dois lados), entao
## a lista de portas e identica — e por isso que mexer no gerador de mundo exige
## subir o BuildInfo.GAME_BUILD, senao os bits apontam para portas diferentes.
##
## Uso:
##   var portas := SafehouseDoorSync.ordered_doors(get_tree())
##   _apply_player_snapshot.rpc_id(peer, payload, SafehouseDoorSync.mask_from(portas))
##   SafehouseDoorSync.apply_mask(portas, mascara)

## Teto de portas no bitmask. Hoje sao 3 no maximo (central + 2 bases do PVP);
## o limite existe para o deslocamento nunca estourar o inteiro do RPC.
const MAX_DOORS := 32


## Portas do grupo em ordem estavel (caminho do no). Uso: ordered_doors(tree)
static func ordered_doors(tree: SceneTree) -> Array:
	if tree == null:
		return []
	var doors: Array = tree.get_nodes_in_group("safehouse_door")
	doors.sort_custom(
		func(first: Node, second: Node) -> bool:
			return String(first.get_path()) < String(second.get_path())
	)
	return doors


## Bit ligado = porta aberta, na ordem de `ordered_doors`.
## Uso: var mascara := SafehouseDoorSync.mask_from(portas)
static func mask_from(doors: Array) -> int:
	var mask := 0
	for index in mini(doors.size(), MAX_DOORS):
		var door: Variant = doors[index]
		if door is Node and is_instance_valid(door) and bool((door as Node).call("is_open_requested")):
			mask |= 1 << index
	return mask


## Aplica a mascara nas portas do cliente (mesma ordem do servidor).
## Uso: SafehouseDoorSync.apply_mask(portas, mascara)
static func apply_mask(doors: Array, mask: int) -> void:
	for index in mini(doors.size(), MAX_DOORS):
		var door: Variant = doors[index]
		if door is Node and is_instance_valid(door):
			(door as Node).call("apply_network_open_state", (mask & (1 << index)) != 0)
