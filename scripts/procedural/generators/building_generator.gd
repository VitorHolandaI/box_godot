class_name ProceduralBuildingGenerator
extends RefCounted

const ROOM_GENERATOR: GDScript = preload("res://scripts/procedural/generators/room_generator.gd")
const BUILDING_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/building_blueprint.gd")
const FLOOR_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/floor_blueprint.gd")
const APARTMENT_UNIT_SIZE := Vector2(10.0, 8.0)
# O boneco tem 2.34 m de altura e 1.16 m de largura: com a planta base de 10x8 m
# os comodos ficavam apertados. Casas usam a mesma planta ampliada na horizontal.
const HOUSE_FOOTPRINT_SCALE := 1.5
const HOUSE_MAX_DOOR_WIDTH := 2.0
const STAIR_CORE := Rect2(0.0, 8.0, 10.0, 8.0)
const STAIR_CORE_UNIT_INDEX := 2
# Lances alternam de coluna e de sentido a cada andar: quem chega no topo de um
# lance anda poucos metros pelo patamar ate o pe do proximo, sem passar por baixo
# de nenhum lance. Inclinacao de 35 graus fica abaixo do floor_max_angle (45).
const STAIR_FLIGHT_COLUMNS_X: Array[float] = [2.0, 5.0]
const STAIR_FLIGHT_WIDTH := 1.8
const STAIR_FRONT_Z := 9.8
const STAIR_BACK_Z := 14.6


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
		unit.scale_layout(HOUSE_FOOTPRINT_SCALE, HOUSE_MAX_DOOR_WIDTH)
		_add_entrance(unit, "top", HOUSE_MAX_DOOR_WIDTH)
		floor.add_unit(unit, Vector2.ZERO)
		building.add_floor(floor)
	return building


static func _generate_apartment_building(building_seed: int, rng: RandomNumberGenerator):
	var floor_count := rng.randi_range(4, 6)
	var variant := String.chr(65 + rng.randi_range(0, 2))
	var building = BUILDING_BLUEPRINT.new("ApartmentBuilding_%s" % variant, building_seed, 20.0, 16.0, floor_count)
	var lobby = FLOOR_BLUEPRINT.new("LobbyFloor", 0)
	lobby.add_unit(ROOM_GENERATOR.generate_lobby(building_seed, building.width, building.depth, STAIR_CORE), Vector2.ZERO)
	building.add_floor(lobby)
	for floor_index in range(1, building.floors):
		building.add_floor(_generate_residential_floor(building, building_seed, floor_index))
	for floor_index in range(building.floors - 1):
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


static func _generate_residential_floor(building, building_seed: int, floor_index: int):
	var floor = FLOOR_BLUEPRINT.new("ResidentialFloor_A", floor_index)
	for unit_index in 4:
		var position := Vector2(float(unit_index % 2) * APARTMENT_UNIT_SIZE.x, float(unit_index / 2) * APARTMENT_UNIT_SIZE.y)
		if unit_index == STAIR_CORE_UNIT_INDEX:
			floor.add_unit(ROOM_GENERATOR.generate_stair_core(STAIR_CORE.size), position)
			continue
		floor.add_unit(ROOM_GENERATOR.generate_apartment(building_seed + floor_index * 11 + unit_index, unit_index % 2), position)
	# Apartamentos dos andares altos sao acessados pelo nucleo, nunca por portas
	# externas que dariam para o vazio.
	_link_units(building, floor, 0, STAIR_CORE_UNIT_INDEX, "horizontal", Vector2(8.0, 8.0))
	_link_units(building, floor, STAIR_CORE_UNIT_INDEX, 3, "vertical", Vector2(10.0, 10.0))
	_link_units(building, floor, 1, 3, "horizontal", Vector2(12.0, 8.0))
	return floor


static func _link_units(building, floor, unit_a_index: int, unit_b_index: int, axis: String, center: Vector2) -> void:
	var placement_a: Dictionary = floor.units[unit_a_index]
	var placement_b: Dictionary = floor.units[unit_b_index]
	var room_a := _room_touching_edge(placement_a, axis, center)
	var room_b := _room_touching_edge(placement_b, axis, center)
	if room_a.is_empty() or room_b.is_empty():
		push_error("Passagem %s em %s nao toca comodos das unidades %d/%d; esperado ponto sobre a borda comum." % [axis, center, unit_a_index, unit_b_index])
		return
	var width := 1.4
	for pair in [[placement_a, room_a], [placement_b, room_b]]:
		var local_center: Vector2 = center - pair[0]["position"]
		pair[0]["blueprint"].add_door({"room_a": pair[1], "room_b": "neighbor", "axis": axis, "center": local_center, "width": width})
	building.add_unit_link({
		"floor_index": floor.floor_index,
		"axis": axis,
		"center": center,
		"width": width,
		"node_a": "%d:%s" % [unit_a_index, room_a],
		"node_b": "%d:%s" % [unit_b_index, room_b],
	})


static func _room_touching_edge(placement: Dictionary, axis: String, center: Vector2) -> String:
	var local_center: Vector2 = center - placement["position"]
	var unit = placement["blueprint"]
	var probe_offset := Vector2(0.1, 0.0) if axis == "vertical" else Vector2(0.0, 0.1)
	var inside_id: String = unit.room_id_at(local_center + probe_offset)
	return inside_id if not inside_id.is_empty() else unit.room_id_at(local_center - probe_offset)


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
