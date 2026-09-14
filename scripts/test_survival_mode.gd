extends RefCounted

const SURVIVAL_WAVE_SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const SURVIVAL_WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const CITY_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/city_generator.gd")
const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const CITY_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/city_assembler.gd")
const DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")
const DOOR_NETWORK_STATE_SCRIPT := preload("res://scripts/door_network_state.gd")
const SAFEHOUSE_BUILDER_SCRIPT := preload("res://scripts/safehouse_builder.gd")
const WAVE_SUPPLY_CONTROLLER_SCRIPT := preload("res://scripts/wave_supply_controller.gd")
const SUPPLY_NETWORK_STATE_SCRIPT := preload("res://scripts/supply_network_state.gd")


func run(test_root: Node) -> void:
	_test_wave_schedule(test_root)
	_test_wave_controller(test_root)
	_test_wave_supplies(test_root)
	_test_survival_hud(test_root)
	_test_audio_streams(test_root)
	_test_ragdoll_appearance(test_root)
	_test_nearest_target_and_melee(test_root)
	_test_survival_city_layout(test_root)
	_test_house_gable_roof(test_root)
	_test_building_door_states(test_root)
	_test_building_door_network_state(test_root)


func _test_wave_schedule(test_root: Node) -> void:
	print("Testando progressao das ondas de sobrevivencia...")
	var schedule = SURVIVAL_WAVE_SCHEDULE_SCRIPT.new()
	var expected := [10, 20, 30, 40, 60, 80, 120, 140, 160]
	for index in expected.size():
		if schedule.target_for(index) != expected[index]:
			_fail(test_root, "Onda %d esperava %d zumbis." % [index + 1, expected[index]])
			return
	if schedule.target_for(schedule.wave_count() - 1) != 600 or not schedule.is_final_wave(schedule.wave_count() - 1):
		_fail(test_root, "A ultima onda deveria terminar em 600 zumbis.")
		return
	print("PASS: Progressao de ondas validada.")


func _test_wave_controller(test_root: Node) -> void:
	print("Testando controle autoritativo de uma onda...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(func() -> bool:
		return true
	)
	var started_waves: Array[int] = []
	controller.wave_started.connect(func(wave_index: int) -> void: started_waves.append(wave_index))
	for _index in 10:
		controller.tick(0.2)
	if controller.spawned_in_wave != 10 or controller.alive_in_wave != 10:
		_fail(test_root, "Controle deveria produzir 10 zumbis e manter 10 vivos; produziu %d/%d." % [controller.spawned_in_wave, controller.alive_in_wave])
		return
	for _index in 10:
		controller.register_death()
	controller.tick(0.01)
	if controller.wave_index != 1 or controller.total_kills != 10 or started_waves != [1]:
		_fail(test_root, "Controle deveria avançar para a segunda onda apos limpar a primeira.")
		return
	print("PASS: Controle de ondas e abates validado.")


func _test_wave_supplies(test_root: Node) -> void:
	print("Testando suprimentos internos renovados por onda...")
	var safehouse: StaticBody3D = SAFEHOUSE_BUILDER_SCRIPT.build_safehouse()
	test_root.add_child(safehouse)
	var safehouse_supplies: Array[Node] = []
	var health_count := 0
	var ammo_count := 0
	for child in safehouse.find_children("SafehouseSupplyPoint*", "Area3D", true, false):
		if not child.is_in_group("safehouse_supply_points"):
			continue
		safehouse_supplies.append(child)
		if int(child.get("supply_kind")) == 0:
			health_count += 1
		else:
			ammo_count += 1
	if safehouse_supplies.size() != 4 or health_count != 2 or ammo_count != 2:
		_fail(test_root, "Safehouse deveria ter quatro pontos por onda, dois de vida e dois de municao; total=%d vida=%d ammo=%d." % [safehouse_supplies.size(), health_count, ammo_count])
		safehouse.free()
		return
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(player)
	player.health = 50
	var health_supply := safehouse_supplies[0]
	health_supply.call("_on_body_entered", player)
	if player.health != 85 or bool(health_supply.get("is_available")):
		_fail(test_root, "Suprimento de vida deveria recuperar 35 pontos uma vez; vida=%d." % player.health)
		player.free()
		safehouse.free()
		return
	var supply_controller = WAVE_SUPPLY_CONTROLLER_SCRIPT.new(test_root.get_tree(), 240912)
	supply_controller.refresh_wave(1)
	for supply in safehouse_supplies:
		if not bool(supply.get("is_available")):
			_fail(test_root, "Os quatro suprimentos da Safehouse deveriam reaparecer a cada onda.")
			player.free()
			safehouse.free()
			return
	health_supply.call("set_available", false)
	var snapshot := SUPPLY_NETWORK_STATE_SCRIPT.collect(test_root.get_tree())
	health_supply.call("set_available", true)
	SUPPLY_NETWORK_STATE_SCRIPT.apply(test_root.get_tree(), snapshot)
	if bool(health_supply.get("is_available")):
		_fail(test_root, "Snapshot deveria restaurar o estado coletado de um suprimento.")
		player.free()
		safehouse.free()
		return
	player.free()
	safehouse.free()
	print("PASS: Vida, municao, quatro pontos da Safehouse e renovacao por onda validados.")


