class_name ProceduralBuildingGenerator
extends RefCounted

const ROOM_GENERATOR: GDScript = preload("res://scripts/procedural/generators/room_generator.gd")
const BUILDING_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/building_blueprint.gd")
const FLOOR_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/floor_blueprint.gd")


static func generate(building_seed: int, archetype: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	if archetype == "house":
		return _generate_house(building_seed, rng)
	return _generate_apartment_building(building_seed, rng)


static func _generate_house(building_seed: int, rng: RandomNumberGenerator):
	var floors := 1 + int(rng.randi() % 2)
	var building = BUILDING_BLUEPRINT.new("House_A", building_seed, 10.0, 8.0, floors)
	for floor_index in floors:
		var floor = FLOOR_BLUEPRINT.new("HouseFloor_A", floor_index)
		var unit = ROOM_GENERATOR.generate_apartment(building_seed + floor_index, floor_index % 2)
		_add_entrance(unit, "top")
		floor.add_unit(unit, Vector2.ZERO)
		building.add_floor(floor)
	return building


static func _generate_apartment_building(building_seed: int, _rng: RandomNumberGenerator):
	var building = BUILDING_BLUEPRINT.new("ApartmentBuilding_A", building_seed, 20.0, 16.0, 6)
	var lobby = FLOOR_BLUEPRINT.new("LobbyFloor", 0)
	lobby.add_unit(ROOM_GENERATOR.generate_lobby(building_seed, building.width, building.depth), Vector2.ZERO)
	building.add_floor(lobby)
	for floor_index in range(1, building.floors):
		var floor = FLOOR_BLUEPRINT.new("ResidentialFloor_A", floor_index)
		for unit_index in 4:
			var unit = ROOM_GENERATOR.generate_apartment(building_seed + floor_index * 11 + unit_index, unit_index % 2)
			var position := Vector2(float(unit_index % 2) * 10.0, float(unit_index / 2) * 8.0)
			_add_outer_entrance(unit, position, building.width, building.depth)
			floor.add_unit(unit, position)
		building.add_floor(floor)
	return building


static func _add_outer_entrance(unit, position: Vector2, width: float, depth: float) -> void:
	if is_zero_approx(position.y):
		_add_entrance(unit, "top")
	elif is_zero_approx(position.y + unit.depth - depth):
		_add_entrance(unit, "bottom")
	elif is_zero_approx(position.x):
		_add_entrance(unit, "left")
	else:
		_add_entrance(unit, "right")


static func _add_entrance(unit, edge: String) -> void:
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
			unit.add_door({"room_a": room.id, "room_b": "outside", "axis": axis, "center": center, "width": 1.4})
			return
