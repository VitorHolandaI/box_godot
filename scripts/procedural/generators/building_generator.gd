class_name ProceduralBuildingGenerator
extends RefCounted

const ROOM_GENERATOR: GDScript = preload("res://scripts/procedural/generators/room_generator.gd")
const BUILDING_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/building_blueprint.gd")
const FLOOR_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/floor_blueprint.gd")
const APARTMENT_UNIT_SIZE := Vector2(10.0, 8.0)
# O boneco tem 2.34 m de altura e 1.16 m de largura: com a planta base de 10x8 m
# os comodos ficavam apertados. Casas usam a mesma planta ampliada na horizontal.
const HOUSE_FOOTPRINT_SCALE := 1.5
## Tamanhos de casa por seed (media/grande), em metros. O programa de comodos
## (floor_plan_generator.program_for_seed) acompanha a area. O lote tem 19x19 m,
## entao 18x15 e o maior que ainda cabe com folga de calcada.
## Sem casa pequena: comodo apertado deixava o zumbi preso (ver
## test_building_navigation._test_zombie_leaves_house_breaking_doors).
const HOUSE_SIZES: Array[Vector2] = [
	Vector2(16.0, 13.0),
	Vector2(18.0, 15.0),
]
const MAX_DOOR_WIDTH := 2.0
# Predio no lote de 19 m: 4 apartamentos de 6x7 m por andar (corredor central de
# 3 m) e o nucleo da escada numa faixa lateral de 8 m.
const APARTMENT_BUILDING_SIZE := Vector2(20.0, 18.0)
const APARTMENT_FLAT_SCALE := Vector2(1.2, 2.0)
## Nucleo lateral de 8 m: estreitar para 6 m desconectava a rampa dos lances
## altos no navmesh (erosao do agente), travando o zumbi no andar 3.
const STAIR_CORE := Rect2(12.0, 0.0, 8.0, 18.0)
# Portas do nucleo ficam no patamar da frente, antes do pe/topo dos lances.
const CORE_ENTRANCE_Z := 3.0
# Lances alternam de coluna e de sentido a cada andar: quem chega no topo de um
# lance anda poucos metros pelo patamar ate o pe do proximo, sem passar por baixo
# de nenhum lance. A faixa livre de ~2.8 m ao lado das colunas liga o patamar da
# frente ao do fundo. Inclinacao de 35 graus fica abaixo do floor_max_angle (45).
const STAIR_FLIGHT_COLUMNS_X: Array[float] = [13.5, 16.0]
const STAIR_FLIGHT_WIDTH := 1.8
## Vaos dos lances no fundo do nucleo: o patamar da frente (z < 11) fica livre
## para o corredor dos 4 apartamentos. Antes o vao ficava no meio e o
## guarda-corpo bloqueava a passagem corredor->nucleo.
const STAIR_FRONT_Z := 11.0
const STAIR_BACK_Z := 15.8


