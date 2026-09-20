class_name ProceduralBuildingAssembler
extends RefCounted

const WALL_HEIGHT := 3.2
const WALL_THICKNESS := 0.12
const DOOR_HEIGHT := 2.75
const WINDOW_SILL := 1.05
const WINDOW_HEIGHT := 0.9
const WINDOW_FRAME_THICKNESS := 0.08
const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const HOUSE_ROOF_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/house_roof_assembler.gd")
## Meta do corpo estatico com os filhos de luz cacheados (G7-fase1).
const LIGHT_CACHE_META := "light_cache"
const ROOF_TERRACE_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/roof_terrace_assembler.gd")
const STAIR_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/stair_assembler.gd")
const BUILDING_NAVIGATION_SCRIPT: GDScript = preload("res://scripts/procedural/navigation/building_navigation.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")
const DESTRUCTIBLE_DOOR_SCRIPT: GDScript = preload("res://scripts/destructible_door.gd")
const COMMERCIAL_DETAIL_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/commercial_detail_assembler.gd")
const APARTMENT_DETAIL_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/apartment_detail_assembler.gd")
const WAVE_SUPPLY_SCENE: PackedScene = preload("res://scenes/wave_supply_pickup.tscn")
# Moveis acompanham o tamanho do boneco (2.34 m) e a planta ampliada das casas.
const FURNITURE_SCALE := 1.3
## Largura do boneco: o mobiliario nao pode invadir o vao mais meio boneco de
## cada lado (mesmo criterio do test_apartment_layout).
const PLAYER_BODY_WIDTH := 1.16
const WOOD := 0
const DARK_WOOD := 1
const FABRIC := 2
const CERAMIC := 3
const METAL := 4
const GLASS := 5


static func assemble(building) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = building.archetype
	var facade_color := _facade_color(building.seed)
	var wall_material: Material = BUILDING_MATERIALS.opaque(facade_color, building.floor_height)
	var floor_material: Material = BUILDING_MATERIALS.opaque(Color(0.27, 0.29, 0.31), building.floor_height, true)
	var trim_material: Material = BUILDING_MATERIALS.opaque(facade_color.darkened(0.45), building.floor_height)
	var ceiling_material: Material = BUILDING_MATERIALS.opaque(facade_color.darkened(0.45), building.floor_height, true)
	var furniture_materials: Array[Material] = []
	if building.archetype.begins_with("House") or building.archetype.begins_with("ApartmentBuilding"):
		furniture_materials = _furniture_materials(building.seed)
	var apartment_living: bool = building.archetype.begins_with("ApartmentBuilding")
	for floor_blueprint in building.floor_blueprints:
		var floor_y: float = float(floor_blueprint.floor_index) * building.floor_height
		STAIR_ASSEMBLER.add_floor_slab(body, building, floor_blueprint.floor_index, floor_y, floor_material)
		for placement in floor_blueprint.units:
			_draw_unit(body, placement["blueprint"], placement["position"], floor_y + 0.08, wall_material, trim_material, furniture_materials, apartment_living)
	STAIR_ASSEMBLER.add_flights(body, building)
	if building.archetype.begins_with("ApartmentBuilding"):
		APARTMENT_DETAIL_ASSEMBLER.add_details(body, building)
	if building.archetype.begins_with("House"):
		_add_house_air_conditioners(body, building)
		HOUSE_ROOF_ASSEMBLER.add_gable_roof(body, building, wall_material)
	elif building.has_roof_terrace:
		ROOF_TERRACE_ASSEMBLER.add_terrace(body, building, floor_material, wall_material)
	else:
		BOX_BUILDER.add_box(body, "Roof", Vector3(building.width, 0.18, building.depth), Vector3(building.width * 0.5, building.floors * building.floor_height, building.depth * 0.5), ceiling_material, true)
	if building.archetype == "Shop_A" or building.archetype == "Grocery_A" or building.archetype == "GunShop_A":
		COMMERCIAL_DETAIL_ASSEMBLER.add_details(body, building)
	_add_wave_supply(body, building)
	# Adicionado por ultimo: o navmesh e assado no _ready a partir de todas as colisoes acima.
	var navigation_height: float = building.floors * building.floor_height + (ROOF_TERRACE_ASSEMBLER.NAVIGATION_HEADROOM if building.has_roof_terrace else 0.0)
	body.add_child(BUILDING_NAVIGATION_SCRIPT.new(Vector3(building.width, navigation_height, building.depth)))
	return body


