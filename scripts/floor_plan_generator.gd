class_name FloorPlanGenerator
extends RefCounted

## Gera planta de casa por subdivisao recursiva do retangulo, no estilo
## squarified treemap: o espaco e cortado no eixo mais longo, na proporcao dos
## pesos dos quartos, ate sobrar um quarto por regiao. As portas saem de uma
## arvore geradora sobre o grafo de vizinhanca, entao TODO quarto fica
## alcancavel a partir do maior - que e a propriedade que a literatura exige
## (Marson & Musse 2010, https://doi.org/10.1155/2010/624817).
##
## Tudo deterministico pela seed: a mesma seed da a mesma planta, o que permite
## testar e reproduzir.
##
## Uso:
##   var plan := FloorPlanGenerator.generate(14, 10, 1234, FloorPlanGenerator.HOUSE_PROGRAM)
##   for room in plan["rooms"]:
##       print(room["name"], " ", room["rect"])

## Lado minimo de um quarto em celulas: abaixo disso o corte nao vale.
const MIN_ROOM_SIDE := 3
## Trecho minimo de parede para caber uma porta.
const MIN_DOOR_EDGE := 2
## Deslocamento do vizinho por lado: 0 norte, 1 leste, 2 sul, 3 oeste.
const SIDE_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Programa de uma casa: nome do quarto e peso relativo de area.
const HOUSE_PROGRAM: Array[Dictionary] = [
	{"name": "SALA", "weight": 4.0},
	{"name": "COZINHA", "weight": 2.5},
	{"name": "QUARTO", "weight": 3.0},
	{"name": "BANHEIRO", "weight": 1.5},
	{"name": "CORREDOR", "weight": 1.0},
]


## Planta: {"rooms": [{"name": String, "rect": Rect2i}], "doors": [{"a": int,
## "b": int, "cell": Vector2i}]}. Os indices apontam para "rooms" na mesma
## ordem. Uso: var plan := FloorPlanGenerator.generate(14, 10, 7)
static func generate(width_cells: int, depth_cells: int, plan_seed: int, program: Array[Dictionary] = HOUSE_PROGRAM) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = plan_seed
	var rooms: Array[Dictionary] = []
	var order := _deterministic_shuffle(program, rng)
	_subdivide(Rect2i(0, 0, maxi(width_cells, MIN_ROOM_SIDE), maxi(depth_cells, MIN_ROOM_SIDE)), order, rooms, rng)
	return {
		"rooms": rooms,
		"doors": _spanning_doors(rooms),
	}


