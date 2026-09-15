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
const ROOF_TERRACE_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/roof_terrace_assembler.gd")
const STAIR_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/stair_assembler.gd")
const BUILDING_NAVIGATION_SCRIPT: GDScript = preload("res://scripts/procedural/navigation/building_navigation.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")
const DESTRUCTIBLE_DOOR_SCRIPT: GDScript = preload("res://scripts/destructible_door.gd")
const WAVE_SUPPLY_SCENE: PackedScene = preload("res://scenes/wave_supply_pickup.tscn")
# Moveis acompanham o tamanho do boneco (2.34 m) e a planta ampliada das casas.
const FURNITURE_SCALE := 1.3
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
	if building.archetype.begins_with("House"):
		furniture_materials = _furniture_materials(building.seed)
	for floor_blueprint in building.floor_blueprints:
		var floor_y: float = float(floor_blueprint.floor_index) * building.floor_height
		STAIR_ASSEMBLER.add_floor_slab(body, building, floor_blueprint.floor_index, floor_y, floor_material)
		for placement in floor_blueprint.units:
			_draw_unit(body, placement["blueprint"], placement["position"], floor_y + 0.08, wall_material, trim_material, furniture_materials)
	STAIR_ASSEMBLER.add_flights(body, building)
	if building.archetype.begins_with("House"):
		HOUSE_ROOF_ASSEMBLER.add_gable_roof(body, building, wall_material)
	elif building.has_roof_terrace:
		ROOF_TERRACE_ASSEMBLER.add_terrace(body, building, floor_material, wall_material)
	else:
		BOX_BUILDER.add_box(body, "Roof", Vector3(building.width, 0.18, building.depth), Vector3(building.width * 0.5, building.floors * building.floor_height, building.depth * 0.5), ceiling_material, true)
	if building.archetype == "Shop_A" or building.archetype == "Grocery_A":
		_add_commercial_front(body, building)
	_add_wave_supply(body, building)
	# Adicionado por ultimo: o navmesh e assado no _ready a partir de todas as colisoes acima.
	var navigation_height: float = building.floors * building.floor_height + (ROOF_TERRACE_ASSEMBLER.NAVIGATION_HEADROOM if building.has_roof_terrace else 0.0)
	body.add_child(BUILDING_NAVIGATION_SCRIPT.new(Vector3(building.width, navigation_height, building.depth)))
	return body


static func _draw_unit(body: StaticBody3D, unit, origin: Vector2, floor_y: float, wall_material: Material, trim_material: Material, furniture_materials: Array[Material]) -> void:
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
			_draw_room_furniture(body, room, origin, floor_y, furniture_materials)


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
	door.configure(size, BUILDING_MATERIALS.opaque(Color(0.24, 0.12, 0.055), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT))
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


static func _draw_room_furniture(body: StaticBody3D, room, origin: Vector2, floor_y: float, materials: Array[Material]) -> void:
	var left: float = origin.x + room.bounds.position.x
	var top: float = origin.y + room.bounds.position.y
	var right: float = origin.x + room.bounds.end.x
	var bottom: float = origin.y + room.bounds.end.y
	match room.room_type:
		"living_room":
			_add_table(body, Vector3(left + 1.0 * FURNITURE_SCALE, floor_y, top + room.bounds.size.y * 0.5), materials)
			_add_room_light(body, Vector3((left + right) * 0.5, floor_y + 2.35, (top + bottom) * 0.5))
		"kitchen":
			_add_kitchen(body, Vector3(right - 0.45 * FURNITURE_SCALE, floor_y, top + room.bounds.size.y * 0.5), Vector3(right - 0.5 * FURNITURE_SCALE, floor_y, top + 0.5 * FURNITURE_SCALE), materials)
		"bathroom":
			_add_bathroom(body, Vector3(left, floor_y, top), Vector2(room.bounds.size.x, room.bounds.size.y), materials)
		"bedroom":
			_add_bedroom(body, room.id, Vector3(left, floor_y, top), Vector2(room.bounds.size.x, room.bounds.size.y), materials)


static func _add_table(body: StaticBody3D, position: Vector3, materials: Array[Material]) -> void:
	_add_furniture(body, "FurnitureLivingTable", Vector3(1.25, 0.12, 0.75), position, Vector3.UP * 0.72, materials[WOOD], true)
	_add_furniture(body, "FurnitureLivingTableBase", Vector3(0.22, 0.66, 0.22), position, Vector3.UP * 0.36, materials[DARK_WOOD], false)


