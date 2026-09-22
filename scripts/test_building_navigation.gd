extends RefCounted

## Regressoes da escada dos predios, do navmesh por edificio e da rota de
## saida dos zumbis (lag de zumbis presos dentro de casas).
## Uso: await BuildingNavigationTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const STAIR_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/stair_assembler.gd")
const NAVIGATION_SCRIPT := preload("res://scripts/procedural/navigation/building_navigation.gd")
const ROUTER_SCRIPT := preload("res://scripts/zombie_indoor_router.gd")
const APARTMENT_SEED := 18273
const HOUSE_SEED := 240912
const STEP_DELTA := 1.0 / 60.0
# Sala do apartamento, logo depois da passagem que sai do nucleo da escada.
const APARTMENT_LIVING_POINT := Vector2(9.0, 4.0)

## Serial dos zumbis de teste: nome unico por instancia, para o Godot nunca
## renomear por colisao de irmao (ver _add_walker_zombie).
var _walker_serial := 0


func run(test_root: Node) -> void:
	_test_stair_flights_alternate_and_skip_walls(test_root)
	_test_ramp_surface_meets_upper_slab(test_root)
	_test_upper_floors_have_no_doors_to_the_void(test_root)
	_test_router_without_building_has_no_route(test_root)
	_test_flock_push_never_pushes_backward_on_route(test_root)
	await _test_navigation_path_reaches_top_floor(test_root)
	await _test_zombie_climbs_to_top_floor(test_root)
	await _test_zombie_descends_to_street(test_root)
	await _test_player_climbs_to_roof_terrace(test_root)
	await _test_zombie_leaves_house_breaking_doors(test_root)


