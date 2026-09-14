class_name ProceduralRoomGenerator
extends RefCounted

const ROOM_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/room_blueprint.gd")
const UNIT_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/unit_blueprint.gd")


static func generate_apartment(apartment_seed: int, variant: int):
	var unit = UNIT_BLUEPRINT.new("Apartment_%d" % (variant + 1), 10.0, 8.0)
	if variant % 2 == 0:
		_add_standard_layout(unit)
	else:
		_add_compact_layout(unit)
	_add_windows(unit)
	return unit


static func generate_lobby(_lobby_seed: int, width: float, depth: float):
	var lobby = UNIT_BLUEPRINT.new("Lobby_A", width, depth)
	lobby.add_room(ROOM_BLUEPRINT.new("lobby", "lobby", Rect2(0.0, 0.0, width, depth * 0.65)))
	lobby.add_room(ROOM_BLUEPRINT.new("stairs", "stairs", Rect2(0.0, depth * 0.65, width * 0.3, depth * 0.35)))
	lobby.add_room(ROOM_BLUEPRINT.new("storage", "storage", Rect2(width * 0.3, depth * 0.65, width * 0.7, depth * 0.35)))
	_add_door(lobby, "lobby", "stairs", "horizontal", Vector2(width * 0.15, depth * 0.65), 1.4)
	_add_door(lobby, "lobby", "storage", "horizontal", Vector2(width * 0.65, depth * 0.65), 1.4)
	_add_door(lobby, "lobby", "outside", "horizontal", Vector2(width * 0.5, 0.0), 1.4)
	return lobby


static func generate_store(_store_seed: int, width: float, depth: float):
	var store = UNIT_BLUEPRINT.new("ShopUnit_A", width, depth)
	var sales_depth := depth * 0.65
	var stock_width := width * 0.62
	store.add_room(ROOM_BLUEPRINT.new("sales", "sales_floor", Rect2(0.0, 0.0, width, sales_depth)))
	store.add_room(ROOM_BLUEPRINT.new("stockroom", "stockroom", Rect2(0.0, sales_depth, stock_width, depth - sales_depth)))
	store.add_room(ROOM_BLUEPRINT.new("office", "office", Rect2(stock_width, sales_depth, width - stock_width, depth - sales_depth)))
	_add_door(store, "sales", "stockroom", "horizontal", Vector2(stock_width * 0.5, sales_depth), 1.4)
	_add_door(store, "sales", "office", "horizontal", Vector2(stock_width + (width - stock_width) * 0.5, sales_depth), 1.4)
	_add_door(store, "sales", "outside", "horizontal", Vector2(width * 0.5, 0.0), 1.8)
	_add_windows(store)
	return store


static func _add_standard_layout(unit) -> void:
	unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, 0.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("kitchen", "kitchen", Rect2(5.0, 0.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_a", "bedroom", Rect2(0.0, 4.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(5.0, 4.0, 2.5, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_b", "bedroom", Rect2(7.5, 4.0, 2.5, 4.0)))
	_add_door(unit, "living", "kitchen", "vertical", Vector2(5.0, 2.0), 1.4)
	_add_door(unit, "living", "bedroom_a", "horizontal", Vector2(2.5, 4.0), 1.4)
	_add_door(unit, "kitchen", "bathroom", "horizontal", Vector2(6.25, 4.0), 1.4)
	_add_door(unit, "bathroom", "bedroom_b", "vertical", Vector2(7.5, 6.0), 1.4)


static func _add_compact_layout(unit) -> void:
	unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, 0.0, 4.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("kitchen", "kitchen", Rect2(4.0, 0.0, 3.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(7.0, 0.0, 3.0, 3.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_a", "bedroom", Rect2(0.0, 4.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("corridor", "corridor", Rect2(5.0, 4.0, 2.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_b", "bedroom", Rect2(7.0, 3.0, 3.0, 5.0)))
	_add_door(unit, "living", "kitchen", "vertical", Vector2(4.0, 2.0), 1.4)
	_add_door(unit, "kitchen", "bathroom", "vertical", Vector2(7.0, 1.5), 1.4)
	_add_door(unit, "living", "bedroom_a", "horizontal", Vector2(2.0, 4.0), 1.4)
	_add_door(unit, "bedroom_a", "corridor", "vertical", Vector2(5.0, 6.0), 1.4)
	_add_door(unit, "corridor", "bedroom_b", "vertical", Vector2(7.0, 6.0), 1.4)


static func _add_windows(unit) -> void:
	for room in unit.rooms:
		if is_zero_approx(room.bounds.position.y):
			unit.add_window({"room_id": room.id, "axis": "horizontal", "center": Vector2(room.bounds.position.x + room.bounds.size.x * 0.5, 0.0), "width": 1.2})
		if is_zero_approx(room.bounds.position.x):
			unit.add_window({"room_id": room.id, "axis": "vertical", "center": Vector2(0.0, room.bounds.position.y + room.bounds.size.y * 0.5), "width": 1.2})
		if is_zero_approx(room.bounds.end.y - unit.depth):
			unit.add_window({"room_id": room.id, "axis": "horizontal", "center": Vector2(room.bounds.position.x + room.bounds.size.x * 0.5, unit.depth), "width": 1.2})
		if is_zero_approx(room.bounds.end.x - unit.width):
			unit.add_window({"room_id": room.id, "axis": "vertical", "center": Vector2(unit.width, room.bounds.position.y + room.bounds.size.y * 0.5), "width": 1.2})


static func _add_door(unit, room_a: String, room_b: String, axis: String, center: Vector2, width: float) -> void:
	unit.add_door({"room_a": room_a, "room_b": room_b, "axis": axis, "center": center, "width": width})
