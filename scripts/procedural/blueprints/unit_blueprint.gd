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


func add_window(window: Dictionary) -> void:
	windows.append(window)
	for room in rooms:
		if room.id == window.get("room_id", ""):
			room.windows.append(window)


func is_graph_connected() -> bool:
	if rooms.is_empty():
		return false
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
			if not next.is_empty() and not visited.has(next):
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
