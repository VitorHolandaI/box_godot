class_name ProceduralUnitBlueprint
extends RefCounted

var archetype: String
var width: float
var depth: float
var rooms: Array = []
var doors: Array[Dictionary] = []
var windows: Array[Dictionary] = []


func _init(unit_archetype: String, unit_width: float, unit_depth: float) -> void:
	archetype = unit_archetype
	width = unit_width
	depth = unit_depth


func add_room(room) -> void:
	rooms.append(room)


func add_door(door: Dictionary) -> void:
	doors.append(door)
	for room in rooms:
		if room.id == door.get("room_a", "") or room.id == door.get("room_b", ""):
			room.doors.append(door)


## Devolve o id do comodo que contem o ponto local, ou "" se nenhum contiver.
## Uso: var room_id := unit.room_id_at(Vector2(2.0, 7.9))
func room_id_at(local_point: Vector2) -> String:
	for room in rooms:
		if room.bounds.has_point(local_point):
			return room.id
	return ""


## Amplia a planta na horizontal (comodos, portas e janelas) mantendo o pe-direito.
## Portas crescem junto, limitadas a `max_door_width`.
## Uso: unit.scale_layout(1.5, 2.0)
func scale_layout(factor: float, max_door_width: float) -> void:
	if factor <= 0.0:
		push_error("Fator de escala da planta invalido %.2f; esperado > 0." % factor)
		return
	width *= factor
	depth *= factor
	for room in rooms:
		room.bounds = Rect2(room.bounds.position * factor, room.bounds.size * factor)
	for door in doors:
		door["center"] = (door["center"] as Vector2) * factor
		door["width"] = minf(float(door["width"]) * factor, max_door_width)
	for window in windows:
		window["center"] = (window["center"] as Vector2) * factor
		window["width"] = float(window["width"]) * factor


func add_window(window: Dictionary) -> void:
	windows.append(window)
	for room in rooms:
		if room.id == window.get("room_id", ""):
			room.windows.append(window)


func is_graph_connected() -> bool:
	if rooms.is_empty():
		return false
	var room_ids: Dictionary = {}
	for room in rooms:
		room_ids[room.id] = true
	var visited: Dictionary = {rooms[0].id: true}
	var pending: Array[String] = [rooms[0].id]
	while not pending.is_empty():
		var current: String = pending.pop_front()
		for door in doors:
			if door.get("room_b", "outside") == "outside":
				continue
			var next := ""
			if door.get("room_a", "") == current:
				next = door.get("room_b", "")
			elif door.get("room_b", "") == current:
				next = door.get("room_a", "")
			# Portas para "outside" ou para unidades vizinhas nao contam no grafo interno.
			if room_ids.has(next) and not visited.has(next):
				visited[next] = true
				pending.append(next)
	return visited.size() == rooms.size()


func signature() -> String:
	var result := "%s:%.2f:%.2f|" % [archetype, width, depth]
	for room in rooms:
		result += room.signature() + ";"
	for door in doors:
		result += "%s:%s:%s:%s" % [door.get("room_a"), door.get("room_b"), door.get("axis"), door.get("center")]
	return result
