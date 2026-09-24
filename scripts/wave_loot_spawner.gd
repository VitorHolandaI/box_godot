# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WaveLootSpawner
extends RefCounted

## O que cai no chao a cada onda: o airdrop de armas (aviao + crate de
## paraquedas) e os itens de vida/municao espalhados, quase todos DENTRO das
## casas, pelas ancoras `building_loot_points` da cidade procedural.
##
## O `world` e o no da partida (scenes/main.tscn): ele continua dono da arvore
## de nos e do RPC do voo cosmico.
##
## Uso:
##   var loot := WaveLootSpawner.new(self)
##   airdrop_controller.airdrop_requested.connect(loot.launch_airdrop)
##   loot.spawn_scattered(wave_index)

const AIRDROP_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/airdrop_controller.gd")
## O aviao entra e sai do mapa nessa diagonal, baixo o bastante para ser visto.
const PLANE_ENTRY_OFFSET := Vector3(-190.0, 16.0, -24.0)
const PLANE_EXIT_OFFSET := Vector3(190.0, 16.0, 24.0)
## Anel de rua livre para o item que nao coube dentro de predio.
const STREET_MIN_RADIUS := 20.0
const STREET_MAX_RADIUS := 110.0
## Itens ao ar livre por onda: o resto nasce dentro das casas.
const STREET_ITEMS_PER_WAVE := 2

var world: Node3D
## Nomes estaveis (o sync por nome do snapshot depende deles).
var crate_index := 0
var loot_index := 0
## Fila de ancoras internas, embaralhada; recarrega quando esvazia.
var _interior_points: Array[Vector3] = []
var _interior_cursor := 0


func _init(world_node: Node3D = null) -> void:
	world = world_node


## Aviao cruza o mapa BAIXO (visivel) e solta o crate no ponto sorteado; o
## crate desce de paraquedas com fisica e abre espalhando as armas no chao.
## Uso: conectado ao sinal airdrop_requested do AirdropController.
func launch_airdrop(drop_position: Vector3, kinds: Array[int]) -> void:
	var plane_start := drop_position + PLANE_ENTRY_OFFSET
	var plane_end := drop_position + PLANE_EXIT_OFFSET
	_add_plane(plane_start, plane_end, drop_position, not NetworkSession.is_client(), kinds)
	if NetworkSession.is_server():
		world.call("broadcast_airdrop_flyby", plane_start, plane_end, drop_position)


## Voo cosmico no cliente: mesmo aviao, sem soltar crate (o crate chega pelo
## sync por nome do snapshot). Uso: chamado pelo RPC recebido no main.
func show_flyby(plane_start: Vector3, plane_end: Vector3, drop_position: Vector3) -> void:
	_add_plane(plane_start, plane_end, drop_position, false, [])


func _add_plane(plane_start: Vector3, plane_end: Vector3, drop_position: Vector3, drops_crate: bool, kinds: Array[int]) -> void:
	var plane := AirdropPlane.new()
	plane.configure(plane_start, plane_end, drop_position)
	world.add_child(plane)
	if drops_crate:
		# Partida local e servidor soltam o crate de verdade; no cliente o
		# crate chega pelo sync por nome do snapshot.
		plane.reached_drop_point.connect(_drop_crate.bind(drop_position, kinds))


func _drop_crate(drop_position: Vector3, kinds: Array[int]) -> void:
	var crate := AirSupplyPickup.new()
	crate.name = "AirCrate%d" % crate_index
	crate_index += 1
	crate.setup(kinds)
	# Nasce no ar (a _ready soma o DROP_HEIGHT) e desce de paraquedas.
	crate.position = Vector3(drop_position.x, 0.02, drop_position.z)
	world.add_child(crate)
	GroundWeaponSync.mark_dirty()


