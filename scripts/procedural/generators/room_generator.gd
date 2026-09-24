# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ProceduralRoomGenerator
extends RefCounted

const ROOM_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/room_blueprint.gd")
const UNIT_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/unit_blueprint.gd")
const FLOOR_PLAN: GDScript = preload("res://scripts/floor_plan_generator.gd")

## Liga o layout procedural (floor_plan_generator: treemap + arvore de portas) no
## lugar das duas plantas fixas. Ligado: casas e apartamentos variam por seed. O
## mobiliario (cama/balcao/banheiro/sala) escolhe canto/parede livre de porta,
## entao a planta passa nos testes de layout. Desligue para voltar as duas
## plantas fixas (fallback).
static var use_plan_layout := true

## Nome do quarto na planta -> tipo de comodo que o mobiliario conhece.
const PLAN_ROOM_TYPES := {
	"SALA": "living_room",
	"COZINHA": "kitchen",
	"QUARTO": "bedroom",
	"BANHEIRO": "bathroom",
	"CORREDOR": "corridor",
	"DESPENSA": "storage",
}
## Largura base do vao de porta da planta (m), antes do scale_layout. A planta
## so garante MIN_DOOR_EDGE celulas de divisa; 2 m e o minimo para o boneco.
const PLAN_DOOR_WIDTH := 2.0
## Recuo do vao em relacao as pontas da divisa: a parede perpendicular que
## encosta na divisa tem meia-espessura (WALL_THICKNESS/2 = 0.06) e invadiria o
## vao se a porta comecasse exatamente na ponta.
const PLAN_DOOR_INSET := 0.05
## Apartamento compacto dos predios: 4 unidades por andar num corredor central.
const COMPACT_UNIT_SIZE := Vector2(6.0, 7.0)


static func generate_apartment(apartment_seed: int, variant: int):
	if use_plan_layout:
		return generate_apartment_from_plan(apartment_seed, 10.0, 8.0)
	var unit = UNIT_BLUEPRINT.new("Apartment_%d" % (variant + 1), 10.0, 8.0)
	if variant % 2 == 0:
		_add_standard_layout(unit)
	else:
		_add_compact_layout(unit)
	_add_windows(unit)
	return unit


## Apartamento com planta procedural (1 celula = 1 m na planta base 10x8): o
## treemap distribui os comodos e a arvore de portas garante que todos sejam
## alcancaveis. Com `include_utility` entra uma DESPENSA e sala/despensa sao
## empurradas para a borda, para a casa ter entrada principal (sala) e de
## servico (despensa). `entrance_edge` forca a sala para a borda por onde o
## apartamento e acessado. Uso:
##   var unit = ProceduralRoomGenerator.generate_apartment_from_plan(seed, 15.0, 12.0, true)
static func generate_apartment_from_plan(apartment_seed: int, width: float, depth: float, include_utility: bool = false, entrance_edge: String = ""):
	var unit = UNIT_BLUEPRINT.new("ApartmentPlan_A", width, depth)
	var program: Array[Dictionary] = FLOOR_PLAN.program_for_seed(apartment_seed, width * depth, include_utility)
	var plan: Dictionary = FLOOR_PLAN.generate(int(round(width)), int(round(depth)), apartment_seed, program)
	var plan_rooms: Array = plan["rooms"]
	var room_ids: Array[String] = []
	for index in plan_rooms.size():
		var room: Dictionary = plan_rooms[index]
		var rect: Rect2i = room["rect"]
		var room_id := "%s_%d" % [String(room["name"]).to_lower(), index]
		room_ids.append(room_id)
		var room_type := String(PLAN_ROOM_TYPES.get(String(room["name"]), "living_room"))
		unit.add_room(ROOM_BLUEPRINT.new(room_id, room_type, Rect2(Vector2(rect.position), Vector2(rect.size))))
	if include_utility:
		# Entrada principal (sala) e de servico (despensa) precisam de parede
		# externa; se o treemap jogou os dois pro miolo, troca o tipo com um
		# comodo de borda.
		var sala_id := _force_type_to_edge(unit, "living_room", ["top", "bottom", "left", "right"], [], false)
		_force_type_to_edge(unit, "storage", ["bottom", "left", "right", "top"], [sala_id], true)
	if not entrance_edge.is_empty():
		_force_type_to_edge(unit, "living_room", [entrance_edge], [], false)
	for door in plan["doors"]:
		var first_index := int(door["a"])
		var second_index := int(door["b"])
		var placement := _plan_door_placement(plan_rooms, first_index, second_index)
		if placement.is_empty():
			push_error("Porta da planta entre quartos %d e %d sem divisa valida; esperado parede comum." % [first_index, second_index])
			continue
		unit.add_door({
			"room_a": room_ids[first_index],
			"room_b": room_ids[second_index],
			"axis": placement["axis"],
			"center": placement["center"],
			"width": placement["width"],
		})
	_add_windows(unit)
	return unit