static func _draw_unit(body: StaticBody3D, unit, origin: Vector2, floor_y: float, wall_material: Material, trim_material: Material, furniture_materials: Array[Material], apartment_living: bool = false) -> void:
	for room in unit.rooms:
		_draw_room_walls(body, unit, room, origin, floor_y, wall_material)
		# O piso decorativo cobriria o vao da laje no nucleo da escada.
		if room.room_type == "stairs":
			continue
		var room_center := Vector3(origin.x + room.bounds.position.x + room.bounds.size.x * 0.5, floor_y + 0.07, origin.y + room.bounds.position.y + room.bounds.size.y * 0.5)
		BOX_BUILDER.add_box(body, "Room_%s" % room.id, Vector3(room.bounds.size.x, 0.04, room.bounds.size.y), room_center, trim_material, false)
	for window in unit.windows:
		if not _window_overlaps_door(unit, window):
			_draw_window(body, window, origin, floor_y, trim_material)
	if not furniture_materials.is_empty():
		for room in unit.rooms:
			_draw_room_furniture(body, unit, room, origin, floor_y, furniture_materials, apartment_living)


static func _draw_room_walls(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, wall_material: Material) -> void:
	_draw_wall_edge(body, unit, room, "vertical", room.bounds.position.x, room.bounds.position.y, room.bounds.end.y, origin, floor_y, wall_material)
	_draw_wall_edge(body, unit, room, "horizontal", room.bounds.position.y, room.bounds.position.x, room.bounds.end.x, origin, floor_y, wall_material)
	if is_zero_approx(room.bounds.end.x - unit.width):
		_draw_wall_edge(body, unit, room, "vertical", room.bounds.end.x, room.bounds.position.y, room.bounds.end.y, origin, floor_y, wall_material)
	if is_zero_approx(room.bounds.end.y - unit.depth):
		_draw_wall_edge(body, unit, room, "horizontal", room.bounds.end.y, room.bounds.position.x, room.bounds.end.x, origin, floor_y, wall_material)


## Nome deterministico e valido (sem ponto) da porta de um vao, em coordenadas
## do edificio. Unidades vizinhas que desenham a mesma parede geram o mesmo nome,
## entao a porta e criada uma unica vez; o grafo de navegacao usa o mesmo nome.
## Uso: var door_name := ProceduralBuildingAssembler.door_node_name("vertical", Vector2(10, 10), 3.48)
static func door_node_name(axis: String, building_center: Vector2, floor_y: float) -> String:
	return "Door_%s_%d_%d_%d" % [axis.substr(0, 1), roundi(building_center.x * 10.0), roundi(building_center.y * 10.0), roundi(floor_y * 10.0)]


static func _window_overlaps_door(unit, window: Dictionary) -> bool:
	var window_center: Vector2 = window["center"]
	var window_axis: String = window["axis"]
	var window_along: float = window_center.y if window_axis == "vertical" else window_center.x
	var window_line: float = window_center.x if window_axis == "vertical" else window_center.y
	var window_start: float = window_along - float(window["width"]) * 0.5
	var window_end: float = window_along + float(window["width"]) * 0.5
	for door in unit.doors:
		if door.get("axis", "") != window_axis:
			continue
		var door_center: Vector2 = door["center"]
		var door_line: float = door_center.x if window_axis == "vertical" else door_center.y
		if not is_equal_approx(door_line, window_line):
			continue
		var door_along: float = door_center.y if window_axis == "vertical" else door_center.x
		var door_start: float = door_along - float(door["width"]) * 0.5
		var door_end: float = door_along + float(door["width"]) * 0.5
		if window_start < door_end and door_start < window_end:
			return true
	return false