## Lote de itens de vida e municao da onda. Replica por nome via
## GroundWeaponSync; cada item some em 3 min.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func spawn_scattered(_wave_index: int = 0) -> void:
	if NetworkSession.is_client():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkSession.world_seed * 31337 + Time.get_ticks_msec()
	for entry in _wave_items():
		spawn_item(rng, int(entry[0]), int(entry[1]), true)
	# Poucas coisas na rua: dois itens ao ar livre.
	for _street in STREET_ITEMS_PER_WAVE:
		spawn_item(rng, GroundSupplyPickup.Kind.AMMO, 30, false)


## Cesta fixa da onda: vida em dobro do resto, e um pente de cada classe.
func _wave_items() -> Array[Array]:
	return [
		[GroundSupplyPickup.Kind.HEALTH, 35], [GroundSupplyPickup.Kind.HEALTH, 35], [GroundSupplyPickup.Kind.HEALTH, 35],
		[GroundSupplyPickup.Kind.HEALTH, 35], [GroundSupplyPickup.Kind.HEALTH, 35], [GroundSupplyPickup.Kind.HEALTH, 35],
		[GroundSupplyPickup.Kind.AMMO, 60], [GroundSupplyPickup.Kind.AMMO, 60], [GroundSupplyPickup.Kind.AMMO, 60],
		[GroundSupplyPickup.Kind.AMMO_SHOTGUN, 12], [GroundSupplyPickup.Kind.AMMO_UZI, 90],
		[GroundSupplyPickup.Kind.AMMO_MAGNUM, 8], [GroundSupplyPickup.Kind.AMMO_DOUBLE_BARREL, 6],
		[GroundSupplyPickup.Kind.AMMO_CARBINE, 30],
	]


## Item de municao/vida: por padrao DENTRO de um predio (ancora interna); sem
## ancora cai para a rua. `prefer_interior=false` forca a rua.
## Uso: loot.spawn_item(rng, kind, amount, true)
func spawn_item(rng: RandomNumberGenerator, kind: int, amount: int, prefer_interior: bool = true) -> void:
	var position := AIRDROP_CONTROLLER_SCRIPT.INVALID_DROP_POSITION
	if prefer_interior:
		position = _take_interior_position(rng)
	if position == AIRDROP_CONTROLLER_SCRIPT.INVALID_DROP_POSITION:
		position = AIRDROP_CONTROLLER_SCRIPT.pick_clear_position(world.get_tree(), rng, STREET_MIN_RADIUS, STREET_MAX_RADIUS)
	if position == AIRDROP_CONTROLLER_SCRIPT.INVALID_DROP_POSITION:
		return
	add_item(kind, amount, position)


## Cria o item num ponto ja escolhido (usado tambem pelo drop de abate).
## Uso: loot.add_item(kind, amount, ground_position)
func add_item(kind: int, amount: int, position: Vector3) -> void:
	var item := GroundSupplyPickup.new()
	item.name = "Loot%d" % loot_index
	loot_index += 1
	item.setup(kind, amount)
	world.add_child(item)
	GroundWeaponSync.mark_dirty()
	item.global_position = position


## Proximo ponto interno livre; recarrega e reembaralha quando acaba. Devolve
## INVALID quando a cidade ainda nao tem ancoras.
func _take_interior_position(rng: RandomNumberGenerator) -> Vector3:
	if _interior_cursor >= _interior_points.size():
		_interior_points = _collect_interior_points()
		_shuffle_with(_interior_points, rng)
		_interior_cursor = 0
	if _interior_points.is_empty():
		return AIRDROP_CONTROLLER_SCRIPT.INVALID_DROP_POSITION
	var point := _interior_points[_interior_cursor]
	_interior_cursor += 1
	return point


## Uma ancora por unidade, ja deslocada acima do piso.
func _collect_interior_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node in world.get_tree().get_nodes_in_group("building_loot_points"):
		var anchor := node as Node3D
		if anchor != null and is_instance_valid(anchor):
			points.append(anchor.global_position + Vector3.UP * 0.25)
	return points


## Embaralha com o RNG LOCAL: Array.shuffle usa o RNG global e mudava o timing
## de outros sistemas (roteador de zumbi), o que deixava testes instaveis.
static func _shuffle_with(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[swap]
		values[swap] = temporary