## Garante que exista um comodo do tipo tocando uma parede externa, para receber
## porta de entrada. Se o tipo estiver no miolo, troca o tipo com um comodo de
## borda disponivel (o maior, ou o menor com `prefer_smallest`). Devolve o id do
## comodo ("" se nao houver borda). Uso: interno do generate_apartment_from_plan.
static func _force_type_to_edge(unit, wanted_type: String, edge_order: Array[String], avoid_ids: Array[String], prefer_smallest: bool) -> String:
	for room in unit.rooms:
		if room.room_type == wanted_type and _touches_edge(unit, room, edge_order):
			return room.id
	for edge in edge_order:
		var target = _edge_room(unit, edge, avoid_ids, prefer_smallest)
		if target != null:
			_swap_room_type(unit, wanted_type, target)
			return target.id
	return ""


## Comodo encostado numa borda, fora dos reservados: o maior ou o menor. Uso: interno.
static func _edge_room(unit, edge: String, avoid_ids: Array[String], prefer_smallest: bool):
	var target = null
	for room in unit.rooms:
		if avoid_ids.has(room.id) or not _touches_edge(unit, room, [edge]):
			continue
		if target == null:
			target = room
			continue
		var area: float = room.bounds.get_area()
		var target_area: float = target.bounds.get_area()
		if (prefer_smallest and area < target_area) or (not prefer_smallest and area > target_area):
			target = room
	return target


## Troca o tipo entre o comodo do tipo desejado e o alvo. Uso: interno.
static func _swap_room_type(unit, wanted_type: String, target) -> void:
	for room in unit.rooms:
		if room.room_type == wanted_type:
			room.room_type = target.room_type
			break
	target.room_type = wanted_type


## O comodo encosta em alguma das bordas listadas? Uso: interno.
static func _touches_edge(unit, room, edge_order: Array[String]) -> bool:
	var bounds: Rect2 = room.bounds
	for edge in edge_order:
		if edge == "top" and is_zero_approx(bounds.position.y):
			return true
		if edge == "bottom" and is_equal_approx(bounds.end.y, unit.depth):
			return true
		if edge == "left" and is_zero_approx(bounds.position.x):
			return true
		if edge == "right" and is_equal_approx(bounds.end.x, unit.width):
			return true
	return false