static func generate(building_seed: int, archetype: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	if archetype == "house":
		return _generate_house(building_seed, rng)
	if archetype == "store" or archetype == "grocery" or archetype == "gun_shop":
		return _generate_store(building_seed, archetype)
	return _generate_apartment_building(building_seed, rng)


static func _generate_house(building_seed: int, rng: RandomNumberGenerator):
	var floors := 1
	var house_variant := String.chr(65 + rng.randi_range(0, 2))
	# Casa media/grande por seed; no caminho antigo fica sempre 15x12.
	var house_size := HOUSE_SIZES[rng.randi_range(0, HOUSE_SIZES.size() - 1)] if ROOM_GENERATOR.use_plan_layout else APARTMENT_UNIT_SIZE * HOUSE_FOOTPRINT_SCALE
	var building = BUILDING_BLUEPRINT.new("House_%s" % house_variant, building_seed, house_size.x, house_size.y, floors)
	for floor_index in floors:
		var floor = FLOOR_BLUEPRINT.new("HouseFloor_A", floor_index)
		var unit
		if ROOM_GENERATOR.use_plan_layout:
			# Planta no tamanho final: o programa (quartos/banheiros) cresce com a
			# area, entao nao passa pelo scale_layout de 10x8. Casa tem 2 entradas:
			# principal na sala e de servico na despensa (tipo casa americana).
			unit = ROOM_GENERATOR.generate_apartment_from_plan(building_seed + floor_index, house_size.x, house_size.y, true)
			_add_house_entrances(unit, MAX_DOOR_WIDTH)
		else:
			unit = ROOM_GENERATOR.generate_apartment(building_seed + floor_index, floor_index % 2)
			unit.scale_layout(Vector2.ONE * HOUSE_FOOTPRINT_SCALE, MAX_DOOR_WIDTH)
			_add_entrance(unit, "top", MAX_DOOR_WIDTH)
		floor.add_unit(unit, Vector2.ZERO)
		building.add_floor(floor)
	return building


## Entradas da casa: principal na sala e de servico na despensa, cada uma na sua
## parede externa. O sentido inicial abre para dentro; ao interagir, a porta
## escolhe em tempo real o lado oposto ao jogador.
## Uso: _add_house_entrances(unit, MAX_DOOR_WIDTH)
static func _add_house_entrances(unit, door_width: float) -> void:
	_add_entrance_to_type(unit, "living_room", ["top", "bottom", "left", "right"], door_width)
	_add_entrance_to_type(unit, "storage", ["bottom", "left", "right", "top"], door_width)


## Poe porta externa num comodo do tipo, na primeira parede de borda da lista.
## Uso: _add_entrance_to_type(unit, "living_room", ["top"], 2.0)
static func _add_entrance_to_type(unit, room_type: String, edge_order: Array[String], door_width: float) -> bool:
	for room in unit.rooms:
		if room.room_type != room_type:
			continue
		var placement := _exterior_edge_door(unit, room, edge_order)
		if placement.is_empty():
			continue
		unit.add_door({
			"room_a": room.id,
			"room_b": "outside",
			"axis": placement["axis"],
			"center": placement["center"],
			"width": door_width,
			"swing_direction": _default_entrance_swing_direction(String(placement["edge"])),
		})
		return true
	return false


## Eixo e centro do vao na parede externa do comodo, ou vazio se ele nao toca
## nenhuma borda listada. Uso: interno do _add_entrance_to_type.
static func _exterior_edge_door(unit, room, edge_order: Array[String]) -> Dictionary:
	var bounds: Rect2 = room.bounds
	for edge in edge_order:
		if edge == "top" and is_zero_approx(bounds.position.y):
			return {"axis": "horizontal", "center": Vector2(bounds.position.x + bounds.size.x * 0.5, 0.0), "edge": edge}
		if edge == "bottom" and is_equal_approx(bounds.end.y, unit.depth):
			return {"axis": "horizontal", "center": Vector2(bounds.position.x + bounds.size.x * 0.5, unit.depth), "edge": edge}
		if edge == "left" and is_zero_approx(bounds.position.x):
			return {"axis": "vertical", "center": Vector2(0.0, bounds.position.y + bounds.size.y * 0.5), "edge": edge}
		if edge == "right" and is_equal_approx(bounds.end.x, unit.width):
			return {"axis": "vertical", "center": Vector2(unit.width, bounds.position.y + bounds.size.y * 0.5), "edge": edge}
	return {}


## Direcao inicial que leva a folha para dentro da casa. A interacao do jogador
## substitui esse fallback pelo lado oposto a ele. Uso: interno.
static func _default_entrance_swing_direction(edge: String) -> float:
	# O pivot da folha fica no inicio do vao no assembler; nesse referencial,
	# o sinal positivo leva top/right para dentro, nao o negativo.
	var inward := 1.0 if edge == "top" or edge == "right" else -1.0
	return inward


static func _generate_apartment_building(building_seed: int, rng: RandomNumberGenerator):
	var floor_count := rng.randi_range(4, 6)
	var variant := String.chr(65 + rng.randi_range(0, 2))
	var building = BUILDING_BLUEPRINT.new("ApartmentBuilding_%s" % variant, building_seed, APARTMENT_BUILDING_SIZE.x, APARTMENT_BUILDING_SIZE.y, floor_count)
	building.has_roof_terrace = true
	var lobby = FLOOR_BLUEPRINT.new("LobbyFloor", 0)
	lobby.add_unit(ROOM_GENERATOR.generate_lobby(building_seed, building.width, building.depth, STAIR_CORE, CORE_ENTRANCE_Z, MAX_DOOR_WIDTH), Vector2.ZERO)
	building.add_floor(lobby)
	for floor_index in range(1, building.floors):
		building.add_floor(_generate_residential_floor(building, building_seed, floor_index))
	# Um lance a mais que o numero de transicoes: o ultimo sobe ao terraco.
	for floor_index in building.floors:
		building.add_stair_flight(stair_flight_for_floor(floor_index))
	return building


## Lance que sobe do andar `floor_index` para o seguinte, em coordenadas do edificio.
## Uso: var flight := ProceduralBuildingGenerator.stair_flight_for_floor(0)
static func stair_flight_for_floor(floor_index: int) -> Dictionary:
	var rises_toward_front := floor_index % 2 == 0
	return {
		"floor_index": floor_index,
		"center_x": STAIR_FLIGHT_COLUMNS_X[floor_index % 2],
		"width": STAIR_FLIGHT_WIDTH,
		"bottom_z": STAIR_BACK_Z if rises_toward_front else STAIR_FRONT_Z,
		"top_z": STAIR_FRONT_Z if rises_toward_front else STAIR_BACK_Z,
	}


## Andar residencial: a planta vem do floor_plan_generator (varia por seed) e o
## numero de apartamentos varia por andar -- 4 (2x2 com corredor central),
## 2 (dois maiores com corredor) ou 1 (andar inteiro). Nenhuma porta externa:
## acima do terreo ela daria para o vazio. Uso: interno.
static func _generate_residential_floor(building, building_seed: int, floor_index: int):
	var floor = FLOOR_BLUEPRINT.new("ResidentialFloor_A", floor_index)
	var unit_seed := building_seed + floor_index * 11
	var count := _apartment_count_for_seed(unit_seed)
	var corridor_depth := 4.0
	if count == 1:
		var whole = ROOM_GENERATOR.generate_apartment_from_plan(unit_seed, 12.0, 18.0, false, "right")
		floor.add_unit(whole, Vector2.ZERO)
		floor.add_unit(ROOM_GENERATOR.generate_stair_core(STAIR_CORE.size), STAIR_CORE.position)
		_link_units(building, floor, 0, 1, "vertical", floor.units[0]["position"] + _right_edge_door_center(whole, 1.0, STAIR_FRONT_Z - 1.0))
		return floor
	if count == 2:
		var lower = ROOM_GENERATOR.generate_apartment_from_plan(unit_seed, 12.0, 7.0, false, "bottom")
		var upper = ROOM_GENERATOR.generate_apartment_from_plan(unit_seed + 7, 12.0, 7.0, false, "top")
		floor.add_unit(lower, Vector2.ZERO)
		floor.add_unit(upper, Vector2(0.0, 11.0))
		floor.add_unit(ROOM_GENERATOR.generate_corridor(12.0, corridor_depth), Vector2(0.0, 7.0))
		floor.add_unit(ROOM_GENERATOR.generate_stair_core(STAIR_CORE.size), STAIR_CORE.position)
		_link_units(building, floor, 0, 2, "horizontal", floor.units[0]["position"] + _entrance_door_center(lower, "bottom"))
		_link_units(building, floor, 1, 2, "horizontal", floor.units[1]["position"] + _entrance_door_center(upper, "top"))
		_link_units(building, floor, 2, 3, "vertical", Vector2(STAIR_CORE.position.x, 7.0 + corridor_depth * 0.5))
		return floor
	for row in 2:
		for column in 2:
			var entrance_side := "bottom" if row == 0 else "top"
			var position := Vector2(float(column) * 6.0, 0.0 if row == 0 else 11.0)
			floor.add_unit(ROOM_GENERATOR.generate_apartment_from_plan(unit_seed + row * 2 + column, 6.0, 7.0, false, entrance_side), position)
	floor.add_unit(ROOM_GENERATOR.generate_corridor(12.0, corridor_depth), Vector2(0.0, 7.0))
	floor.add_unit(ROOM_GENERATOR.generate_stair_core(STAIR_CORE.size), STAIR_CORE.position)
	var corridor_index := 4
	var core_index := 5
	for index in 4:
		var edge := "bottom" if index < 2 else "top"
		_link_units(building, floor, index, corridor_index, "horizontal", floor.units[index]["position"] + _entrance_door_center(floor.units[index]["blueprint"], edge))
	_link_units(building, floor, corridor_index, core_index, "vertical", Vector2(STAIR_CORE.position.x, 7.0 + corridor_depth * 0.5))
	return floor


## Numero de apartamentos do andar por seed: 4 e o comum, 2 as vezes e 1 raro.
## Uso: interno.
static func _apartment_count_for_seed(floor_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var roll := rng.randf()
	if roll < 0.15:
		return 1
	if roll < 0.4:
		return 2
	return 4


## Centro (local da unidade) da porta de entrada na borda onde a sala encosta.
## Uso: interno do _generate_residential_floor.
static func _entrance_door_center(unit, edge: String) -> Vector2:
	for room in unit.rooms:
		if room.room_type != "living_room":
			continue
		var bounds: Rect2 = room.bounds
		if edge == "bottom" and is_equal_approx(bounds.end.y, unit.depth):
			return Vector2(bounds.get_center().x, unit.depth)
		if edge == "top" and is_zero_approx(bounds.position.y):
			return Vector2(bounds.get_center().x, 0.0)
		if edge == "right" and is_equal_approx(bounds.end.x, unit.width):
			return Vector2(unit.width, bounds.get_center().y)
		if edge == "left" and is_zero_approx(bounds.position.x):
			return Vector2(0.0, bounds.get_center().y)
	if edge == "bottom":
		return Vector2(unit.width * 0.5, unit.depth)
	if edge == "top":
		return Vector2(unit.width * 0.5, 0.0)
	return Vector2(unit.width, unit.depth * 0.5)


## Porta na borda direita dentro da faixa [z_min, z_max], para nao cair sobre o
## vao da escada (z >= STAIR_FRONT_Z). Uso: interno do andar de 1 apartamento.
static func _right_edge_door_center(unit, z_min: float, z_max: float) -> Vector2:
	for room in unit.rooms:
		var bounds: Rect2 = room.bounds
		if not is_equal_approx(bounds.end.x, unit.width):
			continue
		var low := maxf(bounds.position.y, z_min)
		var high := minf(bounds.end.y, z_max)
		if high - low >= MAX_DOOR_WIDTH:
			return Vector2(unit.width, (low + high) * 0.5)
	for room in unit.rooms:
		if is_equal_approx((room.bounds as Rect2).end.x, unit.width):
			return Vector2(unit.width, (room.bounds as Rect2).get_center().y)
	return Vector2(unit.width, (z_min + z_max) * 0.5)


static func _link_units(building, floor, unit_a_index: int, unit_b_index: int, axis: String, center: Vector2) -> void:
	var placement_a: Dictionary = floor.units[unit_a_index]
	var placement_b: Dictionary = floor.units[unit_b_index]
	var room_a := _room_spanning_door(placement_a, axis, center, MAX_DOOR_WIDTH)
	var room_b := _room_spanning_door(placement_b, axis, center, MAX_DOOR_WIDTH)
	if room_a.is_empty() or room_b.is_empty():
		push_error("Passagem %s em %s (largura %.1f) nao cabe inteira num comodo das unidades %d/%d; esperado vao sem parede interna atravessada." % [axis, center, MAX_DOOR_WIDTH, unit_a_index, unit_b_index])
		return
	for pair in [[placement_a, room_a], [placement_b, room_b]]:
		var local_center: Vector2 = center - pair[0]["position"]
		pair[0]["blueprint"].add_door({"room_a": pair[1], "room_b": "neighbor", "axis": axis, "center": local_center, "width": MAX_DOOR_WIDTH})
	building.add_unit_link({
		"floor_index": floor.floor_index,
		"axis": axis,
		"center": center,
		"width": MAX_DOOR_WIDTH,
		"node_a": "%d:%s" % [unit_a_index, room_a],
		"node_b": "%d:%s" % [unit_b_index, room_b],
	})


## Comodo da unidade que contem as duas pontas do vao, logo ao lado da parede.
## Vazio quando o vao cruza a divisa entre dois comodos (parede no meio da porta).
static func _room_spanning_door(placement: Dictionary, axis: String, center: Vector2, width: float) -> String:
	var local_center: Vector2 = center - placement["position"]
	var unit = placement["blueprint"]
	var along := Vector2(0.0, 1.0) if axis == "vertical" else Vector2(1.0, 0.0)
	var across := Vector2(along.y, along.x) * 0.1
	var reach := width * 0.5 - 0.05
	for side in [across, -across]:
		var first_id: String = unit.room_id_at(local_center + side - along * reach)
		if not first_id.is_empty() and first_id == unit.room_id_at(local_center + side + along * reach):
			return first_id
	return ""


static func _generate_store(building_seed: int, archetype: String):
	var width := 18.0
	var depth := 14.0
	var name := "Grocery_A" if archetype == "grocery" else "GunShop_A" if archetype == "gun_shop" else "Shop_A"
	var building = BUILDING_BLUEPRINT.new(name, building_seed, width, depth, 1)
	var layout: Dictionary = ROOM_GENERATOR.store_layout_for_seed(building_seed, width, depth)
	building.metadata["store_layout"] = layout
	var floor = FLOOR_BLUEPRINT.new("CommercialFloor", 0)
	floor.add_unit(ROOM_GENERATOR.generate_store(building_seed, width, depth, layout), Vector2.ZERO)
	building.add_floor(floor)
	return building


static func _add_entrance(unit, edge: String, door_width: float = 1.4) -> void:
	for room in unit.rooms:
		var center := Vector2.ZERO
		var axis := ""
		if edge == "top" and is_zero_approx(room.bounds.position.y):
			center = Vector2(room.bounds.position.x + room.bounds.size.x * 0.5, 0.0)
			axis = "horizontal"
		elif edge == "bottom" and is_zero_approx(room.bounds.end.y - unit.depth):
			center = Vector2(room.bounds.position.x + room.bounds.size.x * 0.5, unit.depth)
			axis = "horizontal"
		elif edge == "left" and is_zero_approx(room.bounds.position.x):
			center = Vector2(0.0, room.bounds.position.y + room.bounds.size.y * 0.5)
			axis = "vertical"
		elif edge == "right" and is_zero_approx(room.bounds.end.x - unit.width):
			center = Vector2(unit.width, room.bounds.position.y + room.bounds.size.y * 0.5)
			axis = "vertical"
		if not axis.is_empty():
			var swing_direction := _default_entrance_swing_direction(edge)
			unit.add_door({"room_a": room.id, "room_b": "outside", "axis": axis, "center": center, "width": door_width, "swing_direction": swing_direction})
			return