static func _draw_wall_edge(body: StaticBody3D, unit, room, axis: String, line: float, start: float, finish: float, origin: Vector2, floor_y: float, material: Material) -> void:
	var openings: Array[Dictionary] = []
	var door_ranges: Array[Vector2] = []
	for door in unit.doors:
		if door.get("axis", "") != axis:
			continue
		var center: Vector2 = door["center"]
		var door_line := center.x if axis == "vertical" else center.y
		if not is_equal_approx(door_line, line):
			continue
		var along := center.y if axis == "vertical" else center.x
		var half_width := float(door["width"]) * 0.5
		if along + half_width <= start or along - half_width >= finish:
			continue
		door_ranges.append(Vector2(along - half_width, along + half_width))
		openings.append({
			"start": along - half_width,
			"end": along + half_width,
			"bottom": 0.0,
			"top": DOOR_HEIGHT,
			"fill_top": false,
		})
		# Cada vao recebe porta e batente uma unica vez, mesmo que a mesma
		# linha de parede seja desenhada por salas ou unidades vizinhas.
		var door_name := door_node_name(axis, origin + center, floor_y)
		if not body.has_node(door_name):
			_add_door(body, door, axis, line, along, origin, floor_y, material, door_name)
		var header_name := door_name.replace("Door_", "DoorHeader_")
		if not body.has_node(header_name):
			_add_door_header(body, door, axis, line, along, origin, floor_y, material, header_name)
	for window in unit.windows:
		if window.get("axis", "") != axis:
			continue
		var window_center: Vector2 = window["center"]
		var window_line := window_center.x if axis == "vertical" else window_center.y
		if not is_equal_approx(window_line, line):
			continue
		var window_along := window_center.y if axis == "vertical" else window_center.x
		var window_half_width := float(window["width"]) * 0.5
		var window_start := window_along - window_half_width
		var window_end := window_along + window_half_width
		if window_end <= start or window_start >= finish:
			continue
		# Janela sobreposta por porta deixaria parede dentro do vao da porta.
		var overlaps_door := false
		for door_range in door_ranges:
			if window_start < door_range.y and door_range.x < window_end:
				overlaps_door = true
				break
		if overlaps_door:
			continue
		openings.append({
			"start": window_start,
			"end": window_end,
			"bottom": WINDOW_SILL,
			"top": WINDOW_SILL + WINDOW_HEIGHT,
			"fill_top": true,
		})
	openings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left["start"] < right["start"])
	var cursor := start
	for opening in openings:
		var opening_start: float = maxf(float(opening["start"]), start)
		var opening_end: float = minf(float(opening["end"]), finish)
		_add_wall_panel(body, axis, line, cursor, minf(opening_start, finish), 0.0, WALL_HEIGHT, origin, floor_y, material)
		if float(opening["bottom"]) > 0.0:
			_add_wall_panel(body, axis, line, opening_start, opening_end, 0.0, float(opening["bottom"]), origin, floor_y, material)
		if bool(opening["fill_top"]) and float(opening["top"]) < WALL_HEIGHT:
			_add_wall_panel(body, axis, line, opening_start, opening_end, float(opening["top"]), WALL_HEIGHT, origin, floor_y, material)
		cursor = maxf(cursor, float(opening["end"]))
	_add_wall_panel(body, axis, line, cursor, finish, 0.0, WALL_HEIGHT, origin, floor_y, material)


static func _add_door(body: StaticBody3D, door_data: Dictionary, axis: String, line: float, along: float, origin: Vector2, floor_y: float, _material: Material, door_name: String) -> void:
	var door = DESTRUCTIBLE_DOOR_SCRIPT.new()
	door.name = door_name
	var width := float(door_data.get("width", 1.4))
	var size := Vector3(WALL_THICKNESS, DOOR_HEIGHT, width) if axis == "vertical" else Vector3(width, DOOR_HEIGHT, WALL_THICKNESS)
	var swing_direction := float(door_data.get("swing_direction", 0.0))
	door.configure(size, BUILDING_MATERIALS.opaque(Color(0.24, 0.12, 0.055), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT), swing_direction)
	door.position = Vector3(origin.x + line, floor_y, origin.y + along - width * 0.5) if axis == "vertical" else Vector3(origin.x + along - width * 0.5, floor_y, origin.y + line)
	body.add_child(door)


static func _add_door_header(body: StaticBody3D, door_data: Dictionary, axis: String, line: float, along: float, origin: Vector2, floor_y: float, material: Material, header_name: String) -> void:
	var width := float(door_data.get("width", 1.4))
	var header_height := WALL_HEIGHT - DOOR_HEIGHT
	var size := Vector3(WALL_THICKNESS, header_height, width) if axis == "vertical" else Vector3(width, header_height, WALL_THICKNESS)
	var position := Vector3(origin.x + line, floor_y + DOOR_HEIGHT + header_height * 0.5, origin.y + along) if axis == "vertical" else Vector3(origin.x + along, floor_y + DOOR_HEIGHT + header_height * 0.5, origin.y + line)
	BOX_BUILDER.add_box(body, header_name, size, position, material, true)


static func _add_wall_panel(body: StaticBody3D, axis: String, line: float, start: float, finish: float, y_bottom: float, y_top: float, origin: Vector2, floor_y: float, material: Material) -> void:
	if finish - start <= 0.05 or y_top - y_bottom <= 0.05:
		return
	var center: Vector3
	var size: Vector3
	var center_y := floor_y + (y_bottom + y_top) * 0.5
	var height := y_top - y_bottom
	if axis == "vertical":
		center = Vector3(origin.x + line, center_y, origin.y + (start + finish) * 0.5)
		size = Vector3(WALL_THICKNESS, height, finish - start)
	else:
		center = Vector3(origin.x + (start + finish) * 0.5, center_y, origin.y + line)
		size = Vector3(finish - start, height, WALL_THICKNESS)
	BOX_BUILDER.add_box(body, "Wall", size, center, material, true)


