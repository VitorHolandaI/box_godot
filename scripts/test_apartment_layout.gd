# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da planta dos predios: vao de porta sem parede atravessada
## (porta "travada" que a faca nao acertava), todos os comodos alcancaveis a
## partir da rua, comodos proporcionais ao boneco e terraco acessivel no topo.
## Uso: await ApartmentLayoutTests.new().run(test_root)

const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const ROOF_TERRACE_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/roof_terrace_assembler.gd")
const APARTMENT_SEEDS: Array[int] = [18273, 5501, 99120]
const HOUSE_SEEDS: Array[int] = [240912, 1234, 777]
const PLAYER_WIDTH := 1.16
const DOORWAY_CHECK_BOTTOM := 0.2
const DOORWAY_CHECK_TOP := 2.5


func run(test_root: Node) -> void:
	_test_doorways_are_not_crossed_by_walls(test_root)
	_test_every_room_reachable_from_street(test_root)
	_test_apartment_rooms_fit_player_size(test_root)
	_test_residential_floors_have_variable_apartments(test_root)
	_test_apartments_are_furnished(test_root)
	_test_ground_floor_has_reception_and_trash(test_root)
	_test_building_has_air_conditioners(test_root)
	_test_roof_terrace_has_parapet_and_last_flight(test_root)
	await _test_navigation_reaches_roof_terrace(test_root)


## Cada andar alto tem 1, 2 ou 4 apartamentos (planta varia por seed) e o
## corredor aparece quando ha mais de um. Uso: interno do run.
func _test_residential_floors_have_variable_apartments(test_root: Node) -> void:
	print("Testando 1, 2 ou 4 apartamentos por andar...")
	var seen: Dictionary = {}
	for building_seed in [18273, 5501, 99120, 777, 1234, 4242]:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, "apartment")
		for floor_blueprint in blueprint.floor_blueprints:
			if floor_blueprint.floor_index == 0:
				continue
			var apartments := 0
			var corridor_units := 0
			for placement in floor_blueprint.units:
				var unit = placement["blueprint"]
				if unit.rooms.size() == 1 and unit.rooms[0].room_type == "corridor":
					corridor_units += 1
				for room in unit.rooms:
					if room.room_type == "living_room":
						apartments += 1
			if not [1, 2, 4].has(apartments):
				_fail(test_root, "Andar %d com %d apartamentos; esperado 1, 2 ou 4." % [floor_blueprint.floor_index, apartments])
				return
			var expected_corridors := 0 if apartments == 1 else 1
			if corridor_units != expected_corridors:
				_fail(test_root, "Andar %d com %d apartamento(s) deveria ter %d corredor(es); tem %d." % [floor_blueprint.floor_index, apartments, expected_corridors, corridor_units])
				return
			seen[apartments] = true
	if seen.size() < 2:
		_fail(test_root, "Predios deveriam variar o numero de apartamentos por andar; vistos=%s." % [seen.keys()])
		return
	print("PASS: Andares com %s apartamentos em %d seeds." % [seen.keys(), 6])