static func _add_kitchen(body: StaticBody3D, counter_position: Vector3, fridge_position: Vector3, materials: Array[Material]) -> void:
	_add_furniture(body, "FurnitureKitchenCounter", Vector3(0.7, 0.9, 1.8), counter_position, Vector3.UP * 0.45, materials[DARK_WOOD], true)
	_add_furniture(body, "FurnitureKitchenTop", Vector3(0.76, 0.08, 1.86), counter_position, Vector3.UP * 0.94, materials[METAL], false)
	_add_furniture(body, "FurnitureKitchenSink", Vector3(0.42, 0.04, 0.55), counter_position, Vector3(0.0, 1.0, 0.38), materials[GLASS], false)
	_add_furniture(body, "FurnitureKitchenFridge", Vector3(0.78, 1.85, 0.78), fridge_position, Vector3.UP * 0.925, materials[METAL], true)


static func _add_bathroom(body: StaticBody3D, corner: Vector3, size: Vector2, materials: Array[Material]) -> void:
	var scaled_depth := size.y / FURNITURE_SCALE
	var scaled_width := size.x / FURNITURE_SCALE
	_add_furniture(body, "FurnitureBathroomSink", Vector3(0.5, 0.82, 0.58), corner, Vector3(0.35, 0.41, 0.75), materials[CERAMIC], true)
	_add_furniture(body, "FurnitureBathroomMirror", Vector3(0.04, 0.72, 0.62), corner, Vector3(0.07, 1.45, 0.75), materials[GLASS], false)
	_add_furniture(body, "FurnitureBathroomToilet", Vector3(0.58, 0.48, 0.72), corner, Vector3(0.4, 0.24, scaled_depth - 0.55), materials[CERAMIC], true)
	_add_furniture(body, "FurnitureBathroomShower", Vector3(0.72, 0.12, 0.82), corner, Vector3(scaled_width - 0.48, 0.06, scaled_depth - 0.55), materials[GLASS], true)


static func _add_bedroom(body: StaticBody3D, room_id: String, corner: Vector3, size: Vector2, materials: Array[Material]) -> void:
	var scaled_size := size / FURNITURE_SCALE
	var bed_width := minf(1.15, scaled_size.x - 0.35)
	var bed_depth := minf(1.8, scaled_size.y * 0.48)
	var bed_offset := Vector3(scaled_size.x - bed_width * 0.5 - 0.14, 0.28, scaled_size.y - bed_depth * 0.5 - 0.14)
	_add_furniture(body, "FurnitureBed_%s" % room_id, Vector3(bed_width, 0.48, bed_depth), corner, bed_offset, materials[FABRIC], true)
	_add_furniture(body, "FurniturePillow_%s" % room_id, Vector3(bed_width * 0.72, 0.14, 0.38), corner, bed_offset + Vector3(0.0, 0.3, -bed_depth * 0.3), materials[CERAMIC], false)
	_add_furniture(body, "FurnitureWardrobe_%s" % room_id, Vector3(0.58, 1.8, 0.82), corner, Vector3(0.36, 0.9, 0.55), materials[DARK_WOOD], true)


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


static func _add_commercial_front(body: StaticBody3D, building) -> void:
	var accent := Color(0.26, 0.58, 0.32) if building.archetype == "Grocery_A" else Color(0.84, 0.36, 0.14)
	BOX_BUILDER.add_box(body, "StoreAwning", Vector3(building.width * 0.72, 0.22, 0.9), Vector3(building.width * 0.5, 2.2, -0.38), BUILDING_MATERIALS.opaque(accent, BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT), false)
	BOX_BUILDER.add_box(body, "StoreSign", Vector3(building.width * 0.48, 0.55, 0.08), Vector3(building.width * 0.5, 2.52, -0.08), BUILDING_MATERIALS.opaque(accent.lightened(0.2), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT), false)


static func _facade_color(seed: int) -> Color:
	var palette: Array[Color] = [
		Color(0.58, 0.37, 0.26), Color(0.30, 0.43, 0.53),
		Color(0.60, 0.48, 0.27), Color(0.35, 0.48, 0.31),
		Color(0.52, 0.34, 0.47), Color(0.46, 0.46, 0.48),
	]
	return palette[absi(seed) % palette.size()]