func _test_survival_hud(test_root: Node) -> void:
	print("Testando contador de horas e objetivo da sobrevivencia...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(func() -> bool:
		return true
	)
	var hud_text := controller.get_hud_text()
	if not hud_text.contains("Hora 1/31") or not hud_text.contains("Onda 1/31"):
		_fail(test_root, "HUD de sobrevivencia deveria mostrar a hora e a onda atuais.")
		return
	print("PASS: Contador de horas e objetivo de sobrevivencia validados.")


func _test_audio_streams(test_root: Node) -> void:
	print("Testando streams reais de tiro e gemido de zumbi...")
	if not AudioFeedback.has_audio_streams():
		_fail(test_root, "AudioFeedback deveria criar streams reais para tiro e gemido.")
		return
	print("PASS: Streams reais de audio disponiveis.")


func _test_ragdoll_appearance(test_root: Node) -> void:
	print("Testando preservacao da skin no ragdoll...")
	var ragdoll := RAGDOLL_SCENE.instantiate() as Node3D
	test_root.add_child(ragdoll)
	ragdoll.call("setup", Vector3.ZERO, 0, 12345)
	var torso := ragdoll.get_node("Torso/Mesh") as MeshInstance3D
	var material := torso.mesh.material as StandardMaterial3D
	var expected: Color = ZombieMutator.appearance_colors(12345)[1]
	if material.albedo_color != expected:
		_fail(test_root, "Ragdoll deveria preservar a cor de camisa da variante morta.")
		ragdoll.free()
		return
	ragdoll.free()
	print("PASS: Skin da variante preservada no ragdoll.")


