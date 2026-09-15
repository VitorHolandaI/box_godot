extends RefCounted

## Regressoes de dessincronia online: variante do zumbi igual no cliente,
## snapshot de jogador abaixo do MTU, regra de game over e progresso da onda
## (restantes) replicado para o HUD do cliente.
## Uso: NetworkJoinSyncTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CODEC_SCRIPT := preload("res://scripts/zombie_snapshot_codec.gd")
const PROXY_FACTORY_SCRIPT := preload("res://scripts/network_zombie_proxy_factory.gd")
const SURVIVAL_WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
# Anel de sobrevivencia amostrado em 72 angulos x 3 raios; abaixo disso a onda
# alta nao acha espaco e o spawn para ("zumbi nao da spawn").
const MIN_OPEN_SURVIVAL_SPAWN_POINTS := 40
# MTU do ENet (1392) menos folga para cabecalho do RPC, caminho do no e door_open.
const PLAYER_PACKET_BUDGET_BYTES := 1200


func run(test_root: Node) -> void:
	_test_client_proxy_matches_server_variant(test_root)
	_test_player_snapshot_packet_fits_mtu(test_root)
	_test_game_over_rule(test_root)
	_test_client_wave_sync_uses_alive_count(test_root)
	_test_game_over_restarts_with_players(test_root)
	_test_bunched_input_packets_keep_click(test_root)
	await _test_survival_ring_has_open_spawn_points(test_root)


func _test_client_proxy_matches_server_variant(test_root: Node) -> void:
	print("Testando variante do zumbi igual no servidor e no cliente...")
	var server_zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	server_zombie.name = "ZombieSpawn55"
	# Tipo diferente do que o nome sozinho daria (hash % 11).
	var name_only_type := absi(String(server_zombie.name).hash()) % 11
	server_zombie.set("forced_variant", (name_only_type + 4) % 11)
	test_root.add_child(server_zombie)
	var state: Dictionary = server_zombie.get_network_state()
	state["network_id"] = 55
	var decoded: Dictionary = CODEC_SCRIPT.decode(CODEC_SCRIPT.encode([state]))[0]
	var server_type := int(server_zombie.get("zombie_type"))
	var server_look := int(server_zombie.get("appearance_hash"))
	# Libera antes: irmao com o mesmo nome seria renomeado e mudaria o hash.
	server_zombie.free()
	var proxy: CharacterBody3D = PROXY_FACTORY_SCRIPT.instantiate_proxy(ZOMBIE_SCENE, String(decoded["name"]), decoded)
	test_root.add_child(proxy)
	var proxy_type := int(proxy.get("zombie_type"))
	var same_type := proxy_type == server_type
	var same_look := int(proxy.get("appearance_hash")) == server_look
	proxy.free()
	if not same_type or not same_look:
		_fail(test_root, "Proxy do cliente deveria ter o tipo e a aparencia do servidor; servidor=%d cliente=%d aparencia_igual=%s." % [server_type, proxy_type, same_look])
		return
	print("PASS: Cliente mostra a mesma variante sorteada pela onda no servidor.")


func _test_player_snapshot_packet_fits_mtu(test_root: Node) -> void:
	print("Testando pacote de snapshot de jogador abaixo do MTU...")
	var players: Array[CharacterBody3D] = []
	var states: Array = []
	for index in MAIN_SCRIPT.MAX_PLAYERS_PER_SNAPSHOT_PACKET:
		var player := PLAYER_SCENE.instantiate() as CharacterBody3D
		player.set("reads_local_input", false)
		test_root.add_child(player)
		player.call("take_crate_weapon", WeaponStats.Kind.UZI)
		var state: Dictionary = player.get_network_state()
		state["key"] = "%d:%d" % [2147483647, index]
		states.append(state)
		players.append(player)
	var packet_bytes := var_to_bytes(states).size()
	for player in players:
		player.free()
	if packet_bytes > PLAYER_PACKET_BUDGET_BYTES:
		_fail(test_root, "Pacote com %d jogador(es) tem %d bytes; esperado <= %d para nao fragmentar (MTU 1392)." % [MAIN_SCRIPT.MAX_PLAYERS_PER_SNAPSHOT_PACKET, packet_bytes, PLAYER_PACKET_BUDGET_BYTES])
		return
	print("PASS: Pacote de jogador com %d bytes cabe no MTU." % packet_bytes)


func _test_game_over_rule(test_root: Node) -> void:
	print("Testando regra de game over (vazio, misto, todos caidos)...")
	var standing := PLAYER_SCENE.instantiate() as CharacterBody3D
	var downed := PLAYER_SCENE.instantiate() as CharacterBody3D
	downed.set("is_downed", true)
	var empty_server: bool = SURVIVAL_WAVE_CONTROLLER_SCRIPT.everyone_is_down([])
	var mixed: bool = SURVIVAL_WAVE_CONTROLLER_SCRIPT.everyone_is_down([standing, downed])
	var all_down: bool = SURVIVAL_WAVE_CONTROLLER_SCRIPT.everyone_is_down([downed])
	standing.free()
	downed.free()
	if not empty_server or mixed or not all_down:
		_fail(test_root, "Game over: servidor vazio sim, um de pe nao, todos caidos sim; veio %s/%s/%s." % [empty_server, mixed, all_down])
		return
	print("PASS: Game over com servidor vazio ou todos caidos; um de pe segura a horda.")


