extends RefCounted

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const SPLIT_SCREEN_MANAGER_SCRIPT := preload("res://scripts/split_screen_manager.gd")
const MODULAR_BUILDING_BUILDER_SCRIPT := preload("res://scripts/modular_building_builder.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const ZOMBIE_SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const PERFORMANCE_HUD_SCRIPT := preload("res://scripts/performance_hud.gd")
const PROCEDURAL_CITY_GENERATOR: GDScript = preload("res://scripts/procedural/generators/city_generator.gd")
const PROCEDURAL_BUILDING_GENERATOR: GDScript = preload("res://scripts/procedural/generators/building_generator.gd")
const PROCEDURAL_BUILDING_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/building_assembler.gd")


## Runs focused regressions for bot tactics, spawning, HUDs and horde physics.
## Usage: GameplayRegressionTests.new().run(test_root)
func run(test_root: Node) -> void:
	if not test_root.has_meta("unit_test_failed"):
		test_root.set_meta("unit_test_failed", false)
	_test_careful_melee_approach(test_root)
	_test_public_server_port(test_root)
	_test_server_port_validation(test_root)
	_test_procedural_city_seed(test_root)
	_test_latency_hud(test_root)
	_test_hud_alive_zombie_count(test_root)
	_test_enterable_building_spawn_marker(test_root)
	_test_no_street_zombie_starts(test_root)
	_test_spawn_locations_avoid_streets(test_root)
	_test_network_zombie_starts_at_snapshot(test_root)
	_test_main_uses_mixed_spawn_policy(test_root)
	_test_ragdoll_neck_limits(test_root)
	_test_hordes_merge_under_one_brain(test_root)
	_test_horde_drones_follow_brain(test_root)


func _test_public_server_port(test_root: Node) -> void:
	print("Testando porta UDP publica padrao...")
	if NetworkSession.DEFAULT_PORT != 27015:
		_fail(test_root, "Porta publica esperava 27015; padrao=%d configurada=%d." % [
			NetworkSession.DEFAULT_PORT,
			NetworkSession.server_port,
		])
		return
	print("PASS: Porta UDP publica padrao validada.")


func _test_server_port_validation(test_root: Node) -> void:
	print("Testando validacao de porta UDP configuravel...")
	var valid_port := NetworkSession.parse_server_port_value("32000")
	var invalid_text := NetworkSession.parse_server_port_value("abc")
	var invalid_range := NetworkSession.parse_server_port_value("65536")
	var valid_seed: Variant = NetworkSession.parse_world_seed_value("18273")
	var invalid_seed: Variant = NetworkSession.parse_world_seed_value("cidade")
	if valid_port != 32000 or invalid_text != -1 or invalid_range != -1 or valid_seed != 18273 or invalid_seed != null:
		_fail(test_root, "Parsers devem aceitar porta e seed decimais e rejeitar valores invalidos.")
		return
	print("PASS: Validacao de porta UDP configuravel validada.")


func _test_procedural_city_seed(test_root: Node) -> void:
	print("Testando cidade procedural deterministica e conectividade dos interiores...")
	var first_city = PROCEDURAL_CITY_GENERATOR.generate_world(18273)
	var same_city = PROCEDURAL_CITY_GENERATOR.generate_world(18273)
	var other_city = PROCEDURAL_CITY_GENERATOR.generate_world(67890)
	if first_city.signature() != same_city.signature():
		_fail(test_root, "A mesma seed deveria produzir o mesmo blueprint de cidade.")
		return
	if first_city.signature() == other_city.signature():
		_fail(test_root, "Seeds diferentes deveriam produzir blueprints diferentes.")
		return
	if first_city.roads.size() != 8 or first_city.blocks.size() != 9 or first_city.building_count() != 35:
		_fail(test_root, "A cidade procedural deveria conter 35 edificios e um lote reservado para a Safehouse.")
		return
	var archetypes: Dictionary = {}
	for block in first_city.blocks:
		for lot in block.lots:
			if lot.building == null:
				continue
			archetypes[lot.building.archetype] = true
			for floor_blueprint in lot.building.floor_blueprints:
				for placement in floor_blueprint.units:
					var unit = placement["blueprint"]
					if not unit.is_graph_connected():
						_fail(test_root, "Unidade %s possui comodos desconectados." % unit.archetype)
						return
	if not archetypes.has("Shop_A") or not archetypes.has("Grocery_A"):
		_fail(test_root, "A zona urbana deveria misturar apartamentos, lojas e mercados.")
		return
	var visual_root := Node3D.new()
	var apartment = PROCEDURAL_BUILDING_GENERATOR.generate(18273, "apartment")
	var apartment_node: StaticBody3D = PROCEDURAL_BUILDING_ASSEMBLER.assemble(apartment)
	visual_root.add_child(apartment_node)
	if apartment_node.get_child_count() < 20:
		_fail(test_root, "Assembler deveria criar geometria e colisoes para um predio.")
		visual_root.free()
		return
	var cutout_found := false
	for child in apartment_node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh.material is ShaderMaterial:
			cutout_found = true
			break
	if not cutout_found:
		_fail(test_root, "Predios procedurais deveriam usar o shader da aura de visibilidade.")
		visual_root.free()
		return
	if not apartment_node.has_node("Stair_0_0") or not apartment_node.has_node("Stair_1_0") or not apartment_node.has_node("Floor_1_Left"):
		_fail(test_root, "Predio de varios andares deveria possuir escadas por transicao e vao de laje.")
		visual_root.free()
		return
	visual_root.free()
	print("PASS: Cidade procedural deterministica e interiores conectados validados.")


func _test_latency_hud(test_root: Node) -> void:
	print("Testando indicador de ping no HUD...")
	var previous_latency := NetworkSession.latency_ms
	NetworkSession.latency_ms = 42
	var hud := Label.new()
	hud.set_script(PERFORMANCE_HUD_SCRIPT)
	test_root.add_child(hud)
	var hud_text: String = hud.call("_build_text")
	if not hud_text.contains("ping 42 ms"):
		_fail(test_root, "HUD deveria exibir a latencia medida; texto=%s." % hud_text)
		hud.free()
		NetworkSession.latency_ms = previous_latency
		return
	hud.free()
	NetworkSession.latency_ms = previous_latency
	print("PASS: Indicador de ping no HUD validado.")


func _test_careful_melee_approach(test_root: Node) -> void:
	print("Testando aproximacao cautelosa dos bots no combate corpo a corpo...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	player.pistol_ammo = 0
	player.reserve_ammo = 0
	test_root.add_child(player)
	var zombies := Node3D.new()
	test_root.add_child(zombies)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.position = Vector3(8.0, 0.0, 0.0)
	zombies.add_child(zombie)

	var bot_ai := PlayerBotAI.new()
	var inputs: Array = bot_ai.collect_inputs([player], zombies, test_root.get_tree())
	var movement := inputs[0]["move"] as Vector2
	if bool(inputs[0]["sprint"]) or movement.x < 0.4 or absf(movement.y) < 0.2:
		_fail(test_root, "Bot melee deve aproximar em diagonal sem correr; movimento=%s sprint=%s." % [movement, inputs[0]["sprint"]])
		return

	player.free()
	zombies.free()
	print("PASS: Aproximacao cautelosa dos bots validada.")


func _test_hud_alive_zombie_count(test_root: Node) -> void:
	print("Testando contador de zumbis vivos no HUD...")
	var alive_before := test_root.get_tree().get_nodes_in_group("zombies").size()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	test_root.add_child(player)
	var zombie_a := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	var zombie_b := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(zombie_a)
	test_root.add_child(zombie_b)
	var split_screen := SPLIT_SCREEN_MANAGER_SCRIPT.new() as Control
	test_root.add_child(split_screen)
	var players: Array[Node] = [player]
	split_screen.configure(players)
	split_screen._process(0.0)
	var expected_text := "Zumbis: %d" % (alive_before + 2)
	var hud_text: String = split_screen.hud_labels[0].text
	if not hud_text.contains(expected_text):
		_fail(test_root, "HUD deveria exibir '%s'; texto=%s." % [expected_text, hud_text])
		return

	zombie_a.remove_from_group("zombies")
	split_screen._process(0.0)
	expected_text = "Zumbis: %d" % (alive_before + 1)
	if not split_screen.hud_labels[0].text.contains(expected_text):
		_fail(test_root, "HUD deve retirar zumbis mortos do contador; esperado=%s." % expected_text)
		return

	split_screen.free()
	player.free()
	zombie_a.free()
	zombie_b.free()
	print("PASS: Contador de zumbis vivos no HUD validado.")


func _test_enterable_building_spawn_marker(test_root: Node) -> void:
	print("Testando marcador de spawn dentro de predio modular...")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	var building := MODULAR_BUILDING_BUILDER_SCRIPT.build_procedural_building("house", rng) as StaticBody3D
	test_root.add_child(building)
	var marker := building.get_node_or_null("ZombieInteriorSpawn") as Marker3D
	if marker == null or not marker.is_in_group("zombie_interior_spawn"):
		_fail(test_root, "Predio modular entravel deve registrar um marcador interno de spawn.")
		return
	if absf(marker.position.x) > 0.01 or marker.position.z <= 0.0 or marker.position.y < 1.0:
		_fail(test_root, "Marcador interno deve ficar no corredor livre da entrada; posicao=%s." % marker.position)
		return

	building.free()
	print("PASS: Marcador interno de predio modular validado.")


func _test_no_street_zombie_starts(test_root: Node) -> void:
	print("Testando ausencia de zumbis iniciais nas ruas...")
	var main_world := MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	main_world.set_physics_process(false)
	test_root.add_child(main_world)
	var zombies := main_world.get_node("Zombies") as Node3D
	if zombies.get_child_count() != 0:
		_fail(test_root, "Cena principal nao deve conter zumbis autorados nas ruas; encontrados=%d." % zombies.get_child_count())
		return

	main_world.free()
	print("PASS: Cena principal inicia sem zumbis nas ruas.")


func _test_spawn_locations_avoid_streets(test_root: Node) -> void:
	print("Testando selecao de spawn interno ou na floresta distante...")
	var marker := Marker3D.new()
	marker.position = Vector3(60.0, 1.0, 60.0)
	marker.add_to_group("zombie_interior_spawn")
	test_root.add_child(marker)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var locator := ZOMBIE_SPAWN_LOCATOR_SCRIPT.new(rng)
	var saw_interior := false
	for _attempt in 40:
		var spawn_position: Vector3 = locator.pick_spawn_position(test_root.get_tree())
		if spawn_position.distance_to(marker.global_position) < 0.01:
			saw_interior = true
			continue
		var radius := Vector2(spawn_position.x, spawn_position.z).length()
		if radius < 100.0 or radius > 112.0:
			_fail(test_root, "Spawn fora de interior autorizado e floresta; posicao=%s." % spawn_position)
			return
	if not saw_interior:
		_fail(test_root, "Politica mista deve utilizar interiores autorizados quando estao livres.")
		return

	marker.free()
	print("PASS: Spawns restritos a interiores autorizados ou floresta.")


func _test_network_zombie_starts_at_snapshot(test_root: Node) -> void:
	print("Testando posicao inicial de replica de zumbi...")
	var main_world := MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	main_world.set_physics_process(false)
	test_root.add_child(main_world)
	var expected_position := Vector3(104.0, 1.0, -12.0)
	main_world.call("_apply_zombie_states", [{"name": "NetworkSpawnTest", "position": expected_position}])
	var replica := main_world.get_node("Zombies/NetworkSpawnTest") as CharacterBody3D
	if replica.global_position.distance_to(expected_position) > 0.01:
		_fail(test_root, "Replica apareceu em %s antes de interpolar para %s." % [replica.global_position, expected_position])
		return

	main_world.free()
	print("PASS: Replica nasce diretamente na posicao autoritativa.")


func _test_main_uses_mixed_spawn_policy(test_root: Node) -> void:
	print("Testando integracao da politica mista na partida...")
	var main_world := MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	main_world.set_physics_process(false)
	test_root.add_child(main_world)
	var saw_interior := false
	for _attempt in 40:
		main_world.call("_spawn_zombie")
		var spawned := main_world.get_node("Zombies").get_child(-1) as CharacterBody3D
		var radius := Vector2(spawned.global_position.x, spawned.global_position.z).length()
		if radius < 100.0:
			saw_interior = true
		elif radius > 112.0:
			_fail(test_root, "Partida criou zumbi fora de interior e floresta; posicao=%s." % spawned.global_position)
			return
	if not saw_interior:
		_fail(test_root, "Partida deve usar marcadores internos alem da floresta.")
		return

	main_world.free()
	print("PASS: Partida usa apenas interiores autorizados e floresta.")


func _test_ragdoll_neck_limits(test_root: Node) -> void:
	print("Testando limites fisicos do pescoco do ragdoll...")
	var ragdoll := RAGDOLL_SCENE.instantiate() as Node3D
	test_root.add_child(ragdoll)
	var neck := ragdoll.get_node_or_null("NeckJoint") as ConeTwistJoint3D
	if neck == null:
		_fail(test_root, "Pescoco deve usar ConeTwistJoint3D para impedir a cabeca de atravessar o torso.")
		return
	if neck.swing_span > deg_to_rad(35.0) or neck.twist_span > deg_to_rad(45.0):
		_fail(test_root, "Limites cervicais muito soltos; swing=%.2f twist=%.2f." % [rad_to_deg(neck.swing_span), rad_to_deg(neck.twist_span)])
		return
	if neck.basis.x.normalized().dot(Vector3.UP) < 0.99:
		_fail(test_root, "Eixo de torcao do pescoco deve acompanhar o eixo vertical.")
		return

	ragdoll.free()
	print("PASS: Cabeca do ragdoll limitada acima do torso.")


func _test_hordes_merge_under_one_brain(test_root: Node) -> void:
	print("Testando fusao de hordas sob um unico cerebro...")
	var coordinator := FLOCK_COORDINATOR_SCRIPT.new() as Node
	test_root.add_child(coordinator)
	var zombies := Node3D.new()
	test_root.add_child(zombies)
	var first_horde: Array[CharacterBody3D] = []
	var second_horde: Array[CharacterBody3D] = []
	for index in 2:
		var first := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		first.position = Vector3(float(index), 1.0, 0.0)
		zombies.add_child(first)
		first_horde.append(first)
		var second := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		second.position = Vector3(64.0 + float(index), 1.0, 0.0)
		zombies.add_child(second)
		second_horde.append(second)
	coordinator._physics_process(0.2)
	var first_leader := _find_horde_leader(first_horde)
	var second_leader := _find_horde_leader(second_horde)
	var first_horde_value: Variant = first_horde[0].get("horde_id")
	var second_horde_value: Variant = second_horde[0].get("horde_id")
	if not first_horde_value is int or not second_horde_value is int:
		coordinator.free()
		zombies.free()
		_fail(test_root, "Zumbis devem receber uma identidade persistente de horda.")
		return
	var first_horde_id := int(first_horde_value)
	var second_horde_id := int(second_horde_value)
	if first_leader == null or second_leader == null or first_horde_id <= 0 or first_horde_id == second_horde_id:
		_fail(test_root, "Hordas separadas devem manter identidade e um cerebro cada.")
		return

	for index in second_horde.size():
		second_horde[index].position = Vector3(2.0 + float(index), 1.0, 0.0)
	coordinator._physics_process(0.2)
	var merged_members: Array[CharacterBody3D] = first_horde + second_horde
	var merged_leader := _find_horde_leader(merged_members)
	var leader_count := 0
	for zombie in merged_members:
		leader_count += int(bool(zombie.get("is_cluster_leader")))
		if int(zombie.get("horde_id")) != int(merged_members[0].get("horde_id")):
			_fail(test_root, "Membros fundidos devem compartilhar a mesma identidade de horda.")
			return
	if leader_count != 1 or (merged_leader != first_leader and merged_leader != second_leader):
		_fail(test_root, "Fusao deve sortear um dos cerebros anteriores; lideres=%d." % leader_count)
		return

	coordinator.free()
	zombies.free()
	print("PASS: Hordas fundidas usam um unico cerebro persistente.")


func _test_horde_drones_follow_brain(test_root: Node) -> void:
	print("Testando drones sem percepcao independente...")
	var coordinator := FLOCK_COORDINATOR_SCRIPT.new() as Node
	test_root.add_child(coordinator)
	var members: Array[CharacterBody3D] = []
	for index in 2:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.position = Vector3(float(index), 1.0, 0.0)
		test_root.add_child(zombie)
		members.append(zombie)
	coordinator._physics_process(0.2)
	var leader := _find_horde_leader(members)
	var follower := members[1] if leader == members[0] else members[0]
	follower.call("hear_gunshot", follower.global_position, 65.0)
	if bool(follower.get("is_investigating_sound")):
		_fail(test_root, "Drone nao deve processar tiro sem o cerebro da horda.")
		return
	leader.call("hear_gunshot", leader.global_position, 65.0)
	coordinator._physics_process(0.2)
	if not bool(follower.get("is_investigating_sound")):
		_fail(test_root, "Drone deve copiar a investigacao sonora decidida pelo cerebro.")
		return
	leader.set("is_investigating_sound", false)
	leader.set("alert_target", null)
	coordinator._physics_process(0.2)
	if follower.get("alert_target") != null or bool(follower.get("is_investigating_sound")):
		_fail(test_root, "Drone deve esquecer alertas quando o cerebro encerra a investigacao.")
		return

	coordinator.free()
	for zombie in members:
		zombie.free()
	print("PASS: Somente o cerebro percebe e os drones obedecem.")


func _find_horde_leader(members: Array[CharacterBody3D]) -> CharacterBody3D:
	for zombie in members:
		if bool(zombie.get("is_cluster_leader")):
			return zombie
	return null


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