## Apartamento mobiliado: sala com cozinha integrada, quarto e banheiro.
func _test_apartments_are_furnished(test_root: Node) -> void:
	print("Testando mobilia dos apartamentos...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEEDS[0], "apartment")
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var missing := ""
	for furniture_prefix in ["FurnitureLivingTable", "FurnitureKitchenCounter", "FurnitureKitchenFridge", "FurnitureBathroomMirror", "FurnitureBed_", "FurnitureWardrobe_", "FurniturePicture_"]:
		if building.find_children(furniture_prefix + "*", "Node", true, false).is_empty():
			missing = furniture_prefix
			break
	building.free()
	if not missing.is_empty():
		_fail(test_root, "Apartamento deveria ter mobilia; faltou '%s*'." % missing)
		return
	print("PASS: Apartamentos com sala, cozinha integrada, quarto e banheiro mobiliados.")


## Terreo com recepcao (entrada) e sala de lixo com porta de servico.
func _test_ground_floor_has_reception_and_trash(test_root: Node) -> void:
	print("Testando recepcao e lixo no terreo...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEEDS[0], "apartment")
	var room_types: Dictionary = {}
	var trash_has_service_door := false
	for placement in blueprint.floor_blueprints[0].units:
		for room in placement["blueprint"].rooms:
			room_types[room.room_type] = true
		for door in placement["blueprint"].doors:
			if door.get("room_a", "") == "trash_room" and door.get("room_b", "") == "outside":
				trash_has_service_door = true
	if not room_types.has("reception") or not room_types.has("trash_room") or not trash_has_service_door:
		_fail(test_root, "Terreo deveria ter recepcao, lixo e porta de servico do lixo; comodos=%s servico=%s." % [room_types.keys(), trash_has_service_door])
		return
	print("PASS: Terreo com recepcao e sala de lixo com coleta.")


## Ar-condicionado: condensadora por andar na fachada e split nos apartamentos.
func _test_building_has_air_conditioners(test_root: Node) -> void:
	print("Testando ar-condicionado do predio...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEEDS[0], "apartment")
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var exterior := building.find_children("ExteriorAirConditioner_*", "MeshInstance3D", true, false).size()
	var interior := building.find_children("InteriorAirConditioner_*", "MeshInstance3D", true, false).size()
	building.free()
	if exterior != blueprint.floors or interior < 4:
		_fail(test_root, "Predio deveria ter %d condensadoras e >=4 splits; tem %d/%d." % [blueprint.floors, exterior, interior])
		return
	print("PASS: Predio com %d condensadoras e %d splits de ar-condicionado." % [exterior, interior])


func _test_doorways_are_not_crossed_by_walls(test_root: Node) -> void:
	print("Testando vaos de porta livres de paredes atravessadas...")
	var cases: Array[Array] = []
	for building_seed in APARTMENT_SEEDS:
		cases.append([building_seed, "apartment"])
	for building_seed in HOUSE_SEEDS:
		cases.append([building_seed, "house"])
	for building_case in cases:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(int(building_case[0]), String(building_case[1]))
		var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
		var blocked := _first_blocked_doorway(building)
		building.free()
		if not blocked.is_empty():
			_fail(test_root, "%s seed %d: parede atravessa o vao da porta %s." % [building_case[1], building_case[0], blocked])
			return
	print("PASS: Nenhuma parede corta vaos de porta em predios e casas.")


func _test_every_room_reachable_from_street(test_root: Node) -> void:
	print("Testando todos os comodos alcancaveis a partir da rua...")
	for building_seed in APARTMENT_SEEDS:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, "apartment")
		var unreachable := _unreachable_rooms(blueprint)
		if not unreachable.is_empty():
			_fail(test_root, "Predio seed %d com comodos isolados: %s." % [building_seed, unreachable])
			return
	print("PASS: Portaria, escada, apartamentos e terraco formam um grafo conexo.")


func _test_apartment_rooms_fit_player_size(test_root: Node) -> void:
	print("Testando comodos dos apartamentos proporcionais ao boneco...")
	for building_seed in APARTMENT_SEEDS:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, "apartment")
		for floor_blueprint in blueprint.floor_blueprints:
			for placement in floor_blueprint.units:
				var unit = placement["blueprint"]
				for room in unit.rooms:
					if minf(room.bounds.size.x, room.bounds.size.y) < PLAYER_WIDTH * 2.5:
						_fail(test_root, "Andar %d: comodo '%s' com %s e apertado para boneco de %.2f m." % [floor_blueprint.floor_index, room.id, room.bounds.size, PLAYER_WIDTH])
						return
				for door in unit.doors:
					if float(door["width"]) < PLAYER_WIDTH * 1.6:
						_fail(test_root, "Andar %d: porta %s com %.2f m e estreita para o boneco." % [floor_blueprint.floor_index, door["center"], float(door["width"])])
						return
	print("PASS: Apartamentos com comodos e portas para o boneco de %.2f m." % PLAYER_WIDTH)


func _test_roof_terrace_has_parapet_and_last_flight(test_root: Node) -> void:
	print("Testando terraco com mureta e lance ate o topo...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEEDS[0], "apartment")
	if blueprint.stair_flights.size() != blueprint.floors:
		_fail(test_root, "Predio de %d andares deveria ter %d lances (um ate o terraco); tem %d." % [blueprint.floors, blueprint.floors, blueprint.stair_flights.size()])
		return
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var roof_index: int = blueprint.floors
	var has_parts := building.has_node("RoofParapetFront") and building.has_node("RoofParapetBack") and building.has_node("RoofStairBulkheadRoof") and building.has_node("Floor_%d_Left" % roof_index)
	var parapet := building.get_node_or_null("RoofParapetFront") as MeshInstance3D
	var parapet_height := (parapet.mesh as BoxMesh).size.y if parapet != null else 0.0
	building.free()
	if not has_parts or parapet_height < 1.0:
		_fail(test_root, "Terraco deveria ter laje com vao, mureta >= 1 m e casinha da escada; partes=%s mureta=%.2f." % [has_parts, parapet_height])
		return
	print("PASS: Terraco com mureta de %.1f m e casinha da escada." % parapet_height)


func _test_navigation_reaches_roof_terrace(test_root: Node) -> void:
	print("Testando caminho do navmesh da rua ate o terraco...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEEDS[0], "apartment")
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	building.position = Vector3(-900.0, 0.16, 900.0)
	test_root.add_child(building)
	var navigation = building.get_node("BuildingNavigation")
	for _frame in 120:
		if navigation.is_ready():
			break
		await test_root.get_tree().physics_frame
	var roof_y: float = building.global_position.y + float(blueprint.floors) * blueprint.floor_height
	var from := building.global_position + Vector3(blueprint.width * 0.5, 0.0, -1.5)
	var to := building.global_position + Vector3(4.0, float(blueprint.floors) * blueprint.floor_height, 12.0)
	var path: PackedVector3Array = navigation.get_path_between(from, to)
	building.queue_free()
	if path.is_empty() or absf(path[path.size() - 1].y - roof_y) > 0.5 or Vector2(path[path.size() - 1].x - to.x, path[path.size() - 1].z - to.z).length() > 1.0:
		_fail(test_root, "Caminho deveria chegar ao terraco em %s; pontos=%d fim=%s." % [to, path.size(), path[path.size() - 1] if not path.is_empty() else null])
		return
	print("PASS: Navmesh liga a portaria ao terraco pelos %d lances." % blueprint.stair_flights.size())


## Primeira porta cuja passagem (vao mais meio boneco de cada lado, entre 0.2 m
## e 2.5 m acima do piso) intersecta uma caixa de colisao do edificio. Pega a
## parede interna que encostava na linha da porta e fatiava a aproximacao em
## 1.14 m. Portas sao corpos proprios e ficam de fora.
func _first_blocked_doorway(building: StaticBody3D) -> String:
	for door_node in building.find_children("Door_*", "AnimatableBody3D", false, false):
		var door := door_node as Node3D
		var panel_size: Vector3 = door.get("panel_size")
		var approach := PLAYER_WIDTH * 0.5
		var doorway := Rect2(door.position.x, door.position.z - approach, panel_size.x, approach * 2.0)
		if panel_size.z > panel_size.x:
			doorway = Rect2(door.position.x - approach, door.position.z, approach * 2.0, panel_size.z)
		for child in building.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or not shape_node.shape is BoxShape3D or not shape_node.transform.basis.is_equal_approx(Basis.IDENTITY):
				continue
			var size := (shape_node.shape as BoxShape3D).size
			var bottom := shape_node.position.y - size.y * 0.5
			var top := shape_node.position.y + size.y * 0.5
			if top <= door.position.y + DOORWAY_CHECK_BOTTOM or bottom >= door.position.y + DOORWAY_CHECK_TOP:
				continue
			var box_rect := Rect2(shape_node.position.x - size.x * 0.5, shape_node.position.z - size.z * 0.5, size.x, size.z)
			if box_rect.grow(-0.02).intersects(doorway.grow(-0.02)):
				return "%s (caixa %s em %s)" % [door.name, size, shape_node.position]
	return ""


## Busca em largura sobre "andar:unidade:comodo" usando portas internas,
## passagens entre unidades e lances de escada (nucleo do andar k liga ao k+1;
## o ultimo lance liga ao terraco). Devolve os comodos nao visitados.
func _unreachable_rooms(blueprint) -> Array[String]:
	var edges: Dictionary = {}
	var all_rooms: Array[String] = []
	var starts: Array[String] = []
	for floor_blueprint in blueprint.floor_blueprints:
		for unit_index in floor_blueprint.units.size():
			var unit = floor_blueprint.units[unit_index]["blueprint"]
			var prefix := "%d:%d:" % [floor_blueprint.floor_index, unit_index]
			for room in unit.rooms:
				all_rooms.append(prefix + room.id)
				if room.room_type == "stairs":
					_connect(edges, prefix + room.id, "stairs:%d" % floor_blueprint.floor_index)
			for door in unit.doors:
				if door.get("room_b", "") == "outside":
					starts.append(prefix + String(door["room_a"]))
				elif door.get("room_b", "") != "neighbor":
					_connect(edges, prefix + String(door["room_a"]), prefix + String(door["room_b"]))
	for link in blueprint.unit_links:
		var floor_prefix := "%d:" % int(link["floor_index"])
		_connect(edges, floor_prefix + String(link["node_a"]), floor_prefix + String(link["node_b"]))
	for flight in blueprint.stair_flights:
		var floor_index := int(flight["floor_index"])
		_connect(edges, "stairs:%d" % floor_index, "stairs:%d" % (floor_index + 1))
	all_rooms.append("stairs:%d" % blueprint.floors)
	var visited: Dictionary = {}
	var pending: Array[String] = starts.duplicate()
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		for next in edges.get(current, []):
			pending.append(String(next))
	var unreachable: Array[String] = []
	for room_key in all_rooms:
		if not visited.has(room_key):
			unreachable.append(room_key)
	return unreachable


func _connect(edges: Dictionary, first: String, second: String) -> void:
	if not edges.has(first):
		edges[first] = []
	if not edges.has(second):
		edges[second] = []
	edges[first].append(second)
	edges[second].append(first)


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