## Traduz a divisa entre dois quartos da planta em eixo, centro e largura de
## porta no espaco do blueprint. Uso: interno do generate_apartment_from_plan.
static func _plan_door_placement(rooms: Array, first_index: int, second_index: int) -> Dictionary:
	var first: Rect2i = rooms[first_index]["rect"]
	var second: Rect2i = rooms[second_index]["rect"]
	if first.end.x == second.position.x or second.end.x == first.position.x:
		var boundary_x := float(first.end.x) if second.position.x == first.end.x else float(second.end.x)
		var top := maxi(first.position.y, second.position.y)
		var bottom := mini(first.end.y, second.end.y)
		var overlap := float(bottom - top)
		if overlap <= 0.0:
			return {}
		return {"axis": "vertical", "center": Vector2(boundary_x, float(top) + overlap * 0.5), "width": minf(PLAN_DOOR_WIDTH, overlap - PLAN_DOOR_INSET * 2.0)}
	if first.end.y == second.position.y or second.end.y == first.position.y:
		var boundary_y := float(first.end.y) if second.position.y == first.end.y else float(second.end.y)
		var left := maxi(first.position.x, second.position.x)
		var right := mini(first.end.x, second.end.x)
		var overlap := float(right - left)
		if overlap <= 0.0:
			return {}
		return {"axis": "horizontal", "center": Vector2(float(left) + overlap * 0.5, boundary_y), "width": minf(PLAN_DOOR_WIDTH, overlap - PLAN_DOOR_INSET * 2.0)}
	return {}


## Terreo do predio: recepcao na frente (com a entrada), lixo e estoque no
## fundo e nucleo da escada numa faixa lateral de ponta a ponta. O nucleo ocupa
## o mesmo retangulo em todos os andares para que nenhuma parede de apartamento
## atravesse os lances. A porta do nucleo fica no patamar da frente
## (`core_entrance_z`), fora dos lances. O lixo tem porta de servico nos fundos
## (coleta). Uso:
##   var lobby = ProceduralRoomGenerator.generate_lobby(seed, 20.0, 16.0, Rect2(12, 0, 8, 16), 3.0, 2.0)
static func generate_lobby(_lobby_seed: int, width: float, depth: float, stair_core: Rect2, core_entrance_z: float, door_width: float):
	var lobby = UNIT_BLUEPRINT.new("Lobby_A", width, depth)
	var hall_depth := depth * 0.5
	var back_width := stair_core.position.x * 0.5
	var back_depth := depth - hall_depth
	lobby.add_room(ROOM_BLUEPRINT.new("reception", "reception", Rect2(0.0, 0.0, stair_core.position.x, hall_depth)))
	lobby.add_room(ROOM_BLUEPRINT.new("trash_room", "trash_room", Rect2(0.0, hall_depth, back_width, back_depth)))
	lobby.add_room(ROOM_BLUEPRINT.new("storage", "storage", Rect2(back_width, hall_depth, back_width, back_depth)))
	lobby.add_room(ROOM_BLUEPRINT.new("stair_core", "stairs", stair_core))
	_add_door(lobby, "reception", "stair_core", "vertical", Vector2(stair_core.position.x, core_entrance_z), door_width)
	_add_door(lobby, "reception", "trash_room", "horizontal", Vector2(back_width * 0.5, hall_depth), door_width)
	_add_door(lobby, "reception", "storage", "horizontal", Vector2(back_width * 1.5, hall_depth), door_width)
	_add_door(lobby, "reception", "outside", "horizontal", Vector2(stair_core.position.x * 0.5, 0.0), door_width)
	_add_door(lobby, "trash_room", "outside", "horizontal", Vector2(back_width * 0.5, depth), door_width)
	return lobby