func _test_client_wave_sync_uses_alive_count(test_root: Node) -> void:
	print("Testando restantes da onda sincronizados no cliente...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new()
	# Abates acumulados de ondas anteriores nao podem descontar da onda atual.
	controller.set_sync_state(3, 250, 17)
	var hud_text: String = controller.get_hud_text()
	if not hud_text.contains("Restantes: 17/"):
		_fail(test_root, "HUD do cliente deveria mostrar os 17 restantes enviados pelo servidor; texto=%s." % hud_text)
		return
	print("PASS: Cliente mostra os restantes reais da onda.")


func _test_game_over_restarts_with_players(test_root: Node) -> void:
	print("Testando reinicio automatico do GAME OVER...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new()
	controller.trigger_game_over()
	var empty_waits: bool = not controller.tick_game_over(60.0, false)
	var early: bool = controller.tick_game_over(controller.GAME_OVER_RESTART_SECONDS * 0.5, true)
	var due: bool = controller.tick_game_over(controller.GAME_OVER_RESTART_SECONDS * 0.5 + 0.1, true)
	controller.set_sync_state(0, 0, 0, false)
	var client_cleared: bool = not controller.game_over and not controller.get_hud_text().contains("GAME OVER")
	if not empty_waits or early or not due or not client_cleared:
		_fail(test_root, "GAME OVER: vazio espera, com jogador reinicia em %.0f s e o cliente sai da tela; vazio_espera=%s cedo=%s na_hora=%s cliente_limpo=%s." % [controller.GAME_OVER_RESTART_SECONDS, empty_waits, early, due, client_cleared])
		return
	print("PASS: GAME OVER reinicia sozinho com jogador presente e limpa o HUD do cliente.")


func _test_bunched_input_packets_keep_click(test_root: Node) -> void:
	print("Testando clique preservado com pacotes de input no mesmo frame...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	# Dois pacotes com o botao apertado chegam antes do tick de fisica.
	player.apply_network_input({"attack": true})
	player.apply_network_input({"attack": true})
	var kept := bool(player.get("attack_pressed"))
	player.call("_clear_transient_input")
	# Soltar e apertar de novo gera um clique novo (estado anterior atualizado).
	player.apply_network_input({"attack": true})
	player.apply_network_input({"attack": false})
	player.apply_network_input({"attack": true})
	var second_click := bool(player.get("attack_pressed"))
	player.free()
	if not kept or not second_click:
		_fail(test_root, "Clique nao pode sumir com pacotes agrupados; mantido=%s segundo_clique=%s." % [kept, second_click])
		return
	print("PASS: Pacotes de input agrupados nao apagam o clique.")


func _test_survival_ring_has_open_spawn_points(test_root: Node) -> void:
	print("Testando pontos livres de spawn no anel da sobrevivencia na cidade real...")
	var previous_city := NetworkSession.procedural_city_enabled
	var previous_survival := NetworkSession.survival_mode
	NetworkSession.procedural_city_enabled = true
	NetworkSession.survival_mode = true
	var main_world := MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	main_world.set_physics_process(false)
	test_root.add_child(main_world)
	await test_root.get_tree().physics_frame
	var locator = SPAWN_LOCATOR_SCRIPT.new()
	var open_points := 0
	var sampled := 0
	for radius in [SPAWN_LOCATOR_SCRIPT.SURVIVAL_INNER_RADIUS, (SPAWN_LOCATOR_SCRIPT.SURVIVAL_INNER_RADIUS + SPAWN_LOCATOR_SCRIPT.SURVIVAL_OUTER_RADIUS) * 0.5, SPAWN_LOCATOR_SCRIPT.SURVIVAL_OUTER_RADIUS]:
		for step in 72:
			var angle := TAU * float(step) / 72.0
			sampled += 1
			if locator.is_open_ground(Vector3(cos(angle) * radius, 1.0, sin(angle) * radius), test_root.get_tree()):
				open_points += 1
	main_world.free()
	NetworkSession.procedural_city_enabled = previous_city
	NetworkSession.survival_mode = previous_survival
	print(JSON.stringify({"event": "survival_spawn_ring", "open_points": open_points, "sampled": sampled}))
	if open_points < MIN_OPEN_SURVIVAL_SPAWN_POINTS:
		_fail(test_root, "Anel de spawn com %d/%d pontos livres; esperado >= %d." % [open_points, sampled, MIN_OPEN_SURVIVAL_SPAWN_POINTS])
		return
	print("PASS: Anel de spawn tem %d/%d pontos livres na cidade." % [open_points, sampled])


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
