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
	_test_airdrop_schedule(test_root)
	_test_airdrop_drop_and_pickup(test_root)
	_test_ground_weapon_sync(test_root)
	_test_crate_expires(test_root)
	_test_ground_supply_pickup(test_root)
	_test_building_lights_toggle(test_root)
	_test_client_wave_sync(test_root)
	_test_variant_mix(test_root)
	_test_forced_variant_spawn(test_root)
	_test_wave_controller(test_root)
	_test_wave_supplies(test_root)
	_test_survival_hud(test_root)
	_test_audio_streams(test_root)
	_test_ragdoll_appearance(test_root)
	_test_nearest_target_and_melee(test_root)
	_test_survival_city_layout(test_root)
	_test_house_gable_roof(test_root)
	_test_house_windows_are_glazed_openings(test_root)
	_test_house_doorways_are_clear(test_root)
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


## Ondas de airdrop e conteudo deterministico do crate.
func _test_airdrop_schedule(test_root: Node) -> void:
	print("Testando agenda de airdrop de armas...")
	var schedule = SURVIVAL_WAVE_SCHEDULE_SCRIPT.new()
	for wave_index in [2, 6, 10, 14]:
		if not schedule.is_airdrop_wave(wave_index):
			_fail(test_root, "Onda %d deveria ser de airdrop." % wave_index)
			return
	if schedule.is_airdrop_wave(0) or schedule.is_airdrop_wave(3):
		_fail(test_root, "Ondas fora da lista nao deveriam cair crate.")
		return
	var hora_3 := schedule.crate_kinds_for_wave(2, 777)
	if hora_3 != [WeaponStats.Kind.SHOTGUN]:
		_fail(test_root, "Hora 3 deveria cair escopeta; veio %s." % hora_3)
		return
	var hora_7 := schedule.crate_kinds_for_wave(6, 777)
	if hora_7 != [WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI]:
		_fail(test_root, "Hora 7 deveria cair escopeta + Uzi; veio %s." % hora_7)
		return
	var hora_11 := schedule.crate_kinds_for_wave(10, 777)
	if hora_11 != [WeaponStats.Kind.UZI, WeaponStats.Kind.MAGNUM]:
		_fail(test_root, "Hora 11 deveria cair Uzi + Magnum; veio %s." % hora_11)
		return
	var first := schedule.crate_kinds_for_wave(18, 555)
	var second := schedule.crate_kinds_for_wave(18, 777)
	if first != second and first.is_empty():
		_fail(test_root, "Sorteio das ondas altas deveria ser deterministico por seed.")
		return
	print("PASS: Agenda de airdrop validada.")