## Subdivide a regiao em duas, na proporcao do peso de cada grupo de quartos, e
## segue recursivamente. O corte e no eixo mais longo, que e o que mantem os
## quartos perto de quadrados. Uso: interno.
static func _subdivide(rect: Rect2i, members: Array[Dictionary], rooms: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	if members.is_empty():
		return
	if members.size() == 1:
		rooms.append({"name": String(members[0]["name"]), "rect": rect})
		return
	var total := 0.0
	for member in members:
		total += float(member["weight"])
	var half_weight := 0.0
	var split_index := 1
	for index in members.size():
		half_weight += float(members[index]["weight"])
		if half_weight * 2.0 >= total:
			split_index = clampi(index + 1, 1, members.size() - 1)
			break
	var first := members.slice(0, split_index)
	var second := members.slice(split_index)
	var first_weight := 0.0
	for member in first:
		first_weight += float(member["weight"])
	var ratio := clampf(first_weight / maxf(total, 0.001), 0.25, 0.75)
	if rect.size.x >= rect.size.y:
		var cut := clampi(roundi(float(rect.size.x) * ratio), MIN_ROOM_SIDE, rect.size.x - MIN_ROOM_SIDE)
		_subdivide(Rect2i(rect.position.x, rect.position.y, cut, rect.size.y), first, rooms, rng)
		_subdivide(Rect2i(rect.position.x + cut, rect.position.y, rect.size.x - cut, rect.size.y), second, rooms, rng)
	else:
		var cut := clampi(roundi(float(rect.size.y) * ratio), MIN_ROOM_SIDE, rect.size.y - MIN_ROOM_SIDE)
		_subdivide(Rect2i(rect.position.x, rect.position.y, rect.size.x, cut), first, rooms, rng)
		_subdivide(Rect2i(rect.position.x, rect.position.y + cut, rect.size.x, rect.size.y - cut), second, rooms, rng)


## Portas por arvore geradora do grafo de vizinhanca, partindo do maior quarto:
## garante que da para chegar em todos os quartos e nao poe porta a toa.
## Uso: interno (chamado pelo generate).
static func _spanning_doors(rooms: Array[Dictionary]) -> Array[Dictionary]:
	var doors: Array[Dictionary] = []
	if rooms.is_empty():
		return doors
	var adjacency := _build_adjacency(rooms)
	var biggest := 0
	for index in rooms.size():
		if (rooms[index]["rect"] as Rect2i).get_area() > (rooms[biggest]["rect"] as Rect2i).get_area():
			biggest = index
	var visited: Array[bool] = []
	visited.resize(rooms.size())
	var queue: Array[int] = [biggest]
	visited[biggest] = true
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor in adjacency[current]:
			var target := int(neighbor["room"])
			if visited[target]:
				continue
			visited[target] = true
			doors.append({"a": current, "b": target, "cell": neighbor["cell"]})
			queue.append(target)
	return doors


## Vizininhanca entre quartos: pares com parede comum longa o bastante para
## porta, guardando uma celula da parede para a porta.
## Uso: interno.
static func _build_adjacency(rooms: Array[Dictionary]) -> Array:
	var adjacency: Array = []
	adjacency.resize(rooms.size())
	for index in rooms.size():
		adjacency[index] = []
	for first in rooms.size():
		for second in range(first + 1, rooms.size()):
			if first == second:
				continue
			var shared := _shared_edge(rooms[first]["rect"] as Rect2i, rooms[second]["rect"] as Rect2i)
			if shared.is_empty():
				continue
			adjacency[first].append({"room": second, "cell": shared["cell"]})
			adjacency[second].append({"room": first, "cell": shared["cell"]})
	return adjacency


## Parede comum entre dois quartos e uma celula no meio dela, ou vazio quando
## nao se tocam o bastante. Uso: interno.
static func _shared_edge(first: Rect2i, second: Rect2i) -> Dictionary:
	if first.position.x + first.size.x == second.position.x or second.position.x + second.size.x == first.position.x:
		var top := maxi(first.position.y, second.position.y)
		var bottom := mini(first.position.y + first.size.y, second.position.y + second.size.y)
		if bottom - top >= MIN_DOOR_EDGE:
			var x := first.position.x + first.size.x if second.position.x > first.position.x else first.position.x
			return {"cell": Vector2i(x, (top + bottom) / 2)}
	if first.position.y + first.size.y == second.position.y or second.position.y + second.size.y == first.position.y:
		var left := maxi(first.position.x, second.position.x)
		var right := mini(first.position.x + first.size.x, second.position.x + second.size.x)
		if right - left >= MIN_DOOR_EDGE:
			var y := first.position.y + first.size.y if second.position.y > first.position.y else first.position.y
			return {"cell": Vector2i((left + right) / 2, y)}
	return {}


## Traduz a planta em paredes e vaos, que e o que um montador precisa consumir:
## cada parede e uma celula mais um lado (0=norte, 1=leste, 2=sul, 3=oeste) e
## cada portao e o mesmo par com o vao aberto. Tira as paredes internas das
## divisas entre quartos e o resto vira parede externa, entao o desenho fecha.
## Uso: var interior := FloorPlanGenerator.draft_interior(plan)
static func draft_interior(plan: Dictionary) -> Dictionary:
	var rooms: Array = plan["rooms"]
	var owner_of := {}
	for index in rooms.size():
		var rect: Rect2i = rooms[index]["rect"]
		for x: int in range(rect.position.x, rect.end.x):
			for y: int in range(rect.position.y, rect.end.y):
				owner_of[Vector2i(x, y)] = index
	var doors := {}
	for door in plan["doors"]:
		doors[door["cell"]] = true
	var walls: Array[Dictionary] = []
	var openings: Array[Dictionary] = []
	for index in rooms.size():
		var rect: Rect2i = rooms[index]["rect"]
		for x: int in range(rect.position.x, rect.end.x):
			_add_wall_side(walls, openings, owner_of, doors, index, Vector2i(x, rect.position.y), 0)
			_add_wall_side(walls, openings, owner_of, doors, index, Vector2i(x, rect.end.y - 1), 2)
		for y: int in range(rect.position.y, rect.end.y):
			_add_wall_side(walls, openings, owner_of, doors, index, Vector2i(rect.position.x, y), 3)
			_add_wall_side(walls, openings, owner_of, doors, index, Vector2i(rect.end.x - 1, y), 1)
	# A divisa entre dois quartos e visitada pelos dois, e o vao da porta
	# tambem: sem deduplicar, cada parede interna e cada porta entram duas vezes.
	return {"walls": _unique_sides(walls), "openings": _unique_sides(openings)}


## Tira lado repetido mantendo a ordem. Uso: interno do draft_interior.
static func _unique_sides(sides: Array[Dictionary]) -> Array[Dictionary]:
	var seen := {}
	var unique: Array[Dictionary] = []
	for side in sides:
		var key := "%s/%d" % [side["cell"], side["side"]]
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(side)
	return unique


## Guarda o lado da celula como parede (divisa com outro quarto ou borda) ou
## como vao, quando a porta cai ali. Uso: interno do draft_interior.
static func _add_wall_side(walls: Array[Dictionary], openings: Array[Dictionary], owner_of: Dictionary, doors: Dictionary, room_index: int, cell: Vector2i, side: int) -> void:
	var neighbor := cell + SIDE_OFFSETS[side]
	var outside := not owner_of.has(neighbor)
	var other_room := not outside and int(owner_of[neighbor]) != room_index
	if not outside and not other_room:
		return
	# Canonicaliza a divisa interna: parede a leste vira "oeste do vizinho" e a
	# sul vira "norte do vizinho", entao a mesma divisa tem uma representacao so,
	# venha do quarto de cima ou do de baixo. Na borda externa (sem vizinho) a
	# parede fica na celula de dentro.
	var entry_cell := cell
	var entry_side := side
	if other_room and side == 1:
		entry_cell = neighbor
		entry_side = 3
	elif other_room and side == 2:
		entry_cell = neighbor
		entry_side = 0
	var entry := {"cell": entry_cell, "side": entry_side}
	# A porta da planta guarda a celula de cima/esquerda da divisa, que e
	# exatamente a celula canonica da parede - por isso o teste e na celula
	# canonica, e nao na original (era o que fazia a porta virar parede).
	if doors.has(entry_cell):
		openings.append(entry)
	else:
		walls.append(entry)


## Embaralha com o rng da planta (Array.shuffle usa o global, que nao e
## reproduzivel por seed). Uso: interno.
static func _deterministic_shuffle(source: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var copy: Array[Dictionary] = source.duplicate()
	for index in range(copy.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary: Dictionary = copy[index]
		copy[index] = copy[swap_index]
		copy[swap_index] = temporary
	return copy
