# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
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
## Cada eixo tem seu fator (x = largura, y = profundidade). Portas crescem pelo
## maior fator, limitadas a `max_door_width`, para passar o boneco de 1.16 m.
## Uso: unit.scale_layout(Vector2(1.2, 2.0), 2.0)
func scale_layout(factor: Vector2, max_door_width: float) -> void:
	if factor.x <= 0.0 or factor.y <= 0.0:
		push_error("Fator de escala da planta invalido %s; esperado Vector2 com x e y > 0." % factor)
		return
	width *= factor.x
	depth *= factor.y
	for room in rooms:
		room.bounds = Rect2(room.bounds.position * factor, room.bounds.size * factor)
	for door in doors:
		door["center"] = (door["center"] as Vector2) * factor
		door["width"] = minf(float(door["width"]) * maxf(factor.x, factor.y), max_door_width)
	for window in windows:
		window["center"] = (window["center"] as Vector2) * factor
		window["width"] = float(window["width"]) * (factor.x if window.get("axis", "") == "horizontal" else factor.y)


## Espelha a planta da esquerda para a direita (comodos, portas e janelas).
## Portas e janelas sao os mesmos dicionarios guardados nos comodos.
## Uso: unit.mirror_horizontally()
func mirror_horizontally() -> void:
	for room in rooms:
		room.bounds = Rect2(width - room.bounds.end.x, room.bounds.position.y, room.bounds.size.x, room.bounds.size.y)
	for opening in doors + windows:
		var center: Vector2 = opening["center"]
		opening["center"] = Vector2(width - center.x, center.y)


## Remove janelas de uma linha de parede, ex.: a parede colada no nucleo da
## escada, onde a janela seria um buraco tampado pela parede vizinha.
## Uso: unit.remove_windows_on_line("vertical", unit.width)
func remove_windows_on_line(axis: String, line: float) -> void:
	var kept: Array[Dictionary] = []
	for window in windows:
		var center: Vector2 = window["center"]
		var window_line := center.x if axis == "vertical" else center.y
		if window.get("axis", "") == axis and is_equal_approx(window_line, line):
			continue
		kept.append(window)
	windows = kept
	for room in rooms:
		room.windows.assign(room.windows.filter(func(window: Dictionary) -> bool: return kept.has(window)))


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
