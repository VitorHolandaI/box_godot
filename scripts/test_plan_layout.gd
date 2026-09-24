# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do adaptador planta -> UnitBlueprint: a planta do
## floor_plan_generator vira comodos e portas que o building_assembler sabe
## montar, com todos os comodos alcancaveis e proporcionais ao boneco.
## Uso: await PlanLayoutTests.new().run(test_root)

const ROOM_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/room_generator.gd")
const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const FLOOR_PLAN_SCRIPT := preload("res://scripts/floor_plan_generator.gd")
const PLAYER_WIDTH := 1.16
const PLAN_SEEDS: Array[int] = [18273, 5501, 99120, 7, 240912]
const PLAN_WIDTH := 10.0
const PLAN_DEPTH := 8.0
## Casa: maior tamanho gerado (18x15), para testar o pior caso de grade.
const HOUSE_WIDTH := 18.0
const HOUSE_DEPTH := 15.0
## Menor lado de comodo aceito depois de escalar (mesmo criterio do
## test_apartment_layout: PLAYER_WIDTH * 2.5).
const MIN_ROOM_SIDE := PLAYER_WIDTH * 2.5
## Menor vao de porta aceito (mesmo criterio do test_apartment_layout).
const MIN_DOOR_WIDTH := PLAYER_WIDTH * 1.6


func run(test_root: Node) -> void:
	_test_program_scales_with_area(test_root)
	_test_plan_unit_connected_and_contained(test_root)
	_test_plan_unit_scales_to_player(test_root)
	_test_house_plan_fits_player(test_root)
	_test_house_has_two_entrances(test_root)
	_test_house_entrances_have_inward_default(test_root)
	_test_plan_units_vary_by_seed(test_root)
	_test_flag_switches_generate_apartment(test_root)


## O programa (quais/quantos comodos) cresce com a area e respeita as regras:
## casa pequena nao pede 4 banheiros, casa grande pede mais quartos.
func _test_program_scales_with_area(test_root: Node) -> void:
	print("Testando programa de comodos por tamanho da casa...")
	var small: Array[Dictionary] = FLOOR_PLAN_SCRIPT.program_for_seed(4242, 80.0)
	var large: Array[Dictionary] = FLOOR_PLAN_SCRIPT.program_for_seed(4242, 180.0)
	var repeated: Array[Dictionary] = FLOOR_PLAN_SCRIPT.program_for_seed(4242, 80.0)
	if _count_room(small, "SALA") < 1 or _count_room(small, "COZINHA") < 1 or _count_room(small, "QUARTO") < 1 or _count_room(small, "BANHEIRO") < 1:
		_fail(test_root, "Casa pequena sem o basico (sala/cozinha/quarto/banheiro): %s." % [small])
		return
	if large.size() <= small.size() or _count_room(large, "QUARTO") <= _count_room(small, "QUARTO"):
		_fail(test_root, "Casa grande deveria pedir mais comodos/quartos: pequena=%d quartos=%d grande=%d quartos=%d." % [small.size(), _count_room(small, "QUARTO"), large.size(), _count_room(large, "QUARTO")])
		return
	if _count_room(small, "BANHEIRO") > 2 or _count_room(large, "BANHEIRO") > 4:
		_fail(test_root, "Banheiros fora do plausivel: pequena=%d grande=%d." % [_count_room(small, "BANHEIRO"), _count_room(large, "BANHEIRO")])
		return
	if not _same_program(small, repeated):
		_fail(test_root, "Programa deveria ser deterministico pela seed.")
		return
	var house_program: Array[Dictionary] = FLOOR_PLAN_SCRIPT.program_for_seed(4242, 180.0, true)
	if _count_room(house_program, "DESPENSA") != 1:
		_fail(test_root, "Casa deveria ter 1 despensa (entrada de servico); tem %d." % _count_room(house_program, "DESPENSA"))
		return
	print("PASS: Programa por area: pequena=%d comodos, grande=%d (quartos %d->%d, banheiros %d->%d, 1 despensa)." % [small.size(), large.size(), _count_room(small, "QUARTO"), _count_room(large, "QUARTO"), _count_room(small, "BANHEIRO"), _count_room(large, "BANHEIRO")])


func _count_room(program: Array, room_name: String) -> int:
	var count := 0
	for entry in program:
		if String(entry["name"]) == room_name:
			count += 1
	return count