func _test_nearest_target_and_melee(test_root: Node) -> void:
	print("Testando alvo mais proximo e ataque oportunista no multiplayer...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	var far_player := PLAYER_SCENE.instantiate() as CharacterBody3D
	var near_player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(zombie)
	test_root.add_child(far_player)
	test_root.add_child(near_player)
	zombie.position = Vector3.ZERO
	zombie.gravity = 0.0
	zombie.collision_mask = 0
	far_player.position = Vector3(0.0, 1.0, 8.0)
	near_player.position = Vector3(0.0, 1.0, 3.0)
	zombie.call("_update_senses", 0.25)
	if zombie.get("alert_target") != near_player:
		_fail(test_root, "Zumbi deveria escolher o jogador vivo mais proximo.")
		zombie.free()
		far_player.free()
		near_player.free()
		return
	var previous_health: int = near_player.health
	zombie.set("alert_target", far_player)
	zombie.set("target_switch_cooldown", 1.0)
	near_player.position = Vector3(0.0, 0.8, 0.8)
	zombie.call("_physics_process", 0.01)
	if near_player.health >= previous_health or zombie.get("alert_target") != far_player:
		_fail(test_root, "Zumbi deveria atacar jogador proximo sem trocar alvo; vida=%d, ataque=%d, alvo=%s." % [near_player.health, zombie.attack_sequence, zombie.alert_target.name if zombie.alert_target != null else "null"])
		zombie.free()
		far_player.free()
		near_player.free()
		return
	var upper_floor_health: int = near_player.health
	near_player.position = Vector3(0.0, 3.8, 0.8)
	zombie.set("alert_target", near_player)
	zombie.set("sense_check_cooldown", 1.0)
	zombie.set("attack_cooldown", 0.0)
	zombie.call("_physics_process", 0.01)
	if near_player.health != upper_floor_health:
		_fail(test_root, "Zumbi nao deveria atingir jogador em outro andar fora do alcance vertical: vida=%d/%d, zumbi_y=%.2f, jogador_y=%.2f." % [near_player.health, upper_floor_health, zombie.global_position.y, near_player.global_position.y])
		zombie.free()
		far_player.free()
		near_player.free()
		return
	print("PASS: Alcance melee respeita a separacao entre andares.")
	zombie.free()
	far_player.free()
	near_player.free()
	print("PASS: Alvo estavel e ataque oportunista validados.")


func _test_survival_city_layout(test_root: Node) -> void:
	print("Testando proporcao de casas, predios altos e escadas do mapa...")
	var city = CITY_GENERATOR_SCRIPT.generate_world(240912, true)
	var house_count := 0
	var tall_building_count := 0
	var street_facing_rotations: Dictionary = {}
	for block in city.blocks:
		for lot in block.lots:
			if lot.building == null:
				continue
			if lot.building.archetype.begins_with("House"):
				house_count += 1
				street_facing_rotations[lot.building_rotation_y] = true
				if lot.building.floors != 1:
					_fail(test_root, "Casa de sobrevivencia deveria ter apenas um piso.")
			elif lot.building.archetype.begins_with("ApartmentBuilding"):
				tall_building_count += 1
				if lot.building.floors < 2:
					_fail(test_root, "Predio alto deveria possuir ao menos dois pisos.")
	if house_count <= 20 or tall_building_count > 3:
		_fail(test_root, "Mapa deveria priorizar casas e limitar predios altos: casas=%d, altos=%d." % [house_count, tall_building_count])
		return
	if not street_facing_rotations.has(0.0) or not street_facing_rotations.has(PI):
		_fail(test_root, "Casas deveriam orientar suas entradas para ambos os lados das ruas.")
		return
	print("PASS: Mapa prioriza casas e limita predios altos com escadas coerentes.")


func _test_building_door_states(test_root: Node) -> void:
	print("Testando estados aberto/fechado e resistencia das portas...")
	var door = DOOR_SCRIPT.new()
	door.configure(Vector3(1.4, 2.6, 0.12), null)
	if door.is_open:
		_fail(test_root, "Porta comum deveria iniciar fechada.")
		return
	door.interact()
	if not door.is_open:
		_fail(test_root, "Interacao deveria abrir a porta comum.")
		return
	door.interact()
	if door.is_open:
		_fail(test_root, "Segunda interacao deveria fechar a porta comum.")
		return
	door.take_damage(door.max_health)
	if not door.is_open or not door.is_destroyed:
		_fail(test_root, "Dano de zumbi deveria destruir e abrir a porta comum.")
		return
	door.interact()
	if not door.is_open:
		_fail(test_root, "Porta destruida deveria permanecer aberta.")
		return
	door.free()
	print("PASS: Estados e resistencia das portas validados.")


func _test_house_gable_roof(test_root: Node) -> void:
	print("Testando telhado inclinado das casas...")
	var house_blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(house_blueprint)
	test_root.add_child(house)
	if not house.has_node("RoofLeftSlope") or not house.has_node("RoofRightSlope"):
		_fail(test_root, "Casa procedural deveria possuir telhado de duas aguas.")
		house.free()
		return
	if is_zero_approx((house.get_node("RoofLeftSlope") as MeshInstance3D).rotation.z):
		_fail(test_root, "Telhado da casa deveria possuir inclinacao visivel.")
		house.free()
		return
	var doors := house.find_children("Door_*", "AnimatableBody3D", true, false)
	if doors.is_empty() or not (doors[0] as AnimatableBody3D).has_node("DoorKnob"):
		_fail(test_root, "Casa procedural deveria possuir porta externa visivel com macaneta.")
		house.free()
		return
	for furniture_name in ["FurnitureLivingTable", "FurnitureKitchenCounter", "FurnitureBathroomMirror", "FurnitureBed_bedroom_a", "FurnitureWardrobe_bedroom_b", "InteriorLight"]:
		if not house.has_node(furniture_name):
			_fail(test_root, "Interior residencial deveria possuir '%s'." % furniture_name)
			house.free()
			return
	for floor_blueprint in house_blueprint.floor_blueprints:
		for placement in floor_blueprint.units:
			for door in placement["blueprint"].doors:
				if door.get("room_b", "") != "outside" and float(door.get("width", 0.0)) < 1.4:
					_fail(test_root, "Passagem interna deveria ter ao menos 1.4 m; porta=%s." % door)
					house.free()
					return
	if house.find_children("Interior*Supply", "Area3D", true, false).size() != 1:
		_fail(test_root, "Cada predio procedural deveria possuir um ponto de suprimento interno.")
		house.free()
		return
	CITY_ASSEMBLER_SCRIPT._configure_building_cutout(house, house_blueprint)
	var roof_material := ((house.get_node("RoofLeftSlope") as MeshInstance3D).mesh as PrimitiveMesh).material as ShaderMaterial
	if roof_material == null or not bool(roof_material.get_shader_parameter("use_building_bounds")):
		_fail(test_root, "Recorte da casa deveria conhecer os limites do predio.")
		house.free()
		return
	house.free()
	print("PASS: Telhado, porta, interior mobiliado e limites de recorte validados.")


func _test_building_door_network_state(test_root: Node) -> void:
	print("Testando replicacao das portas comuns...")
	var door = DOOR_SCRIPT.new()
	door.name = "NetworkDoor"
	test_root.add_child(door)
	door.interact()
	var states := DOOR_NETWORK_STATE_SCRIPT.collect(test_root.get_tree())
	door.apply_network_state(false, false)
	DOOR_NETWORK_STATE_SCRIPT.apply(test_root.get_tree(), states)
	if not door.is_open:
		_fail(test_root, "Snapshot do servidor deveria abrir a porta no cliente.")
		door.free()
		return
	door.free()
	print("PASS: Estado autoritativo das portas comuns validado.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