func _test_stair_flights_alternate_and_skip_walls(test_root: Node) -> void:
	print("Testando lances alternados da escada livres de paredes...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	# Um lance por transicao de andar e mais um ate o terraco.
	if blueprint.stair_flights.size() != blueprint.floors:
		_fail(test_root, "Predio de %d andares deveria ter %d lances; tem %d." % [blueprint.floors, blueprint.floors, blueprint.stair_flights.size()])
		return
	for index in range(1, blueprint.stair_flights.size()):
		var previous: Dictionary = blueprint.stair_flights[index - 1]
		var current: Dictionary = blueprint.stair_flights[index]
		if is_equal_approx(float(previous["center_x"]), float(current["center_x"])) or not is_equal_approx(float(previous["top_z"]), float(current["bottom_z"])):
			_fail(test_root, "Lance %d deveria mudar de coluna e comecar onde o anterior termina: %s -> %s." % [index, previous, current])
			return
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	for flight in blueprint.stair_flights:
		var footprint := STAIR_ASSEMBLER_SCRIPT.flight_hole_rect(flight)
		var base_y: float = float(flight["floor_index"]) * blueprint.floor_height
		for node in building.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			var node_name := String(mesh_node.name)
			if not (node_name.begins_with("Wall") or node_name.begins_with("DoorHeader")):
				continue
			var box := mesh_node.mesh as BoxMesh
			var wall_rect := Rect2(mesh_node.position.x - box.size.x * 0.5, mesh_node.position.z - box.size.z * 0.5, box.size.x, box.size.z)
			var wall_bottom := mesh_node.position.y - box.size.y * 0.5
			var wall_top := mesh_node.position.y + box.size.y * 0.5
			var overlaps_height: bool = wall_top > base_y + 0.2 and wall_bottom < base_y + blueprint.floor_height * 2.0
			if overlaps_height and wall_rect.grow(-0.01).intersects(footprint):
				_fail(test_root, "Parede '%s' em %s atravessa o lance %s." % [node_name, mesh_node.position, flight])
				building.free()
				return
	building.free()
	print("PASS: Lances alternam de coluna e nenhuma parede corta a escada.")


func _test_ramp_surface_meets_upper_slab(test_root: Node) -> void:
	print("Testando rampa da escada alcancando a laje de cima...")
	var flight: Dictionary = BUILDING_GENERATOR_SCRIPT.stair_flight_for_floor(0)
	var floor_height := 3.4
	var ramp: CollisionShape3D = STAIR_ASSEMBLER_SCRIPT.build_ramp_collision(flight, 0.0, floor_height)
	var size := (ramp.shape as BoxShape3D).size
	var expected_top := Vector3(float(flight["center_x"]), floor_height + STAIR_ASSEMBLER_SCRIPT.SLAB_THICKNESS * 0.5 + STAIR_ASSEMBLER_SCRIPT.RAMP_TOP_LIFT, float(flight["top_z"]))
	var best_distance := INF
	for end_sign in [-1.0, 1.0]:
		var surface_end: Vector3 = ramp.transform * Vector3(0.0, size.y * 0.5, size.z * 0.5 * end_sign)
		best_distance = minf(best_distance, surface_end.distance_to(expected_top))
	ramp.free()
	if best_distance > 0.02:
		_fail(test_root, "Topo da rampa deveria encostar na laje em %s; distancia=%.3f m." % [expected_top, best_distance])
		return
	var slope_degrees := rad_to_deg(atan2(floor_height, absf(float(flight["top_z"]) - float(flight["bottom_z"]))))
	if slope_degrees >= 45.0:
		_fail(test_root, "Inclinacao da escada %.1f graus excede o floor_max_angle de 45." % slope_degrees)
		return
	print("PASS: Rampa termina rente a laje com inclinacao de %.0f graus." % slope_degrees)


func _test_upper_floors_have_no_doors_to_the_void(test_root: Node) -> void:
	print("Testando acesso aos apartamentos altos pelo nucleo da escada...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	for floor_blueprint in blueprint.floor_blueprints:
		if floor_blueprint.floor_index == 0:
			continue
		for placement in floor_blueprint.units:
			for door in placement["blueprint"].doors:
				if door.get("room_b", "") == "outside":
					_fail(test_root, "Andar %d possui porta externa para o vazio: %s." % [floor_blueprint.floor_index, door])
					return
	var links_per_floor: Dictionary = {}
	for link in blueprint.unit_links:
		links_per_floor[int(link["floor_index"])] = int(links_per_floor.get(int(link["floor_index"]), 0)) + 1
	for floor_blueprint in blueprint.floor_blueprints:
		if floor_blueprint.floor_index == 0:
			continue
		var apartments := 0
		for placement in floor_blueprint.units:
			for room in placement["blueprint"].rooms:
				if room.room_type == "living_room":
					apartments += 1
		# 1 apartamento liga direto ao nucleo; 2 ou 4 passam pelo corredor.
		var expected := apartments + (0 if apartments == 1 else 1)
		if int(links_per_floor.get(floor_blueprint.floor_index, 0)) != expected:
			_fail(test_root, "Andar %d com %d apartamento(s) deveria ter %d passagens; tem %d." % [floor_blueprint.floor_index, apartments, expected, int(links_per_floor.get(floor_blueprint.floor_index, 0))])
			return
	print("PASS: Andares altos so tem passagens internas (1, 2 ou 4 apartamentos por andar).")


func _test_router_without_building_has_no_route(test_root: Node) -> void:
	print("Testando rota direta fora de edificios...")
	var router = ROUTER_SCRIPT.new()
	var target := Vector3(-900.0, 0.0, -900.0)
	var waypoint: Vector3 = router.next_waypoint(test_root.get_tree(), Vector3(-880.0, 0.0, -880.0), target, STEP_DELTA)
	if router.has_route or waypoint != target:
		_fail(test_root, "Sem edificio por perto o roteador deveria devolver o proprio alvo; veio %s." % waypoint)
		return
	print("PASS: Na rua o zumbi persegue em linha reta.")


func _test_flock_push_never_pushes_backward_on_route(test_root: Node) -> void:
	print("Testando empurrao do bando limitado durante a rota interna...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.simulation_enabled = false
	test_root.add_child(zombie)
	zombie.set("flock_separation_vector", Vector3(-8.0, 0.0, 3.0))
	zombie.indoor_router.has_route = true
	var desired := Vector3(2.0, 0.0, 0.0)
	var push: Vector3 = zombie.call("_flock_push", desired)
	var max_push := float(zombie.get("speed")) * 0.5 + 0.001
	zombie.free()
	if push.dot(desired) < -0.001 or push.length() > max_push:
		_fail(test_root, "Empurrao do bando %s nao pode frear a rota %s nem passar de %.2f m/s." % [push, desired, max_push])
		return
	print("PASS: Separacao da horda nao empurra zumbis de volta para os cantos.")


func _test_navigation_path_reaches_top_floor(test_root: Node) -> void:
	print("Testando caminho do navmesh da rua ate o ultimo andar...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	var building := _add_building(test_root, blueprint, Vector3(600.0, 0.16, 600.0))
	var navigation = await _wait_navigation(test_root, building)
	var top_floor_y: float = building.global_position.y + float(blueprint.floors - 1) * blueprint.floor_height
	var from := building.global_position + Vector3(blueprint.width * 0.5, 0.0, -1.5)
	var to := building.global_position + Vector3(APARTMENT_LIVING_POINT.x, float(blueprint.floors - 1) * blueprint.floor_height, APARTMENT_LIVING_POINT.y)
	var path: PackedVector3Array = navigation.get_path_between(from, to)
	building.queue_free()
	if path.is_empty() or absf(path[path.size() - 1].y - top_floor_y) > 0.5:
		_fail(test_root, "Caminho deveria chegar ao andar %d (y=%.1f); pontos=%d fim=%s." % [blueprint.floors - 1, top_floor_y, path.size(), path[path.size() - 1] if not path.is_empty() else null])
		return
	print("PASS: Navmesh liga a porta da rua ao ultimo andar pelos lances.")


func _test_zombie_climbs_to_top_floor(test_root: Node) -> void:
	print("Testando zumbi subindo todos os lances ate o jogador...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	var building := _add_building(test_root, blueprint, Vector3(-600.0, 0.16, 600.0))
	await _wait_navigation(test_root, building)
	_destroy_all_doors(building)
	var top_level: float = float(blueprint.floors - 1) * blueprint.floor_height
	var player := _add_bait_player(test_root, building.global_position + Vector3(APARTMENT_LIVING_POINT.x, top_level + 1.4, APARTMENT_LIVING_POINT.y))
	var zombie := _add_walker_zombie(test_root, building.global_position + Vector3(10.0, 1.3, 4.0))
	await test_root.get_tree().physics_frame
	var reached: bool = await _step_until(test_root, zombie, 4200, func() -> bool: return zombie.global_position.y - building.global_position.y >= top_level + 0.5)
	var final_height := zombie.global_position.y - building.global_position.y
	zombie.queue_free()
	player.queue_free()
	building.queue_free()
	if not reached:
		_fail(test_root, "Zumbi deveria subir ate o andar %d (y>=%.1f); parou em y=%.2f." % [blueprint.floors - 1, top_level + 0.5, final_height])
		return
	print("PASS: Zumbi sobe a escada andar por andar sem travar.")


func _test_zombie_descends_to_street(test_root: Node) -> void:
	print("Testando zumbi descendo todos os lances ate a rua...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	var building := _add_building(test_root, blueprint, Vector3(-600.0, 0.16, -600.0))
	await _wait_navigation(test_root, building)
	_destroy_all_doors(building)
	var top_level: float = float(blueprint.floors - 1) * blueprint.floor_height
	var player := _add_bait_player(test_root, building.global_position + Vector3(10.0, 1.4, -6.0))
	var zombie := _add_walker_zombie(test_root, building.global_position + Vector3(APARTMENT_LIVING_POINT.x, top_level + 1.3, APARTMENT_LIVING_POINT.y))
	await test_root.get_tree().physics_frame
	var reached: bool = await _step_until(test_root, zombie, 4200, func() -> bool: return zombie.global_position.z < building.global_position.z - 0.5)
	var final_position := zombie.global_position - building.global_position
	zombie.queue_free()
	player.queue_free()
	building.queue_free()
	if not reached:
		_fail(test_root, "Zumbi do andar %d deveria descer e sair pela portaria; parou em %s." % [blueprint.floors - 1, final_position])
		return
	print("PASS: Zumbi desce a escada sem travar no degrau de chegada.")


func _test_player_climbs_to_roof_terrace(test_root: Node) -> void:
	print("Testando jogador subindo a escada ate o terraco...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(APARTMENT_SEED, "apartment")
	var building := _add_building(test_root, blueprint, Vector3(0.0, 0.16, 900.0))
	var navigation = await _wait_navigation(test_root, building)
	_destroy_all_doors(building)
	var terrace_level: float = float(blueprint.floors) * blueprint.floor_height
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("is_local_controller", false)
	# Comeca no saguao: o mundo de teste nao tem chao fora do edificio.
	player.position = building.global_position + Vector3(blueprint.width * 0.5, 1.4, 2.5)
	test_root.add_child(player)
	await test_root.get_tree().physics_frame
	var router = ROUTER_SCRIPT.new()
	var goal := building.global_position + Vector3(4.0, terrace_level, 12.0)
	var reached := false
	for step in 4200:
		var feet := player.global_position - Vector3.UP * 1.17
		var waypoint: Vector3 = router.next_waypoint(test_root.get_tree(), feet, goal, STEP_DELTA)
		var to_waypoint := Vector2(waypoint.x - feet.x, waypoint.z - feet.z)
		player.set("remote_input_age", 0.0)
		player.set("move_input", to_waypoint.normalized() if router.has_route and to_waypoint.length() > 0.05 else Vector2.ZERO)
		player.call("_physics_process", STEP_DELTA)
		if player.global_position.y - building.global_position.y >= terrace_level + 0.5:
			reached = true
			break
		if step % 30 == 29:
			await test_root.get_tree().process_frame
	var final_position := player.global_position - building.global_position
	player.queue_free()
	building.queue_free()
	if navigation == null or not reached:
		_fail(test_root, "Jogador (capsula maior) deveria subir ate o terraco (y>=%.1f); parou em %s." % [terrace_level + 0.5, final_position])
		return
	print("PASS: Jogador sobe todos os lances ate o terraco.")


func _test_zombie_leaves_house_breaking_doors(test_root: Node) -> void:
	print("Testando zumbi saindo da casa arrombando portas fechadas...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(HOUSE_SEED, "house")
	var building := _add_building(test_root, blueprint, Vector3(600.0, 0.16, -600.0))
	await _wait_navigation(test_root, building)
	var player := _add_bait_player(test_root, building.global_position + Vector3(5.0, 1.3, 20.0))
	var zombie := _add_walker_zombie(test_root, building.global_position + Vector3(8.5, 1.3, 5.2))
	await test_root.get_tree().physics_frame
	var house_rect := Rect2(building.global_position.x, building.global_position.z, blueprint.width, blueprint.depth)
	var escaped: bool = await _step_until(test_root, zombie, 2400, func() -> bool: return not house_rect.has_point(Vector2(zombie.global_position.x, zombie.global_position.z)))
	var opened_without_breaking := false
	var broken_doors := 0
	for door in building.find_children("Door_*", "AnimatableBody3D", true, false):
		broken_doors += 1 if bool(door.get("is_destroyed")) else 0
		opened_without_breaking = opened_without_breaking or (bool(door.get("is_open")) and not bool(door.get("is_destroyed")))
	var final_position := zombie.global_position - building.global_position
	zombie.queue_free()
	player.queue_free()
	building.queue_free()
	if not escaped or broken_doors == 0:
		_fail(test_root, "Zumbi deveria sair da casa quebrando portas; saiu=%s portas_quebradas=%d posicao=%s." % [escaped, broken_doors, final_position])
		return
	if opened_without_breaking:
		_fail(test_root, "Zumbi nao pode abrir porta sem destrui-la.")
		return
	print("PASS: Zumbi preso sai pela rota da porta, quebrando %d porta(s) sem abri-las." % broken_doors)


func _step_until(test_root: Node, zombie: CharacterBody3D, max_steps: int, is_done: Callable) -> bool:
	# Passos manuais: move_and_slide consulta o espaco fisico direto, entao a
	# simulacao de dezenas de segundos roda rapido. A cada bloco o teste cede um
	# frame para aplicar chamadas diferidas (ex.: colisao de porta quebrada).
	for step in max_steps:
		zombie.call("_physics_process", STEP_DELTA)
		if bool(is_done.call()):
			return true
		if step % 30 == 29:
			await test_root.get_tree().process_frame
	return false


func _add_building(test_root: Node, blueprint, position: Vector3) -> StaticBody3D:
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	building.position = position
	test_root.add_child(building)
	return building


func _wait_navigation(test_root: Node, building: StaticBody3D):
	var navigation = building.get_node("BuildingNavigation")
	for _frame in 120:
		if navigation.is_ready():
			return navigation
		await test_root.get_tree().physics_frame
	_fail(test_root, "Navmesh do edificio %s nao sincronizou em 120 frames de fisica." % building.name)
	return navigation


func _destroy_all_doors(building: StaticBody3D) -> void:
	for door in building.find_children("Door_*", "AnimatableBody3D", true, false):
		door.take_damage(int(door.get("max_health")), Vector3.FORWARD, "melee", null)


func _add_bait_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	return player


## Zumbi classico (tipo 0) para que velocidade e silhueta sejam deterministicas.
## Zumbi WALKER de teste. A variante vem de `forced_variant`, nao do hash do
## nome.
##
## Antes o nome era escolhido justamente para o hash cair em WALKER, mas os tres
## testes deste arquivo calculavam o MESMO nome. Quando o queue_free do zumbi
## anterior ainda nao tinha sido processado, o Godot renomeava o novo por
## colisao de irmao, o hash mudava junto e o zumbi nascia de outra variante — um
## rastejante nao sobe escada. Era essa a falha intermitente do teste da escada
## (media de 1 em 4 execucoes), que nunca reproduzia sozinha.
func _add_walker_zombie(test_root: Node, position: Vector3) -> CharacterBody3D:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	# Antes de entrar na arvore: o _ready le forced_variant para montar o corpo.
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	_walker_serial += 1
	zombie.name = "NavWalker%d" % _walker_serial
	zombie.position = position
	test_root.add_child(zombie)
	return zombie


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