## Crate desce, coleta por interacao entrega uma arma por pegada e a troca
## dropa a da mao. Uso: roda na suite.
## Crate BR-style: cai, abre e ejeta as armas no chao; cada pickup entrega
## uma arma por interacao e o slot cheio troca.
func _test_airdrop_drop_and_pickup(test_root: Node) -> void:
	print("Testando crate de airdrop que abre e ejeta armas...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	player.position = Vector3(0.0, 1.0, 0.0)
	test_root.add_child(player)
	var crate := AirSupplyPickup.new()
	crate.name = "AirCrateTest"
	crate.setup([WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI])
	test_root.add_child(crate)
	crate.global_position = Vector3(0.0, 0.7, 0.0)
	if not crate.is_in_group("ground_weapons"):
		_fail(test_root, "Crate deveria entrar no grupo ground_weapons.")
		player.free()
		crate.free()
		return
	crate.call("land")
	if not bool(crate.get("dropped")):
		_fail(test_root, "Crate deveria abrir ao aterrissar.")
		player.free()
		crate.free()
		return
	var ejected: Array = []
	for node in test_root.get_tree().get_nodes_in_group("ground_weapons"):
		if node is GroundWeaponPickup:
			ejected.append(node)
	if ejected.size() != 2:
		_fail(test_root, "Crate deveria ejectar 2 pickups de arma; saiu %d." % ejected.size())
		player.free()
		for node in ejected:
			node.free()
		crate.free()
		return
	# Primeira arma: entra no slot livre e equipa na mao.
	var first := ejected[0] as GroundWeaponPickup
	var first_result := String(first.call("interact_with", player))
	if first_result != "granted" or player.current_weapon != PlayerCharacter.Weapon.SHOTGUN:
		_fail(test_root, "Primeira pegada deveria entregar a escopeta; resultado=%s." % first_result)
		player.free()
		for node in ejected:
			node.free()
		crate.free()
		return
	# Segunda arma (slot cheio): troca e dropa a da mao no chao.
	var second := ejected[1] as GroundWeaponPickup
	var swap_result := String(second.call("interact_with", player))
	if swap_result != "swapped" or player.current_weapon != PlayerCharacter.Weapon.UZI:
		_fail(test_root, "Pegar Uzi com slot cheio deveria trocar; resultado=%s." % swap_result)
		player.free()
		for node in ejected:
			node.free()
		crate.free()
		return
	crate.free()
	for node in ejected:
		node.free()
	player.free()
	print("PASS: Crate de airdrop com armas espalhadas no chao validado.")


func _test_ground_weapon_sync(test_root: Node) -> void:
	print("Testando sync por nome das armas no chao...")
	var tree := test_root.get_tree()
	var crate := AirSupplyPickup.new()
	crate.name = "AirCrateSync"
	crate.setup([WeaponStats.Kind.SHOTGUN])
	test_root.add_child(crate)
	crate.global_position = Vector3(30.0, 0.0, -20.0)
	var pickup := GroundWeaponPickup.new()
	pickup.name = "GroundWeaponSync"
	pickup.setup(WeaponStats.Kind.MAGNUM, 4, 9, 22)
	test_root.add_child(pickup)
	pickup.global_position = Vector3(-15.0, 0.0, 40.0)
	var entries: Array = GroundWeaponSync.collect(tree)
	if entries.size() != 2:
		_fail(test_root, "Sync deveria coletar crate e dropada; coletou %d." % entries.size())
		crate.free()
		pickup.free()
		return
	crate.free()
	pickup.free()
	GroundWeaponSync.apply(tree, entries)
	var crate_names: Array[String] = []
	var restored_pickup: Node = null
	for node in tree.get_nodes_in_group("ground_weapons"):
		crate_names.append(String(node.name))
		if node is GroundWeaponPickup:
			restored_pickup = node
	if not (crate_names.has("AirCrateSync") and crate_names.has("GroundWeaponSync")):
		_fail(test_root, "Sync deveria recriar os nos pelo nome; nomes=%s." % crate_names)
		return
	if restored_pickup == null or int(restored_pickup.get("durability")) != 22:
		_fail(test_root, "Dropada recriada deveria preservar durabilidade no payload.")
		for node in tree.get_nodes_in_group("ground_weapons"):
			node.free()
		return
	# queue_free do apply e adiado para o fim do frame: aqui so garantimos
	# que nada foi recriado apos o snapshot vazio.
	GroundWeaponSync.apply(tree, [])
	for node in tree.get_nodes_in_group("ground_weapons"):
		if not node.is_queued_for_deletion():
			_fail(test_root, "Snapshot sem armas deveria marcar as coletadas para remocao.")
			break
		node.free()
	print("PASS: Sync por nome das armas no chao validado.")


## Cliente recebe o estado da onda por RPC e o HUD acompanha.
## Crate fica marcado e expira em lifetime_seconds sem coleta.
func _test_crate_expires(test_root: Node) -> void:
	print("Testando expiracao do crate sem coleta...")
	var crate := AirSupplyPickup.new()
	crate.name = "AirCrateExpire"
	crate.setup([WeaponStats.Kind.MAGNUM])
	crate.starts_landed = true
	crate.lifetime_seconds = 0.3
	test_root.add_child(crate)
	crate.global_position = Vector3(10.0, 0.02, 10.0)
	if not bool(crate.get("dropped")):
		_fail(test_root, "Crate aterrissado deveria iniciar pronto para coleta.")
		crate.free()
		return
	for _tick in 4:
		crate.call("_physics_process", 0.1)
	if not crate.is_queued_for_deletion():
		_fail(test_root, "Crate deveria expirar apos lifetime_seconds sem coleta.")
		crate.free()
		return
	crate.free()
	print("PASS: Expiracao do crate validada.")


## Item de vida/municao espalhado: coleta ao tocar e sync por nome (tipo 2).
func _test_ground_supply_pickup(test_root: Node) -> void:
	print("Testando itens de vida e municao espalhados...")
	var tree := test_root.get_tree()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	test_root.add_child(player)
	player.health = 50
	var item := GroundSupplyPickup.new()
	item.name = "LootSyncTest"
	item.setup(GroundSupplyPickup.Kind.HEALTH, 35)
	test_root.add_child(item)
	item.global_position = Vector3(5.0, 0.0, 5.0)
	if not item.is_in_group("ground_supplies"):
		_fail(test_root, "Item espalhado deveria entrar no grupo ground_supplies.")
		player.free()
		item.free()
		return
	item.call("_on_body_entered", player)
	if player.health != 85:
		_fail(test_root, "Item de vida deveria curar 35 ao tocar; vida=%d." % player.health)
		player.free()
		return
	# Vida cheia nao consome o item; ele fica para o proximo jogador.
	var full_player := PLAYER_SCENE.instantiate() as CharacterBody3D
	full_player.reads_local_input = false
	test_root.add_child(full_player)
	var second := GroundSupplyPickup.new()
	second.name = "LootSyncTest2"
	second.setup(GroundSupplyPickup.Kind.HEALTH, 35)
	test_root.add_child(second)
	second.global_position = Vector3(-5.0, 0.0, 5.0)
	second.call("_on_body_entered", full_player)
	if bool(second.is_queued_for_deletion()):
		_fail(test_root, "Item nao deveria ser consumido por jogador com vida cheia.")
	var entries: Array = GroundWeaponSync.collect(tree)
	var supply_entry: Array = []
	for entry in entries:
		if String(entry[0]) == "LootSyncTest2":
			supply_entry = entry
	if supply_entry.is_empty() or int(supply_entry[4]) != 2:
		_fail(test_root, "Sync deveria coletar suprimento com flag 2; entrada=%s." % supply_entry)
		player.free()
		full_player.free()
		item.free()
		second.free()
		return
	second.free()
	GroundWeaponSync.apply(tree, entries)
	var restored: Node = null
	for node in tree.get_nodes_in_group("ground_supplies"):
		if String(node.name) == "LootSyncTest2":
			restored = node
	if restored == null or int(restored.get("supply_kind")) != int(GroundSupplyPickup.Kind.HEALTH) or int(restored.get("amount")) != 35:
		_fail(test_root, "Suprimento recriado pelo sync deveria preservar tipo e quantidade.")
	player.free()
	full_player.free()
	item.free()
	for node in tree.get_nodes_in_group("ground_supplies"):
		node.free()
	print("PASS: Itens de vida e municao espalhados validados.")


## G7-fase1: toggle de luzes preserva no e o cache em meta reaproveita filhos.
func _test_building_lights_toggle(test_root: Node) -> void:
	print("Testando toggle de luzes de interior por predio...")
	var building := StaticBody3D.new()
	building.name = "BuildingLightTest"
	test_root.add_child(building)
	var light := OmniLight3D.new()
	light.name = "InteriorLight"
	light.position = Vector3(2.0, 2.8, 2.0)
	building.add_child(light)
	ProceduralBuildingAssembler.set_building_lights_enabled(building, false)
	if light.visible:
		_fail(test_root, "Toggle deveria apagar a luz de interior do predio.")
		building.free()
		return
	ProceduralBuildingAssembler.set_building_lights_enabled(building, true)
	if not light.visible:
		_fail(test_root, "Toggle deveria reacender a luz de interior.")
		building.free()
		return
	# Cache em meta: a segunda chamada nao refaz find_children.
	var cached: Variant = building.get_meta("light_cache", null)
	if not cached is Array or (cached as Array).size() != 1:
		_fail(test_root, "Cache de luzes deveria conter o filho unico.")
	building.free()
	print("PASS: Toggle de luzes de interior validado.")


func _test_client_wave_sync(test_root: Node) -> void:
	print("Testando sync de onda para o HUD do cliente...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new()
	controller.set_sync_state(3, 45)
	var hud_text := controller.get_hud_text()
	if not hud_text.contains("Hora 4") or not hud_text.contains("Abates: 45"):
		_fail(test_root, "HUD do cliente deveria refletir a onda sincronizada; texto=%s." % hud_text)
		return
	print("PASS: Sync de onda para o cliente validado.")


## Mix por fase soma 100 e pick_variant respeita as porcentagens.
func _test_variant_mix(test_root: Node) -> void:
	print("Testando mix percentual de variantes por fase...")
	var schedule = SURVIVAL_WAVE_SCHEDULE_SCRIPT.new()
	var early := schedule.variant_mix_for_wave(0)
	var mid := schedule.variant_mix_for_wave(3)
	var late := schedule.variant_mix_for_wave(7)
	var endgame := schedule.variant_mix_for_wave(12)
	for mix in [early, mid, late, endgame]:
		var total := 0
		for kind in mix:
			total += int(mix[kind])
		if total != 100:
			_fail(test_root, "Mix da fase deveria somar 100; somou %d." % total)
			return
	if not early.has(ZombieMutator.Type.WALKER) or early.get(ZombieMutator.Type.BRUTE, 0) != 0:
		_fail(test_root, "Hora 1-2 deveria ser horda basica sem brute.")
		return
	if mid.get(ZombieMutator.Type.SPRINTER, 0) == 0:
		_fail(test_root, "Hora 3+ deveria liberar sprinters.")
		return
	if late.get(ZombieMutator.Type.BRUTE, 0) == 0:
		_fail(test_root, "Hora 7+ deveria liberar o brute.")
		return
	if endgame.get(ZombieMutator.Type.SCREAMER, 0) == 0:
		_fail(test_root, "Hora 11+ deveria liberar o screamer.")
		return
	# Faixas acumuladas do mix final: walker 0-34, brute 83-92, screamer 93-99.
	if schedule.pick_variant(12, 0) != int(ZombieMutator.Type.WALKER):
		_fail(test_root, "Rolagem 0 deveria cair no walker (maior faixa).")
		return
	if schedule.pick_variant(12, 83) != int(ZombieMutator.Type.BRUTE) or schedule.pick_variant(12, 92) != int(ZombieMutator.Type.BRUTE):
		_fail(test_root, "Faixa do brute deveria cobrir rolagens 83-92.")
		return
	if schedule.pick_variant(12, 82) == int(ZombieMutator.Type.BRUTE):
		_fail(test_root, "Rolagem 82 deveria ficar fora da faixa do brute.")
		return
	if schedule.pick_variant(12, 93) != int(ZombieMutator.Type.SCREAMER):
		_fail(test_root, "Rolagem 93 deveria cair no screamer.")
		return
	print("PASS: Mix percentual de variantes validado.")


## Spawn respeita a variante forçada e aplica os stats da tabela.
func _test_forced_variant_spawn(test_root: Node) -> void:
	print("Testando variante forçada com stats de brute e screamer...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "ZombieForcedTest"
	zombie.simulation_enabled = false
	zombie.set("forced_variant", ZombieMutator.Type.BRUTE)
	test_root.add_child(zombie)
	if int(zombie.get("zombie_type")) != int(ZombieMutator.Type.BRUTE):
		_fail(test_root, "Zumbi deveria nascer brute com variante forçada.")
		zombie.free()
		return
	if int(zombie.get("max_health")) != 550 or float(zombie.get("speed")) > 1.3:
		_fail(test_root, "Brute deveria ter 550 de vida e andar devagar; vida=%s speed=%s." % [zombie.get("max_health"), zombie.get("speed")])
		zombie.free()
		return
	zombie.set("forced_variant", ZombieMutator.Type.SCREAMER)
	var screamer := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	screamer.name = "ZombieScreamerTest"
	screamer.simulation_enabled = false
	screamer.set("forced_variant", ZombieMutator.Type.SCREAMER)
	test_root.add_child(screamer)
	if int(screamer.get("zombie_type")) != int(ZombieMutator.Type.SCREAMER):
		_fail(test_root, "Zumbi deveria nascer screamer.")
		zombie.free()
		screamer.free()
		return
	# Grito atrai a horda: cooldown inicia e fire chama hear_gunshot no grupo.
	screamer.set("scream_cooldown", 0.0)
	screamer.call("_update_scream", 0.1)
	if float(screamer.get("scream_cooldown")) <= 0.0:
		_fail(test_root, "Grito deveria recarregar o cooldown do screamer.")
		zombie.free()
		screamer.free()
		return
	zombie.free()
	screamer.free()
	print("PASS: Variantes forçadas (brute e screamer) validadas.")


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
	# Longe da origem: testes anteriores deixam jogadores em (0, 1, 0).
	var origin := Vector3(-640.0, 0.0, 640.0)
	zombie.position = origin
	zombie.gravity = 0.0
	zombie.collision_mask = 0
	far_player.position = origin + Vector3(0.0, 1.0, 8.0)
	near_player.position = origin + Vector3(0.0, 1.0, 3.0)
	zombie.call("_update_senses", 0.25)
	if zombie.get("alert_target") != near_player:
		var chosen: Node = zombie.get("alert_target")
		_fail(test_root, "Zumbi deveria escolher o jogador vivo mais proximo (%s); escolheu %s." % [near_player.get_path(), chosen.get_path() if chosen != null else null])
		zombie.free()
		far_player.free()
		near_player.free()
		return
	var previous_health: int = near_player.health
	zombie.set("alert_target", far_player)
	zombie.set("target_switch_cooldown", 1.0)
	near_player.position = origin + Vector3(0.0, 0.8, 0.8)
	zombie.call("_physics_process", 0.01)
	if near_player.health >= previous_health or zombie.get("alert_target") != far_player:
		_fail(test_root, "Zumbi deveria atacar jogador proximo sem trocar alvo; vida=%d, ataque=%d, alvo=%s." % [near_player.health, zombie.attack_sequence, zombie.alert_target.name if zombie.alert_target != null else "null"])
		zombie.free()
		far_player.free()
		near_player.free()
		return
	var upper_floor_health: int = near_player.health
	near_player.position = origin + Vector3(0.0, 3.8, 0.8)
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


func _test_house_doorways_are_clear(test_root: Node) -> void:
	print("Testando vaos de porta sem parede no lugar...")
	var house_blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(house_blueprint)
	test_root.add_child(house)
	var doors: Array = house.find_children("Door_*", "AnimatableBody3D", true, false)
	if doors.is_empty():
		_fail(test_root, "Casa procedural deveria possuir portas animaveis.")
		house.free()
		return
	for door_node in doors:
		var door := door_node as AnimatableBody3D
		var panel := door.get_node_or_null("DoorPanel") as MeshInstance3D
		if panel == null:
			continue
		var panel_box := panel.mesh as BoxMesh
		var doorway_center: Vector3 = door.position + panel.position
		var doorway_size := Vector3(panel_box.size.x * 0.7, panel_box.size.y * 0.7, panel_box.size.z * 0.7)
		for node in house.find_children("*", "MeshInstance3D", true, false):
			var wall := node as MeshInstance3D
			if wall == panel or String(wall.name).begins_with("Door"):
				continue
			var wall_box := wall.mesh as BoxMesh
			if wall_box == null:
				continue
			var half := (wall_box.size + doorway_size) * 0.5
			var offset := wall.position - doorway_center
			if absf(offset.x) < half.x and absf(offset.y) < half.y and absf(offset.z) < half.z:
				_fail(test_root, "Vao da porta %s esta coberto por '%s'." % [door.name, wall.name])
				house.free()
				return
	house.free()
	print("PASS: Nenhum vao de porta esta coberto por parede.")


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
	door.call("_physics_process", 0.5)
	if absf(float(door.rotation.y)) < 1.0:
		_fail(test_root, "Porta comum deveria girar na dobradica ao abrir.")
		return
	door.interact()
	if door.is_open:
		_fail(test_root, "Segunda interacao deveria fechar a porta comum.")
		return
	door.take_damage(door.max_health, Vector3.FORWARD, "bullet", null)
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
	if doors.size() < 5 or not (doors[0] as AnimatableBody3D).has_node("DoorKnob"):
		_fail(test_root, "Casa procedural deveria possuir 5 portas visiveis; encontradas=%d." % doors.size())
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


func _test_house_windows_are_glazed_openings(test_root: Node) -> void:
	print("Testando janelas de vidro com parede acima e abaixo...")
	var house_blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(house_blueprint)
	test_root.add_child(house)
	var glass_nodes := house.find_children("WindowGlass_*", "MeshInstance3D", true, false)
	if glass_nodes.is_empty():
		_fail(test_root, "Casa procedural deveria possuir janelas de vidro.")
		house.free()
		return
	var glass := glass_nodes[0] as MeshInstance3D
	var glass_box := glass.mesh as BoxMesh
	# O vidro usa o shader de edificio translucido para sumir junto com os andares ocultos.
	var material := glass_box.material as ShaderMaterial if glass_box != null else null
	var glass_color: Color = material.get_shader_parameter("glass_color") if material != null else Color(1, 1, 1, 1)
	if material == null or not String(material.shader.resource_path).ends_with("building_glass.gdshader") or glass_color.a >= 0.5:
		_fail(test_root, "Vidro da janela deveria ser translucido, nao um bloco solido.")
		house.free()
		return
	if glass_box.size.y >= 1.0:
		_fail(test_root, "Janela nao deveria ocupar a altura total da parede; altura=%.2f." % glass_box.size.y)
		house.free()
		return
	var glass_top := glass.position.y + glass_box.size.y * 0.5
	var glass_bottom := glass.position.y - glass_box.size.y * 0.5
	var has_wall_below := false
	var has_wall_above := false
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var wall := node as MeshInstance3D
		if String(wall.name).begins_with("Window") or String(wall.name).begins_with("Floor"):
			continue
		var wall_box := wall.mesh as BoxMesh
		if wall_box == null or wall_box.size.y < 0.5:
			continue
		var aligned := absf(wall.position.z - glass.position.z) < 0.2 or absf(wall.position.x - glass.position.x) < 0.2
		if not aligned:
			continue
		if wall.position.y + wall_box.size.y * 0.5 <= glass_bottom + 0.05:
			has_wall_below = true
		if wall.position.y - wall_box.size.y * 0.5 >= glass_top - 0.05:
			has_wall_above = true
	if not has_wall_below or not has_wall_above:
		_fail(test_root, "Janela deveria ter parede abaixo e acima; abaixo=%s acima=%s." % [has_wall_below, has_wall_above])
		house.free()
		return
	house.free()
	print("PASS: Janelas tem vidro translucido e parede acima e abaixo.")


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