## Apartamento compacto de 6 x 6.5 m para 4 unidades por andar: sala (com a
## entrada), quarto e banheiro. `entrance_side` diz de que lado fica o
## corredor: "bottom" poe a sala em cima do corredor de baixo, "top" espelha.
## Uso: var apt := ProceduralRoomGenerator.generate_apartment_unit(seed, "bottom")
static func generate_apartment_unit(_unit_seed: int, entrance_side: String):
	var unit = UNIT_BLUEPRINT.new("ApartmentUnit_A", COMPACT_UNIT_SIZE.x, COMPACT_UNIT_SIZE.y)
	var living_at_bottom := entrance_side == "bottom"
	var living_depth := 4.0
	var back_depth := COMPACT_UNIT_SIZE.y - living_depth
	if living_at_bottom:
		unit.add_room(ROOM_BLUEPRINT.new("bedroom", "bedroom", Rect2(0.0, 0.0, 3.0, back_depth)))
		unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(3.0, 0.0, 3.0, back_depth)))
		unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, back_depth, 6.0, living_depth)))
		_add_door(unit, "living", "bedroom", "horizontal", Vector2(1.5, back_depth), 1.9)
		_add_door(unit, "living", "bathroom", "horizontal", Vector2(4.5, back_depth), 1.9)
	else:
		unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, 0.0, 6.0, living_depth)))
		unit.add_room(ROOM_BLUEPRINT.new("bedroom", "bedroom", Rect2(0.0, living_depth, 3.0, back_depth)))
		unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(3.0, living_depth, 3.0, back_depth)))
		_add_door(unit, "living", "bedroom", "horizontal", Vector2(1.5, living_depth), 1.9)
		_add_door(unit, "living", "bathroom", "horizontal", Vector2(4.5, living_depth), 1.9)
	return unit


## Corredor que distribui os 4 apartamentos do andar, ligado ao nucleo da
## escada. Uso: var hall := ProceduralRoomGenerator.generate_corridor(12.0, 3.0)
static func generate_corridor(width: float, depth: float):
	var corridor = UNIT_BLUEPRINT.new("Corridor_A", width, depth)
	corridor.add_room(ROOM_BLUEPRINT.new("corridor", "corridor", Rect2(0.0, 0.0, width, depth)))
	return corridor


## Nucleo da escada dos andares superiores: um unico comodo livre de paredes.
## Uso: var core = ProceduralRoomGenerator.generate_stair_core(Vector2(10.0, 8.0))
static func generate_stair_core(size: Vector2):
	var core = UNIT_BLUEPRINT.new("StairCore_A", size.x, size.y)
	core.add_room(ROOM_BLUEPRINT.new("stair_core", "stairs", Rect2(Vector2.ZERO, size)))
	return core