static func _draw_window(body: StaticBody3D, window: Dictionary, origin: Vector2, floor_y: float, material: Material) -> void:
	var center: Vector2 = window["center"]
	var axis: String = window["axis"]
	var width := float(window["width"])
	var center_y := floor_y + WINDOW_SILL + WINDOW_HEIGHT * 0.5
	var position := Vector3(origin.x + center.x, center_y, origin.y + center.y)
	var frame_material := material
	var glass_material: Material = BUILDING_MATERIALS.glass(BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT)
	var glass_size := Vector3(width - WINDOW_FRAME_THICKNESS * 2.0, WINDOW_HEIGHT - WINDOW_FRAME_THICKNESS * 2.0, 0.05)
	if axis == "vertical":
		glass_size = Vector3(0.05, WINDOW_HEIGHT - WINDOW_FRAME_THICKNESS * 2.0, width - WINDOW_FRAME_THICKNESS * 2.0)
	BOX_BUILDER.add_box(body, "WindowGlass_%s" % window["room_id"], glass_size, position, glass_material, false)
	BOX_BUILDER.add_box(body, "WindowSill_%s" % window["room_id"], _window_frame_size(axis, width, WINDOW_FRAME_THICKNESS), position + Vector3(0.0, -WINDOW_HEIGHT * 0.5, 0.0), frame_material, true)
	BOX_BUILDER.add_box(body, "WindowLintel_%s" % window["room_id"], _window_frame_size(axis, width, WINDOW_FRAME_THICKNESS), position + Vector3(0.0, WINDOW_HEIGHT * 0.5, 0.0), frame_material, true)


static func _window_frame_size(axis: String, width: float, thickness: float) -> Vector3:
	if axis == "vertical":
		return Vector3(WALL_THICKNESS * 1.2, thickness, width)
	return Vector3(width, thickness, WALL_THICKNESS * 1.2)


static func _draw_room_furniture(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material], apartment_living: bool = false) -> void:
	match room.room_type:
		"living_room":
			if apartment_living:
				_place_apartment_living(body, unit, room, origin, floor_y, materials)
			else:
				_place_living(body, unit, room, origin, floor_y, materials)
		"kitchen":
			_place_kitchen(body, unit, room, origin, floor_y, materials)
		"bathroom":
			_place_bathroom(body, unit, room, origin, floor_y, materials)
		"bedroom":
			_place_bedroom(body, unit, room, origin, floor_y, materials)


## Cama e guarda-roupa no canto do quarto mais longe das portas: com a planta
## procedural a porta pode cair na parede onde o movel encostava (a cama tem
## 1.8 m de fundo e atravessava o vao). Tenta os 4 cantos e so cai no primeiro
## cujo movel nao invade a aproximacao de nenhuma porta. Uso: interno.
static func _place_bedroom(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var scaled := bounds.size / FURNITURE_SCALE
	var bed_width := minf(1.15, scaled.x - 0.35)
	var bed_depth := minf(1.8, scaled.y * 0.48)
	var margin := 0.14
	var corners: Array[Vector2] = [
		Vector2(bounds.position.x, bounds.position.y),
		Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y),
		Vector2(bounds.end.x, bounds.end.y),
	]
	var inward: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]
	var bed_corner := -1
	for index in corners.size():
		var anchor := Vector3(corners[index].x + origin.x, floor_y, corners[index].y + origin.y)
		var offset := Vector3(inward[index].x * (scaled.x - bed_width * 0.5 - margin), 0.28, inward[index].y * (scaled.y - bed_depth * 0.5 - margin))
		var center := Vector2(anchor.x + offset.x * FURNITURE_SCALE, anchor.z + offset.z * FURNITURE_SCALE)
		if not _furniture_clear(unit, origin, center, Vector2(bed_width, bed_depth) * FURNITURE_SCALE):
			continue
		_add_furniture(body, "FurnitureBed_%s" % room.id, Vector3(bed_width, 0.48, bed_depth), anchor, offset, materials[FABRIC], true)
		_add_furniture(body, "FurniturePillow_%s" % room.id, Vector3(bed_width * 0.72, 0.14, 0.38), anchor, offset + Vector3(0.0, 0.3, -bed_depth * 0.3), materials[CERAMIC], false)
		bed_corner = index
		break
	for index in corners.size():
		if index == bed_corner:
			continue
		var anchor := Vector3(corners[index].x + origin.x, floor_y, corners[index].y + origin.y)
		var offset := Vector3(inward[index].x * 0.36, 0.9, inward[index].y * 0.55)
		var center := Vector2(anchor.x + offset.x * FURNITURE_SCALE, anchor.z + offset.z * FURNITURE_SCALE)
		if not _furniture_clear(unit, origin, center, Vector2(0.58, 0.82) * FURNITURE_SCALE):
			continue
		_add_furniture(body, "FurnitureWardrobe_%s" % room.id, Vector3(0.58, 1.8, 0.82), anchor, offset, materials[DARK_WOOD], true)
		break
	_place_picture(body, unit, room, origin, floor_y, materials)