func _same_program(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if String(first[index]["name"]) != String(second[index]["name"]) or not is_equal_approx(float(first[index]["weight"]), float(second[index]["weight"])):
			return false
	return true


func _test_plan_unit_connected_and_contained(test_root: Node) -> void:
	print("Testando planta procedural: comodos contidos, sem sobreposicao e alcancaveis...")
	for plan_seed in PLAN_SEEDS:
		var unit = ROOM_GENERATOR_SCRIPT.generate_apartment_from_plan(plan_seed, PLAN_WIDTH, PLAN_DEPTH)
		var problem := _plan_unit_problem(unit, PLAN_WIDTH, PLAN_DEPTH)
		if not problem.is_empty():
			_fail(test_root, "Seed %d: %s" % [plan_seed, problem])
			return
	print("PASS: Planta contida, sem sobreposicao e com todos os comodos alcancaveis.")


## Primeiro problema da unidade da planta ("" quando esta tudo certo). Uso:
## interno do _test_plan_unit_connected_and_contained.
func _plan_unit_problem(unit, width: float, depth: float) -> String:
	var rooms: Array = unit.rooms
	if rooms.size() < 3:
		return "gerou %d comodos; esperado ao menos 3." % rooms.size()
	if not unit.is_graph_connected():
		return "comodo isolado na planta."
	for index in rooms.size():
		var bounds: Rect2 = rooms[index].bounds
		if bounds.position.x < -0.001 or bounds.position.y < -0.001 or bounds.end.x > width + 0.001 or bounds.end.y > depth + 0.001:
			return "comodo '%s' fora da unidade em %s." % [rooms[index].id, bounds]
		if _overlaps_any_room(bounds, rooms, index):
			return "comodos se sobrepoem."
	for door in unit.doors:
		if float(door["width"]) <= 0.0:
			return "porta sem largura em %s." % door
	return ""


## O retangulo cruza algum comodo depois do indice? Uso: interno.
func _overlaps_any_room(bounds: Rect2, rooms: Array, index: int) -> bool:
	for other in range(index + 1, rooms.size()):
		if bounds.intersects((rooms[other].bounds as Rect2).grow(-0.001)):
			return true
	return false


func _test_plan_unit_scales_to_player(test_root: Node) -> void:
	print("Testando planta procedural escalada para o tamanho do boneco...")
	var scales: Array[Vector2] = [Vector2.ONE * 1.5, Vector2(1.2, 2.0)]
	for plan_seed in PLAN_SEEDS:
		for scale in scales:
			var unit = ROOM_GENERATOR_SCRIPT.generate_apartment_from_plan(plan_seed, PLAN_WIDTH, PLAN_DEPTH)
			unit.scale_layout(scale, 2.0)
			var problem := _scaled_unit_problem(unit)
			if not problem.is_empty():
				_fail(test_root, "Seed %d escala %s: %s" % [plan_seed, scale, problem])
				return
	print("PASS: Comodos e portas da planta passam o boneco de %.2f m apos escalar." % PLAYER_WIDTH)


## Primeiro problema da unidade escalada ("" quando esta tudo certo). Uso:
## interno do _test_plan_unit_scales_to_player.
func _scaled_unit_problem(unit) -> String:
	for room in unit.rooms:
		var bounds: Rect2 = room.bounds
		if minf(bounds.size.x, bounds.size.y) < MIN_ROOM_SIDE:
			return "comodo '%s' com %s menor que %.2f m." % [room.id, bounds.size, MIN_ROOM_SIDE]
	for door in unit.doors:
		if float(door["width"]) < MIN_DOOR_WIDTH:
			return "porta com %.2f m menor que %.2f m." % [float(door["width"]), MIN_DOOR_WIDTH]
	return ""


## A casa usa a planta no tamanho final (15x12), sem scale_layout: os comodos e
## portas precisam passar o boneco do mesmo jeito.
func _test_house_plan_fits_player(test_root: Node) -> void:
	print("Testando planta da casa 15x12 no tamanho final...")
	for plan_seed in PLAN_SEEDS:
		var unit = ROOM_GENERATOR_SCRIPT.generate_apartment_from_plan(plan_seed, HOUSE_WIDTH, HOUSE_DEPTH)
		var problem := _plan_unit_problem(unit, HOUSE_WIDTH, HOUSE_DEPTH)
		if problem.is_empty():
			problem = _scaled_unit_problem(unit)
		if not problem.is_empty():
			_fail(test_root, "Casa seed %d: %s" % [plan_seed, problem])
			return
	print("PASS: Casa 15x12 gerada no tamanho final passa o boneco.")


## Casa com 2 entradas: principal na sala e de servico na despensa (mudroom),
## cada uma numa parede externa. Uso: interno do run.
func _test_house_has_two_entrances(test_root: Node) -> void:
	print("Testando casa com entrada na sala e de servico na despensa...")
	for plan_seed in PLAN_SEEDS:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(plan_seed, "house")
		var unit = blueprint.floor_blueprints[0].units[0]["blueprint"]
		var entrances: Array[String] = []
		for door in unit.doors:
			if door.get("room_b", "") == "outside":
				entrances.append(String(door["room_a"]))
		var problem := _entrance_problem(unit, entrances)
		if not problem.is_empty():
			_fail(test_root, "Casa seed %d: %s" % [plan_seed, problem])
			return
	print("PASS: Casa com 2 entradas externas, uma na sala e uma na despensa.")


## A direcao inicial das portas externas aponta para dentro. O clique do
## jogador pode trocar o lado para abrir longe dele. Uso: interno do run.
func _test_house_entrances_have_inward_default(test_root: Node) -> void:
	print("Testando sentido inicial das entradas da casa...")
	for building_seed in range(1, 21):
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, "house")
		var unit = blueprint.floor_blueprints[0].units[0]["blueprint"]
		for door in unit.doors:
			if door.get("room_b", "") != "outside":
				continue
			var inward_swing := _inward_swing_for_exterior_door(unit, door)
			var swing := float(door.get("swing_direction", 0.0))
			if is_zero_approx(inward_swing) or is_zero_approx(swing):
				_fail(test_root, "Casa seed %d tem entrada externa sem sentido de abertura: %s." % [building_seed, door])
				return
			if is_equal_approx(swing, inward_swing):
				continue
			_fail(test_root, "Casa seed %d tem swing inicial %.1f para fora na entrada %s." % [building_seed, swing, door])
			return
	print("PASS: Direcao inicial de todas as entradas aponta para dentro.")


