class_name ProceduralBuildingGenerator
extends RefCounted

const ROOM_GENERATOR: GDScript = preload("res://scripts/procedural/generators/room_generator.gd")
const BUILDING_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/building_blueprint.gd")
const FLOOR_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/floor_blueprint.gd")
const APARTMENT_UNIT_SIZE := Vector2(10.0, 8.0)
# O boneco tem 2.34 m de altura e 1.16 m de largura: com a planta base de 10x8 m
# os comodos ficavam apertados. Casas usam a mesma planta ampliada na horizontal.
const HOUSE_FOOTPRINT_SCALE := 1.5
const MAX_DOOR_WIDTH := 2.0
# Predio cabe no lote de 19 m: um apartamento grande por andar (12x16 m, a planta
# base esticada) e o nucleo da escada numa faixa lateral de 8 m. Antes eram tres
# apartamentos de 10x8 m e a passagem do nucleo caia sobre uma parede interna,
# deixando 1.14 m de vao para um boneco de 1.16 m (porta "travada").
const APARTMENT_BUILDING_SIZE := Vector2(20.0, 16.0)
const APARTMENT_FLAT_SCALE := Vector2(1.2, 2.0)
const STAIR_CORE := Rect2(12.0, 0.0, 8.0, 16.0)
# Portas do nucleo ficam no patamar da frente, antes do pe/topo dos lances.
const CORE_ENTRANCE_Z := 3.0
# Lances alternam de coluna e de sentido a cada andar: quem chega no topo de um
# lance anda poucos metros pelo patamar ate o pe do proximo, sem passar por baixo
# de nenhum lance. A faixa livre de ~2.8 m ao lado das colunas liga o patamar da
# frente ao do fundo. Inclinacao de 35 graus fica abaixo do floor_max_angle (45).
const STAIR_FLIGHT_COLUMNS_X: Array[float] = [13.5, 16.0]
const STAIR_FLIGHT_WIDTH := 1.8
const STAIR_FRONT_Z := 5.6
const STAIR_BACK_Z := 10.4


static func generate(building_seed: int, archetype: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	if archetype == "house":
		return _generate_house(building_seed, rng)
	if archetype == "store" or archetype == "grocery":
		return _generate_store(building_seed, archetype)
	return _generate_apartment_building(building_seed, rng)


static func _generate_house(building_seed: int, rng: RandomNumberGenerator):
	var floors := 1
	var house_variant := String.chr(65 + rng.randi_range(0, 2))
	var house_size := APARTMENT_UNIT_SIZE * HOUSE_FOOTPRINT_SCALE
	var building = BUILDING_BLUEPRINT.new("House_%s" % house_variant, building_seed, house_size.x, house_size.y, floors)
	for floor_index in floors:
		var floor = FLOOR_BLUEPRINT.new("HouseFloor_A", floor_index)
		var unit = ROOM_GENERATOR.generate_apartment(building_seed + floor_index, floor_index % 2)
		unit.scale_layout(Vector2.ONE * HOUSE_FOOTPRINT_SCALE, MAX_DOOR_WIDTH)
		_add_entrance(unit, "top", MAX_DOOR_WIDTH)
		floor.add_unit(unit, Vector2.ZERO)
		building.add_floor(floor)
	return building


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


## Andar residencial: apartamento espelhado com a sala colada no nucleo, para
## quem sai da escada entrar direto na sala. Nenhuma porta externa: acima do
## terreo ela daria para o vazio.
static func _generate_residential_floor(building, building_seed: int, floor_index: int):
	var floor = FLOOR_BLUEPRINT.new("ResidentialFloor_A", floor_index)
	var flat = ROOM_GENERATOR.generate_apartment(building_seed + floor_index * 11, floor_index % 2)
	flat.scale_layout(APARTMENT_FLAT_SCALE, MAX_DOOR_WIDTH)
	flat.mirror_horizontally()
	flat.remove_windows_on_line("vertical", flat.width)
	floor.add_unit(flat, Vector2.ZERO)
	floor.add_unit(ROOM_GENERATOR.generate_stair_core(STAIR_CORE.size), STAIR_CORE.position)
	_link_units(building, floor, 0, 1, "vertical", Vector2(STAIR_CORE.position.x, CORE_ENTRANCE_Z))
	return floor


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
	var name := "Grocery_A" if archetype == "grocery" else "Shop_A"
	var building = BUILDING_BLUEPRINT.new(name, building_seed, width, depth, 1)
	var floor = FLOOR_BLUEPRINT.new("CommercialFloor", 0)
	floor.add_unit(ROOM_GENERATOR.generate_store(building_seed, width, depth), Vector2.ZERO)
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
			unit.add_door({"room_a": room.id, "room_b": "outside", "axis": axis, "center": center, "width": door_width})
			return
