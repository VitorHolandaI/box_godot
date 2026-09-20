class_name ProceduralApartmentDetailAssembler
extends RefCounted

## Detalhes do predio: balcao da recepcao, lixeiras do lixo, split de
## ar-condicionado nos apartamentos e condensadoras na fachada. Tudo segue a
## posicao real dos comodos no blueprint, entao acompanha a planta.
## Uso: ProceduralApartmentDetailAssembler.add_details(body, building)

const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")


static func add_details(body: StaticBody3D, building) -> void:
	_add_reception(body, building)
	_add_trash_room(body, building)
	_add_interior_air_conditioners(body, building)
	_add_exterior_air_conditioners(body, building)


## Comodos de um tipo a partir de um andar, com origem e altura ja resolvidas.
## Uso: interno. var rooms := _room_placements(building, "living_room", 1)
static func _room_placements(building, room_type: String, min_floor: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for floor_blueprint in building.floor_blueprints:
		var floor_index := int(floor_blueprint.floor_index)
		if floor_index < min_floor:
			continue
		for placement in floor_blueprint.units:
			var unit = placement["blueprint"]
			for room in unit.rooms:
				if room.room_type == room_type:
					result.append({
						"room": room,
						"origin": placement["position"],
						"floor_y": float(floor_index) * building.floor_height + 0.08,
					})
	return result


static func _add_reception(body: StaticBody3D, building) -> void:
	var placements := _room_placements(building, "reception", 0)
	if placements.is_empty():
		return
	var placement: Dictionary = placements[0]
	var bounds: Rect2 = placement["room"].bounds
	var origin: Vector2 = placement["origin"]
	var floor_y: float = placement["floor_y"]
	var desk_material: Material = BUILDING_MATERIALS.opaque(Color(0.30, 0.22, 0.15), building.floor_height)
	var sign_material: Material = BUILDING_MATERIALS.opaque(Color(0.55, 0.62, 0.58), building.floor_height)
	var metal_material: Material = BUILDING_MATERIALS.opaque(Color(0.42, 0.45, 0.48), building.floor_height, false, 0.5, 0.35)
	var wood_material: Material = BUILDING_MATERIALS.opaque(Color(0.36, 0.26, 0.16), building.floor_height)
	var plant_material: Material = BUILDING_MATERIALS.opaque(Color(0.22, 0.42, 0.24), building.floor_height)
	var left := origin.x + bounds.position.x
	var front := origin.y + bounds.position.y
	var back := origin.y + bounds.end.y
	var center_x := left + 1.6
	var center_z := front + 1.1
	BOX_BUILDER.add_box(body, "ReceptionDesk", Vector3(2.4, 0.9, 0.7), Vector3(center_x, floor_y + 0.45, center_z), desk_material, true)
	BOX_BUILDER.add_box(body, "ReceptionSign", Vector3(1.1, 0.32, 0.05), Vector3(center_x, floor_y + 2.15, center_z - 0.3), sign_material, false)
	BOX_BUILDER.add_box(body, "ReceptionMailboxes", Vector3(1.1, 0.9, 0.4), Vector3(left + 1.0, floor_y + 1.05, front + 0.6), metal_material, true)
	BOX_BUILDER.add_box(body, "ReceptionBench", Vector3(1.6, 0.5, 0.55), Vector3(left + 3.0, floor_y + 0.25, front + 4.0), wood_material, true)
	BOX_BUILDER.add_box(body, "ReceptionVendingMachine", Vector3(1.0, 1.9, 0.75), Vector3(left + 10.6, floor_y + 0.95, front + 1.0), metal_material, true)
	for plant_x in [0.8, 11.0]:
		BOX_BUILDER.add_box(body, "ReceptionPlant", Vector3(0.5, 1.1, 0.5), Vector3(left + plant_x, floor_y + 0.55, back - 1.2), plant_material, false)


static func _add_trash_room(body: StaticBody3D, building) -> void:
	var placements := _room_placements(building, "trash_room", 0)
	if placements.is_empty():
		return
	var placement: Dictionary = placements[0]
	var bounds: Rect2 = placement["room"].bounds
	var origin: Vector2 = placement["origin"]
	var floor_y: float = placement["floor_y"]
	var bin_material: Material = BUILDING_MATERIALS.opaque(Color(0.20, 0.26, 0.20), building.floor_height, false, 0.3, 0.5)
	var index := 0
	for offset_x in [0.7, 4.7]:
		BOX_BUILDER.add_box(body, "TrashBin_%d" % index, Vector3(0.8, 1.1, 0.8), Vector3(origin.x + bounds.position.x + offset_x, floor_y + 0.55, origin.y + bounds.end.y - 1.0), bin_material, true)
		index += 1


static func _add_interior_air_conditioners(body: StaticBody3D, building) -> void:
	var unit_material: Material = BUILDING_MATERIALS.opaque(Color(0.82, 0.84, 0.82), building.floor_height, false, 0.1, 0.5)
	var index := 0
	for placement in _room_placements(building, "living_room", 1):
		var bounds: Rect2 = placement["room"].bounds
		var origin: Vector2 = placement["origin"]
		var floor_y: float = placement["floor_y"]
		var x := origin.x + bounds.position.x + 0.55
		var z := origin.y + bounds.position.y + bounds.size.y * 0.5
		BOX_BUILDER.add_box(body, "InteriorAirConditioner_%d" % index, Vector3(0.8, 0.32, 0.24), Vector3(x, floor_y + 2.35, z), unit_material, false)
		index += 1


static func _add_exterior_air_conditioners(body: StaticBody3D, building) -> void:
	var unit_material: Material = BUILDING_MATERIALS.opaque(Color(0.78, 0.80, 0.78), building.floor_height, false, 0.15, 0.58)
	var grille_material: Material = BUILDING_MATERIALS.opaque(Color(0.26, 0.30, 0.31), building.floor_height, false, 0.35, 0.35)
	var offset := float(posmod(int(building.seed), 5) - 2) * 0.55
	var x := clampf(building.width * 0.5 + offset, 1.0, building.width - 1.0)
	var z: float = building.depth + 0.17
	for floor_index in building.floors:
		var y: float = float(floor_index) * building.floor_height + 2.05
		BOX_BUILDER.add_box(body, "ExteriorAirConditioner_%d" % floor_index, Vector3(1.05, 0.52, 0.28), Vector3(x, y, z), unit_material, false)
		BOX_BUILDER.add_box(body, "ExteriorAirConditionerGrille_%d" % floor_index, Vector3(0.68, 0.28, 0.03), Vector3(x, y, z + 0.15), grille_material, false)