## Direcao que move a folha para o interior, inferida pela borda externa onde
## fica o vao. Uso: interno do _test_house_entrances_have_inward_default.
func _inward_swing_for_exterior_door(unit, door: Dictionary) -> float:
	var center: Vector2 = door["center"]
	if is_zero_approx(center.y) or is_equal_approx(center.x, unit.width):
		return 1.0
	if is_equal_approx(center.y, unit.depth) or is_zero_approx(center.x):
		return -1.0
	return 0.0


## Primeiro problema das entradas ("" quando estao certas). Uso: interno.
func _entrance_problem(unit, entrances: Array[String]) -> String:
	if entrances.size() < 2:
		return "so %d entrada(s) externa(s); esperado 2." % entrances.size()
	var has_sala := false
	var has_despensa := false
	for room_id in entrances:
		var room = _find_room(unit, room_id)
		if room == null:
			continue
		has_sala = has_sala or room.room_type == "living_room"
		has_despensa = has_despensa or room.room_type == "storage"
	if not has_sala or not has_despensa:
		return "entradas sala=%s despensa=%s; esperado uma de cada." % [has_sala, has_despensa]
	return ""


func _find_room(unit, room_id: String):
	for room in unit.rooms:
		if room.id == room_id:
			return room
	return null


func _test_plan_units_vary_by_seed(test_root: Node) -> void:
	print("Testando variacao da planta por seed...")
	var signatures := {}
	for plan_seed in PLAN_SEEDS:
		signatures[ROOM_GENERATOR_SCRIPT.generate_apartment_from_plan(plan_seed, PLAN_WIDTH, PLAN_DEPTH).signature()] = true
	if signatures.size() < 2:
		_fail(test_root, "Planta nao variou por seed: %d assinatura(s) para %d seeds." % [signatures.size(), PLAN_SEEDS.size()])
		return
	print("PASS: %d seeds deram %d plantas diferentes." % [PLAN_SEEDS.size(), signatures.size()])


func _test_flag_switches_generate_apartment(test_root: Node) -> void:
	print("Testando a flag que troca a planta fixa pela procedural...")
	var previous := ROOM_GENERATOR_SCRIPT.use_plan_layout
	ROOM_GENERATOR_SCRIPT.use_plan_layout = false
	var legacy = ROOM_GENERATOR_SCRIPT.generate_apartment(18273, 0)
	ROOM_GENERATOR_SCRIPT.use_plan_layout = true
	var planned = ROOM_GENERATOR_SCRIPT.generate_apartment(18273, 0)
	ROOM_GENERATOR_SCRIPT.use_plan_layout = previous
	if legacy.archetype == planned.archetype or not planned.is_graph_connected():
		_fail(test_root, "Flag: antigo='%s' procedural='%s' conexo=%s; esperado arquetipos diferentes e procedural conexo." % [legacy.archetype, planned.archetype, planned.is_graph_connected()])
		return
	print("PASS: Flag troca '%s' (fixa) por '%s' (procedural conexa)." % [legacy.archetype, planned.archetype])


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