## Sala do apartamento: mesa no canto ao lado da porta (fora do eixo de
## passagem). O agente do navmesh tem raio 0.6: mesa no centro da sala fecharia
## o vao da entrada. A cozinha vem do comodo COZINHA da planta. Uso: interno.
static func _place_apartment_living(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var entry_line := _apartment_entry_line(unit, room)
	var toward_center := -1.0 if entry_line > bounds.get_center().y else 1.0
	for side in [1.0, -1.0]:
		var table_x := bounds.position.x + 1.1 if side > 0.0 else bounds.end.x - 1.1
		var table_center := Vector2(origin.x + table_x, origin.y + entry_line + toward_center * 1.5)
		if not _furniture_clear(unit, origin, table_center, Vector2(1.25, 0.75) * FURNITURE_SCALE):
			continue
		var anchor := Vector3(table_center.x, floor_y, table_center.y)
		_add_furniture(body, "FurnitureLivingTable", Vector3(1.25, 0.12, 0.75), anchor, Vector3.UP * 0.72, materials[WOOD], true)
		_add_furniture(body, "FurnitureLivingTableBase", Vector3(0.22, 0.66, 0.22), anchor, Vector3.UP * 0.36, materials[DARK_WOOD], false)
		break
	_add_room_light(body, Vector3(origin.x + bounds.get_center().x, floor_y + 2.35, origin.y + bounds.get_center().y))


## Linha local (y) da parede onde fica a porta de entrada do apartamento.
## Uso: interno do _place_apartment_living.
static func _apartment_entry_line(unit, room) -> float:
	for door in unit.doors:
		if door.get("room_a", "") == room.id and door.get("room_b", "") == "neighbor":
			return (door["center"] as Vector2).y
	return room.bounds.get_center().y


## Mesa da sala no centro (ou encostada numa parede, se o centro estiver na
## aproximacao de uma porta). Uso: interno.
static func _place_living(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var middle := Vector2((bounds.position.x + bounds.end.x) * 0.5, (bounds.position.y + bounds.end.y) * 0.5)
	var candidates: Array[Vector2] = [
		middle,
		Vector2(bounds.position.x + 1.0 * FURNITURE_SCALE, middle.y),
		Vector2(bounds.end.x - 1.0 * FURNITURE_SCALE, middle.y),
	]
	for candidate in candidates:
		var anchor := Vector3(candidate.x + origin.x, floor_y, candidate.y + origin.y)
		var center := anchor + Vector3.UP * 0.72 * FURNITURE_SCALE
		if not _furniture_clear(unit, origin, Vector2(center.x, center.z), Vector2(1.25, 0.75) * FURNITURE_SCALE):
			continue
		_add_furniture(body, "FurnitureLivingTable", Vector3(1.25, 0.12, 0.75), anchor, Vector3.UP * 0.72, materials[WOOD], true)
		_add_furniture(body, "FurnitureLivingTableBase", Vector3(0.22, 0.66, 0.22), anchor, Vector3.UP * 0.36, materials[DARK_WOOD], false)
		break
	_place_picture(body, unit, room, origin, floor_y, materials)
	_add_room_light(body, Vector3(middle.x + origin.x, floor_y + 2.35, middle.y + origin.y))


## Balcao e geladeira numa parede sem porta: tenta as duas paredes verticais e
## as duas pontas, parando na primeira que nao invade vao. Uso: interno.
static func _place_kitchen(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var sides: Array[Dictionary] = [
		{"anchor_x": bounds.end.x, "inward_x": -1.0},
		{"anchor_x": bounds.position.x, "inward_x": 1.0},
	]
	var ends: Array[Dictionary] = [
		{"anchor_z": bounds.position.y, "inward_z": 1.0},
		{"anchor_z": bounds.end.y, "inward_z": -1.0},
	]
	for side in sides:
		for end in ends:
			if _try_place_kitchen(body, unit, origin, floor_y, materials, bounds, side, end):
				return


## Tenta o balcao/geladeira numa combinacao de parede e ponta. Devolve true
## quando colocou. Uso: interno do _place_kitchen.
static func _try_place_kitchen(body: StaticBody3D, unit, origin: Vector2, floor_y: float, materials: Array[Material], bounds: Rect2, side: Dictionary, end: Dictionary) -> bool:
	var sx: float = side["inward_x"]
	var sz: float = end["inward_z"]
	var counter_anchor := Vector3(side["anchor_x"] + origin.x, floor_y, (bounds.position.y + bounds.end.y) * 0.5 + origin.y)
	var fridge_anchor := Vector3(side["anchor_x"] + origin.x, floor_y, end["anchor_z"] + origin.y)
	var counter_offset := Vector3(sx * 0.45, 0.45, 0.0)
	var fridge_offset := Vector3(sx * 0.5, 0.925, sz * 0.5)
	var counter_center := counter_anchor + counter_offset * FURNITURE_SCALE
	var fridge_center := fridge_anchor + fridge_offset * FURNITURE_SCALE
	if not _furniture_clear(unit, origin, Vector2(counter_center.x, counter_center.z), Vector2(0.7, 1.8) * FURNITURE_SCALE):
		return false
	if not _furniture_clear(unit, origin, Vector2(fridge_center.x, fridge_center.z), Vector2(0.78, 0.78) * FURNITURE_SCALE):
		return false
	_add_furniture(body, "FurnitureKitchenCounter", Vector3(0.7, 0.9, 1.8), counter_anchor, counter_offset, materials[DARK_WOOD], true)
	_add_furniture(body, "FurnitureKitchenTop", Vector3(0.76, 0.08, 1.86), counter_anchor, counter_offset + Vector3(0.0, 0.49, 0.0), materials[METAL], false)
	_add_furniture(body, "FurnitureKitchenSink", Vector3(0.42, 0.04, 0.55), counter_anchor, counter_offset + Vector3(0.0, 0.55, 0.38), materials[GLASS], false)
	_add_furniture(body, "FurnitureKitchenStove", Vector3(0.54, 0.06, 0.62), counter_anchor, counter_offset + Vector3(sx * 0.04, 0.55, -0.34), materials[DARK_WOOD], false)
	_add_furniture(body, "FurnitureKitchenFridge", Vector3(0.78, 1.85, 0.78), fridge_anchor, fridge_offset, materials[METAL], true)
	return true


## Quadro simples numa parede sem vao. Nao tem colisao: decora sem reduzir a
## passagem do boneco. Uso: interno da sala e quarto.
static func _place_picture(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var middle := (bounds.position + bounds.end) * 0.5
	var candidates: Array[Dictionary] = [
		{"axis": "horizontal", "line": bounds.position.y, "along": middle.x, "position": Vector3(origin.x + middle.x, floor_y + 1.72, origin.y + bounds.position.y + 0.08), "size": Vector3(0.9, 0.62, 0.04)},
		{"axis": "horizontal", "line": bounds.end.y, "along": middle.x, "position": Vector3(origin.x + middle.x, floor_y + 1.72, origin.y + bounds.end.y - 0.08), "size": Vector3(0.9, 0.62, 0.04)},
		{"axis": "vertical", "line": bounds.position.x, "along": middle.y, "position": Vector3(origin.x + bounds.position.x + 0.08, floor_y + 1.72, origin.y + middle.y), "size": Vector3(0.04, 0.62, 0.9)},
	]
	for candidate in candidates:
		if _wall_segment_has_door(unit, String(candidate["axis"]), float(candidate["line"]), float(candidate["along"]), 0.9):
			continue
		BOX_BUILDER.add_box(body, "FurniturePicture_%s" % room.id, candidate["size"], candidate["position"], materials[FABRIC], false)
		return


## Uma porta ocupa o trecho de parede candidato ao quadro? Uso: interno.
static func _wall_segment_has_door(unit, axis: String, line: float, along: float, width: float) -> bool:
	for door in unit.doors:
		if door.get("axis", "") != axis:
			continue
		var center: Vector2 = door["center"]
		var door_line := center.x if axis == "vertical" else center.y
		if not is_equal_approx(door_line, line):
			continue
		var door_along := center.y if axis == "vertical" else center.x
		if absf(door_along - along) < (float(door["width"]) + width) * 0.5:
			return true
	return false


## Banheiro num canto sem porta: pia/espelho no canto, vaso/chuveiro na parede
## oposta. Tenta os 4 cantos. Uso: interno.
static func _place_bathroom(body: StaticBody3D, unit, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var bounds: Rect2 = room.bounds
	var scaled := bounds.size / FURNITURE_SCALE
	var corners: Array[Vector2] = [
		Vector2(bounds.position.x, bounds.position.y),
		Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y),
		Vector2(bounds.end.x, bounds.end.y),
	]
	var inward: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]
	for index in corners.size():
		if _try_place_bathroom(body, unit, origin, floor_y, materials, corners[index], inward[index], scaled):
			return
	# Quarto pequeno com portas em paredes vizinhas pode nao ter canto livre para
	# o conjunto inteiro. Garante ao menos pia e espelho no primeiro canto (o
	# espelho nao tem colisao, entao nunca trava o vao).
	_place_bathroom_fallback(body, unit, origin, floor_y, materials, corners[0], inward[0])


## Pia (se livre) e espelho (sempre) no canto, ultimo recurso do banheiro.
## Uso: interno do _place_bathroom.
static func _place_bathroom_fallback(body: StaticBody3D, unit, origin: Vector2, floor_y: float, materials: Array[Material], corner: Vector2, inward: Vector2) -> void:
	var anchor := Vector3(corner.x + origin.x, floor_y, corner.y + origin.y)
	var sink_offset := Vector3(inward.x * 0.35, 0.41, inward.y * 0.75)
	var sink_center := anchor + sink_offset * FURNITURE_SCALE
	if _furniture_clear(unit, origin, Vector2(sink_center.x, sink_center.z), Vector2(0.5, 0.58) * FURNITURE_SCALE):
		_add_furniture(body, "FurnitureBathroomSink", Vector3(0.5, 0.82, 0.58), anchor, sink_offset, materials[CERAMIC], true)
	_add_furniture(body, "FurnitureBathroomMirror", Vector3(0.04, 0.72, 0.62), anchor, Vector3(inward.x * 0.07, 1.45, inward.y * 0.75), materials[GLASS], false)


## Monta o conjunto do banheiro no canto se o conjunto inteiro ficar livre de
## vao. Devolve true quando colocou. Uso: interno do _place_bathroom.
static func _try_place_bathroom(body: StaticBody3D, unit, origin: Vector2, floor_y: float, materials: Array[Material], corner: Vector2, inward: Vector2, scaled: Vector2) -> bool:
	var anchor := Vector3(corner.x + origin.x, floor_y, corner.y + origin.y)
	var pieces: Array[Array] = [
		["FurnitureBathroomSink", Vector3(0.5, 0.82, 0.58), Vector3(inward.x * 0.35, 0.41, inward.y * 0.75), materials[CERAMIC], true],
		["FurnitureBathroomMirror", Vector3(0.04, 0.72, 0.62), Vector3(inward.x * 0.07, 1.45, inward.y * 0.75), materials[GLASS], false],
		["FurnitureBathroomToilet", Vector3(0.58, 0.48, 0.72), Vector3(inward.x * 0.4, 0.24, inward.y * (scaled.y - 0.55)), materials[CERAMIC], true],
		["FurnitureBathroomShower", Vector3(0.72, 0.12, 0.82), Vector3(inward.x * (scaled.x - 0.48), 0.06, inward.y * (scaled.y - 0.55)), materials[GLASS], true],
	]
	if not _bathroom_set_clear(unit, origin, anchor, pieces):
		return false
	for piece in pieces:
		_add_furniture(body, piece[0], piece[1], anchor, piece[2], piece[3], piece[4])
	return true


## O conjunto do banheiro inteiro fica livre dos vaos? So as pecas com colisao
## importam: o espelho nao trava ninguem e nao pode derrubar o conjunto. Uso: interno.
static func _bathroom_set_clear(unit, origin: Vector2, anchor: Vector3, pieces: Array[Array]) -> bool:
	for piece in pieces:
		if not bool(piece[4]):
			continue
		var center: Vector3 = anchor + (piece[2] as Vector3) * FURNITURE_SCALE
		var size: Vector3 = (piece[1] as Vector3) * FURNITURE_SCALE
		if not _furniture_clear(unit, origin, Vector2(center.x, center.z), Vector2(size.x, size.z)):
			return false
	return true


## Retangulo de aproximacao do vao (a porta mais meio boneco de cada lado), em
## coordenadas do edificio. Uso: interno do _furniture_clear.
static func _door_approach_rect(door: Dictionary, origin: Vector2) -> Rect2:
	var center: Vector2 = door["center"] + origin
	var width := float(door.get("width", 1.4))
	var approach := PLAYER_BODY_WIDTH * 0.5
	if door.get("axis", "") == "vertical":
		return Rect2(center.x - approach, center.y - width * 0.5, approach * 2.0, width)
	return Rect2(center.x - width * 0.5, center.y - approach, width, approach * 2.0)


## O movel centrado em `world_center` (XZ) fica livre dos vaos de porta da
## unidade? Uso: interno das colocacoes de movel.
static func _furniture_clear(unit, origin: Vector2, world_center: Vector2, size: Vector2) -> bool:
	var rect := Rect2(world_center - size * 0.5, size).grow(-0.02)
	for door in unit.doors:
		if _door_approach_rect(door, origin).grow(-0.02).intersects(rect):
			return false
	return true


## Caixa de movel com tamanho e deslocamento na escala base, ampliados por
## FURNITURE_SCALE a partir do ponto de ancoragem (canto ou encosto na parede).
static func _add_furniture(body: StaticBody3D, node_name: String, base_size: Vector3, anchor: Vector3, base_offset: Vector3, material: Material, collision: bool) -> void:
	BOX_BUILDER.add_box(body, node_name, base_size * FURNITURE_SCALE, anchor + base_offset * FURNITURE_SCALE, material, collision)


static func _add_room_light(body: StaticBody3D, position: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "InteriorLight"
	light.position = position
	light.light_color = Color(1.0, 0.78, 0.52)
	light.light_energy = 0.72
	light.omni_range = 5.5
	light.shadow_enabled = false
	body.add_child(light)


## Liga/desliga as luzes de interior de um predio (G7-fase1): visible=false
## pula o custo de forward no Compatibility sem destruir a cena. Cache de
## filhos em meta evita find_children a cada toggle. Uso:
##   ProceduralBuildingAssembler.set_building_lights_enabled(predio, false)
static func set_building_lights_enabled(building: Node, enabled: bool) -> void:
	if not building.has_meta(LIGHT_CACHE_META):
		building.set_meta(LIGHT_CACHE_META, building.find_children("*InteriorLight*", "OmniLight3D", true, false))
	var lights: Variant = building.get_meta(LIGHT_CACHE_META)
	for light_value in lights:
		var light := light_value as OmniLight3D
		if light != null and is_instance_valid(light):
			light.visible = enabled


## Condensadora simples na fachada traseira da casa. E puramente visual, alta o
## bastante para nao reduzir a passagem da calcada. Uso: interno do assemble.
static func _add_house_air_conditioners(body: StaticBody3D, building) -> void:
	var unit_material: Material = BUILDING_MATERIALS.opaque(Color(0.78, 0.80, 0.78), building.floor_height, false, 0.15, 0.58)
	var grille_material: Material = BUILDING_MATERIALS.opaque(Color(0.26, 0.30, 0.31), building.floor_height, false, 0.35, 0.35)
	var offset := float(posmod(int(building.seed), 5) - 2) * 0.55
	var x := clampf(building.width * 0.5 + offset, 1.0, building.width - 1.0)
	var z: float = building.depth + 0.17
	BOX_BUILDER.add_box(body, "ExteriorAirConditioner", Vector3(1.05, 0.52, 0.28), Vector3(x, 2.05, z), unit_material, false)
	BOX_BUILDER.add_box(body, "ExteriorAirConditionerGrille", Vector3(0.68, 0.28, 0.03), Vector3(x, 2.05, z + 0.15), grille_material, false)


static func _add_wave_supply(body: StaticBody3D, building) -> void:
	if building.floor_blueprints.is_empty() or building.floor_blueprints[0].units.is_empty():
		return
	var placement: Dictionary = building.floor_blueprints[0].units[0]
	var unit = placement["blueprint"]
	if unit.rooms.is_empty():
		return
	var room = unit.rooms[0]
	var unit_origin: Vector2 = placement["position"]
	var room_center: Vector2 = unit_origin + room.bounds.position + room.bounds.size * 0.5
	var supply := WAVE_SUPPLY_SCENE.instantiate() as Area3D
	var is_health := posmod(int(building.seed), 2) == 0
	supply.name = "InteriorHealthSupply" if is_health else "InteriorAmmoSupply"
	supply.set("supply_kind", 0 if is_health else 1)
	supply.set("supply_amount", 30 if is_health else 24)
	supply.position = Vector3(room_center.x, 0.2, room_center.y)
	supply.add_to_group("building_supply_points")
	body.add_child(supply)


static func _furniture_materials(seed: int) -> Array[Material]:
	var wood_shift := float(absi(seed) % 4) * 0.025
	return [
		BUILDING_MATERIALS.opaque(Color(0.40 + wood_shift, 0.25, 0.13), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT),
		BUILDING_MATERIALS.opaque(Color(0.24 + wood_shift, 0.14, 0.08), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT),
		BUILDING_MATERIALS.opaque(Color(0.31, 0.36, 0.27), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT),
		BUILDING_MATERIALS.opaque(Color(0.84, 0.85, 0.81), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT),
		BUILDING_MATERIALS.opaque(Color(0.48, 0.51, 0.52), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT, false, 0.5, 0.32),
		BUILDING_MATERIALS.opaque(Color(0.50, 0.72, 0.78), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT, false, 0.75, 0.08),
	]


static func _facade_color(seed: int) -> Color:
	var palette: Array[Color] = [
		Color(0.58, 0.37, 0.26), Color(0.30, 0.43, 0.53),
		Color(0.60, 0.48, 0.27), Color(0.35, 0.48, 0.31),
		Color(0.52, 0.34, 0.47), Color(0.46, 0.46, 0.48),
	]
	return palette[absi(seed) % palette.size()]