## Planta de comercio com variacao por seed: entrada deslocada na fachada,
## escritorio trocando de lado e profundidade do estoque variavel. Segue os
## principios de varejo (zona de descompressao livre na entrada, caixa visivel
## fora do eixo da porta, estoque/escritorio como apoio no fundo). Devolve
## tambem os retangulos das salas dos fundos, usados pelo assembler.
## Uso: var layout := ProceduralRoomGenerator.store_layout_for_seed(seed, 18.0, 14.0)
static func store_layout_for_seed(store_seed: int, width: float, depth: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = store_seed
	var entrance_ratios: Array[float] = [0.28, 0.5, 0.72]
	var entrance_x := width * entrance_ratios[rng.randi_range(0, entrance_ratios.size() - 1)]
	# Frente de vendas ocupa a maior parte; estoque/escritorio ficam no fundo.
	var sales_depth := depth * rng.randf_range(0.62, 0.74)
	var stock_width := width * rng.randf_range(0.55, 0.72)
	var office_on_left := rng.randf() < 0.5
	var back_height := depth - sales_depth
	var office_rect := Rect2(0.0, sales_depth, width - stock_width, back_height) if office_on_left else Rect2(stock_width, sales_depth, width - stock_width, back_height)
	var stock_rect := Rect2(width - stock_width, sales_depth, stock_width, back_height) if office_on_left else Rect2(0.0, sales_depth, stock_width, back_height)
	return {
		"entrance_x": entrance_x,
		"sales_depth": sales_depth,
		"office_on_left": office_on_left,
		"office_rect": office_rect,
		"stock_rect": stock_rect,
	}


## Loja/mercado/loja de armas: frente de vendas, estoque e escritorio no fundo.
## A entrada fica deslocada na fachada e o estoque tem porta de servico nos
## fundos (carga/descarga). Uso:
##   var store := ProceduralRoomGenerator.generate_store(seed, 18.0, 14.0)
static func generate_store(store_seed: int, width: float, depth: float, layout: Dictionary = {}):
	if layout.is_empty():
		layout = store_layout_for_seed(store_seed, width, depth)
	var store = UNIT_BLUEPRINT.new("ShopUnit_A", width, depth)
	var sales_depth: float = layout["sales_depth"]
	var stock_rect: Rect2 = layout["stock_rect"]
	var office_rect: Rect2 = layout["office_rect"]
	store.add_room(ROOM_BLUEPRINT.new("sales", "sales_floor", Rect2(0.0, 0.0, width, sales_depth)))
	store.add_room(ROOM_BLUEPRINT.new("stockroom", "stockroom", stock_rect))
	store.add_room(ROOM_BLUEPRINT.new("office", "office", office_rect))
	_add_door(store, "sales", "stockroom", "horizontal", Vector2(stock_rect.position.x + stock_rect.size.x * 0.5, sales_depth), 1.4)
	_add_door(store, "sales", "office", "horizontal", Vector2(office_rect.position.x + office_rect.size.x * 0.5, sales_depth), 1.4)
	_add_door(store, "sales", "outside", "horizontal", Vector2(float(layout["entrance_x"]), 0.0), 1.8)
	_add_door(store, "stockroom", "outside", "horizontal", Vector2(stock_rect.position.x + stock_rect.size.x * 0.5, depth), 1.4)
	_add_windows(store)
	return store


## Sala e cozinha distribuem a casa: o quarto do fundo nao depende mais de
## passar pelo banheiro (a cama do quarto A ocupa a parede do banheiro).
static func _add_standard_layout(unit) -> void:
	unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, 0.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("kitchen", "kitchen", Rect2(5.0, 0.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_a", "bedroom", Rect2(0.0, 4.0, 5.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(5.0, 4.0, 2.5, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_b", "bedroom", Rect2(7.5, 4.0, 2.5, 4.0)))
	_add_door(unit, "living", "kitchen", "vertical", Vector2(5.0, 2.0), 1.4)
	_add_door(unit, "living", "bedroom_a", "horizontal", Vector2(2.5, 4.0), 1.4)
	_add_door(unit, "kitchen", "bathroom", "horizontal", Vector2(6.25, 4.0), 1.4)
	_add_door(unit, "kitchen", "bedroom_b", "horizontal", Vector2(8.75, 4.0), 1.4)


## Corredor largo (2.5 m na planta base) ligado a cozinha e ao quarto A; o
## banheiro e suite do quarto B e tambem abre para a cozinha.
static func _add_compact_layout(unit) -> void:
	unit.add_room(ROOM_BLUEPRINT.new("living", "living_room", Rect2(0.0, 0.0, 4.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("kitchen", "kitchen", Rect2(4.0, 0.0, 3.0, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bathroom", "bathroom", Rect2(7.0, 0.0, 3.0, 3.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_a", "bedroom", Rect2(0.0, 4.0, 4.5, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("corridor", "corridor", Rect2(4.5, 4.0, 2.5, 4.0)))
	unit.add_room(ROOM_BLUEPRINT.new("bedroom_b", "bedroom", Rect2(7.0, 3.0, 3.0, 5.0)))
	_add_door(unit, "living", "kitchen", "vertical", Vector2(4.0, 2.0), 1.4)
	_add_door(unit, "kitchen", "bathroom", "vertical", Vector2(7.0, 1.5), 1.4)
	_add_door(unit, "living", "bedroom_a", "horizontal", Vector2(2.0, 4.0), 1.4)
	_add_door(unit, "kitchen", "corridor", "horizontal", Vector2(5.75, 4.0), 1.4)
	_add_door(unit, "bedroom_a", "corridor", "vertical", Vector2(4.5, 6.0), 1.4)
	_add_door(unit, "corridor", "bedroom_b", "vertical", Vector2(7.0, 6.0), 1.4)
	_add_door(unit, "bedroom_b", "bathroom", "horizontal", Vector2(8.5, 3.0), 1.4)


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
