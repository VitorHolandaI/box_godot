extends RefCounted

## Regressoes de zumbis presos: medidor de progresso, desvio contornando parede
## e realocacao de quem ficou encalhado longe dos jogadores.
## Uso: await ZombieUnstuckTests.new().run(test_root)

const PROGRESS_WATCH_SCRIPT := preload("res://scripts/zombie_progress_watch.gd")
const WALL_DETOUR_SCRIPT := preload("res://scripts/zombie_wall_detour.gd")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SAFEHOUSE_BUILDER_SCRIPT := preload("res://scripts/safehouse_builder.gd")
const SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
const SPLIT_SCREEN_SCRIPT := preload("res://scripts/split_screen_manager.gd")
const STEP := 0.25
const PHYSICS_STEP := 1.0 / 60.0


## Testes sincronos liberam com free(): a suite segue sem ceder frame, e nos em
## queue_free ainda contavam como jogadores/zumbis nos testes seguintes.
func run(test_root: Node) -> void:
	_test_watch_counts_blocked_time(test_root)
	_test_watch_counts_sliding_without_progress(test_root)
	_test_watch_resets_on_progress(test_root)
	_test_detour_follows_wall_toward_target(test_root)
	_test_detour_flips_side_when_blocked_again(test_root)
	await _test_zombie_walks_around_safehouse_to_door(test_root)
	await _test_zombie_detours_around_wall_outdoors(test_root)
	_test_far_stranded_zombie_asks_relocation(test_root)
	_test_client_snaps_relocated_zombie(test_root)
	_test_spawn_rejects_walls_and_buildings(test_root)
	_test_minimap_reveals_only_last_stragglers(test_root)


func _test_watch_counts_blocked_time(test_root: Node) -> void:
	print("Testando medidor de zumbi parado contra parede...")
	var watch = PROGRESS_WATCH_SCRIPT.new()
	var target := Vector3(30.0, 0.0, 0.0)
	for step in 16:
		watch.update(STEP, Vector3(0.05 * float(step % 2), 0.0, 0.0), target)
	if watch.blocked_seconds < 2.9 or watch.no_progress_seconds < 2.9:
		_fail(test_root, "Zumbi parado 4 s deveria somar ~3 s bloqueado e sem progresso; bloqueado=%.2f sem_progresso=%.2f." % [watch.blocked_seconds, watch.no_progress_seconds])
		return
	print("PASS: Medidor soma tempo parado contra obstaculo.")


func _test_watch_counts_sliding_without_progress(test_root: Node) -> void:
	print("Testando medidor de zumbi deslizando sem chegar perto...")
	var watch = PROGRESS_WATCH_SCRIPT.new()
	var target := Vector3(0.0, 0.0, 20.0)
	# Anda 2 m/s de um lado para o outro ao longo de um muro, sem se aproximar.
	for step in 40:
		var along := fmod(float(step) * STEP * 2.0, 8.0)
		watch.update(STEP, Vector3(along - 4.0, 0.0, 0.0), target)
	if watch.blocked_seconds > 0.0 or watch.no_progress_seconds < 8.0:
		_fail(test_root, "Deslizando 10 s nao e bloqueio mas e falta de progresso; bloqueado=%.2f sem_progresso=%.2f." % [watch.blocked_seconds, watch.no_progress_seconds])
		return
	print("PASS: Medidor separa deslizar no muro de ficar parado.")


func _test_watch_resets_on_progress(test_root: Node) -> void:
	print("Testando medidor zerando quando o zumbi se aproxima...")
	var watch = PROGRESS_WATCH_SCRIPT.new()
	var target := Vector3(0.0, 0.0, 40.0)
	for step in 40:
		watch.update(STEP, Vector3(0.0, 0.0, float(step) * STEP * 2.0), target)
	var approaching_ok: bool = watch.blocked_seconds == 0.0 and watch.no_progress_seconds <= 1.0
	watch.reset()
	var reset_ok: bool = watch.blocked_seconds == 0.0 and watch.no_progress_seconds == 0.0
	if not approaching_ok or not reset_ok:
		_fail(test_root, "Zumbi se aproximando deveria manter o medidor zerado; bloqueado=%.2f sem_progresso=%.2f reset=%s." % [watch.blocked_seconds, watch.no_progress_seconds, reset_ok])
		return
	print("PASS: Medidor zera ao se aproximar e no reset.")


func _test_detour_follows_wall_toward_target(test_root: Node) -> void:
	print("Testando desvio pela tangente da parede ate a linha ficar livre...")
	var detour = WALL_DETOUR_SCRIPT.new()
	# Parede virada para -z (normal apontando para o zumbi); alvo atras e um pouco a direita.
	var wall_normal := Vector3(0.0, 0.0, -1.0)
	var desired := Vector3(0.3, 0.0, 1.0).normalized()
	var free_path: Vector3 = detour.steer(0.1, Vector3.ZERO, desired, 0.2, wall_normal, false)
	var detour_direction: Vector3 = detour.steer(0.1, Vector3.ZERO, desired, 1.5, wall_normal, false)
	var held: Vector3 = detour.steer(1.0, Vector3.ZERO, desired, 0.0, Vector3.ZERO, false)
	var released: Vector3 = detour.steer(0.1, Vector3.ZERO, desired, 0.0, Vector3.ZERO, true)
	var along_wall := absf(detour_direction.x) > 0.9 and detour_direction.x > 0.0
	if free_path != desired or not along_wall or held != detour_direction or released != desired or detour.is_active():
		_fail(test_root, "Desvio deveria seguir a parede para +x ate a linha limpar; livre=%s desvio=%s mantido=%s liberado=%s." % [free_path, detour_direction, held, released])
		return
	print("PASS: Zumbi bloqueado segue a parede e volta ao alvo com a linha livre.")


func _test_detour_flips_side_when_blocked_again(test_root: Node) -> void:
	print("Testando troca de lado do desvio em quina...")
	var detour = WALL_DETOUR_SCRIPT.new()
	var wall_normal := Vector3(0.0, 0.0, -1.0)
	var desired := Vector3(0.3, 0.0, 1.0).normalized()
	var first: Vector3 = detour.steer(0.1, Vector3.ZERO, desired, 1.5, wall_normal, false)
	detour.steer(WALL_DETOUR_SCRIPT.MAX_DETOUR_SECONDS + 0.1, Vector3.ZERO, desired, 0.0, Vector3.ZERO, false)
	var second: Vector3 = detour.steer(0.1, Vector3.ZERO, desired, 1.5, wall_normal, false)
	# Mesmo bloqueio, mas depois de andar 4 m: o lado estava certo, mantem.
	detour.steer(WALL_DETOUR_SCRIPT.MAX_DETOUR_SECONDS + 0.1, Vector3.ZERO, desired, 0.0, Vector3.ZERO, false)
	var after_progress: Vector3 = detour.steer(0.1, Vector3(4.0, 0.0, 0.0), desired, 1.5, wall_normal, false)
	if signf(first.x) == signf(second.x) or signf(after_progress.x) != signf(first.x):
		_fail(test_root, "Quina sem sair do lugar troca de lado; apos progresso volta ao lado do alvo; primeiro=%s segundo=%s apos_progresso=%s." % [first, second, after_progress])
		return
	print("PASS: Desvio troca de lado quando o primeiro lado nao resolve.")


func _test_zombie_detours_around_wall_outdoors(test_root: Node) -> void:
	print("Testando zumbi contornando muro na rua...")
	var origin := Vector3(-900.0, 0.0, -900.0)
	var ground := _add_ground(test_root, origin)
	# Muro de 10 m entre o zumbi e o jogador, fora de qualquer navmesh.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10.0, 3.0, 0.4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = origin + Vector3(0.0, 1.6, 0.0)
	test_root.add_child(wall)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = origin + Vector3(0.6, 1.3, 6.0)
	test_root.add_child(player)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	# Walker fixo: sorteio pelo nome podia dar cuspidor/investida (comportam diferente).
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	zombie.position = origin + Vector3(0.0, 1.3, -3.0)
	test_root.add_child(zombie)
	await test_root.get_tree().physics_frame
	var passed := false
	for step in 1800:
		zombie.call("_physics_process", PHYSICS_STEP)
		if zombie.global_position.z - origin.z > 1.0:
			passed = true
			break
		if step % 30 == 29:
			await test_root.get_tree().process_frame
	var final_local := zombie.global_position - origin
	zombie.queue_free()
	player.queue_free()
	wall.queue_free()
	ground.queue_free()
	if not passed:
		_fail(test_root, "Zumbi deveria contornar o muro de 10 m ate o jogador; parou em %s (local)." % final_local)
		return
	print("PASS: Zumbi na rua contorna o muro em vez de empurra-lo.")


func _test_zombie_walks_around_safehouse_to_door(test_root: Node) -> void:
	print("Testando zumbi contornando a casa segura ate a porta...")
	var origin := Vector3(900.0, 0.0, -900.0)
	var ground := _add_ground(test_root, origin)
	var safehouse: StaticBody3D = SAFEHOUSE_BUILDER_SCRIPT.build_safehouse()
	safehouse.position = origin + Vector3(0.0, 0.12, 0.0)
	test_root.add_child(safehouse)
	var navigation = safehouse.get_node("BuildingNavigation")
	for _frame in 120:
		if navigation.is_ready():
			break
		await test_root.get_tree().physics_frame
	safehouse.get_node("SafehouseDoor").call("interact")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = origin + Vector3(0.0, 1.3, 0.0)
	test_root.add_child(player)
	# Atras da parede do fundo (sul): a linha reta ate o jogador bate na parede.
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	zombie.position = origin + Vector3(1.0, 1.3, 9.5)
	test_root.add_child(zombie)
	await test_root.get_tree().physics_frame
	var inside := false
	for step in 2400:
		zombie.call("_physics_process", PHYSICS_STEP)
		var local := zombie.global_position - safehouse.global_position
		if absf(local.x) < 5.5 and absf(local.z) < 5.5:
			inside = true
			break
		if step % 30 == 29:
			await test_root.get_tree().process_frame
	var final_local := zombie.global_position - safehouse.global_position
	zombie.queue_free()
	player.queue_free()
	safehouse.queue_free()
	ground.queue_free()
	if not inside:
		_fail(test_root, "Zumbi atras da casa segura deveria contornar ate a porta aberta e entrar; parou em %s (local)." % final_local)
		return
	print("PASS: Zumbi contorna a casa segura e entra pela porta.")


func _test_far_stranded_zombie_asks_relocation(test_root: Node) -> void:
	print("Testando pedido de realocacao de zumbi encalhado longe...")
	var player := _add_bait_player(test_root, Vector3(-950.0, 1.3, 950.0))
	var far_zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	far_zombie.position = Vector3(-950.0, 1.3, 1000.0)
	test_root.add_child(far_zombie)
	var near_zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	near_zombie.position = Vector3(-950.0, 1.3, 958.0)
	test_root.add_child(near_zombie)
	var requests: Array[Node] = []
	for zombie in [far_zombie, near_zombie]:
		zombie.stranded.connect(func(stranded_zombie: Node) -> void: requests.append(stranded_zombie))
		zombie.call("_watch_chase_progress", player, 0.0)
		zombie.progress_watch.no_progress_seconds = zombie.STRANDED_SECONDS + 1.0
		zombie.call("_watch_chase_progress", player, 0.0)
	far_zombie.relocate(Vector3(-940.0, 1.0, 940.0))
	var relocated_ok: bool = far_zombie.global_position.is_equal_approx(Vector3(-940.0, 1.0, 940.0)) and far_zombie.progress_watch.no_progress_seconds == 0.0
	player.free()
	far_zombie.free()
	near_zombie.free()
	if requests != [far_zombie] or not relocated_ok:
		_fail(test_root, "So o zumbi encalhado a 50 m deveria pedir realocacao (o de 8 m cerca o jogador); pedidos=%s realocado=%s." % [requests, relocated_ok])
		return
	print("PASS: Zumbi encalhado longe pede realocacao; o que cerca o jogador fica.")


func _test_client_snaps_relocated_zombie(test_root: Node) -> void:
	print("Testando cliente teleportando zumbi realocado...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.simulation_enabled = false
	zombie.position = Vector3(-960.0, 1.0, -960.0)
	test_root.add_child(zombie)
	zombie.apply_network_state({"position": Vector3(-959.5, 1.0, -960.0)})
	var small_step_kept := zombie.global_position.is_equal_approx(Vector3(-960.0, 1.0, -960.0))
	zombie.apply_network_state({"position": Vector3(-900.0, 1.0, -960.0)})
	var snapped := zombie.global_position.is_equal_approx(Vector3(-900.0, 1.0, -960.0))
	zombie.free()
	if not small_step_kept or not snapped:
		_fail(test_root, "Passo curto interpola e salto de 60 m teleporta; interpolou=%s teleportou=%s." % [small_step_kept, snapped])
		return
	print("PASS: Cliente teleporta so saltos de realocacao.")


func _test_spawn_rejects_walls_and_buildings(test_root: Node) -> void:
	print("Testando spawn so em chao aberto...")
	var origin := Vector3(960.0, 0.0, 960.0)
	var block := StaticBody3D.new()
	var block_shape := CollisionShape3D.new()
	var block_box := BoxShape3D.new()
	block_box.size = Vector3(2.0, 3.0, 2.0)
	block_shape.shape = block_box
	block.add_child(block_shape)
	block.position = origin + Vector3(0.0, 1.5, 0.0)
	test_root.add_child(block)
	var navigation := preload("res://scripts/procedural/navigation/building_navigation.gd").new(Vector3(10.0, 3.4, 10.0))
	var house := StaticBody3D.new()
	house.position = origin + Vector3(20.0, 0.0, 0.0)
	house.add_child(navigation)
	test_root.add_child(house)
	var locator = SPAWN_LOCATOR_SCRIPT.new()
	var tree := test_root.get_tree()
	var in_wall: bool = locator.is_open_ground(origin + Vector3(0.3, 1.0, 0.0), tree)
	var in_house: bool = locator.is_open_ground(origin + Vector3(25.0, 1.0, 5.0), tree)
	var street: bool = locator.is_open_ground(origin + Vector3(0.0, 1.0, 10.0), tree)
	block.free()
	house.free()
	if in_wall or in_house or not street:
		_fail(test_root, "Spawn deveria recusar parede e predio e aceitar a rua; parede=%s predio=%s rua=%s." % [in_wall, in_house, street])
		return
	print("PASS: Spawn recusa paredes e interiores de predios.")


func _test_minimap_reveals_only_last_stragglers(test_root: Node) -> void:
	print("Testando minimapa revelando os ultimos zumbis...")
	var few: Array = []
	for index in 3:
		few.append(Node3D.new())
	var many: Array = few.duplicate()
	for index in 5:
		many.append(Node3D.new())
	var revealed_few: Array = SPLIT_SCREEN_SCRIPT.stragglers_to_reveal(few, 5)
	var revealed_many: Array = SPLIT_SCREEN_SCRIPT.stragglers_to_reveal(many, 5)
	for node in many:
		node.free()
	if revealed_few.size() != 3 or not revealed_many.is_empty():
		_fail(test_root, "Minimapa revela todos com 3 vivos e nenhum com 8; veio %d e %d." % [revealed_few.size(), revealed_many.size()])
		return
	print("PASS: Minimapa mostra os ultimos 5 zumbis da onda.")


func _add_bait_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	return player


func _add_ground(test_root: Node, origin: Vector3) -> StaticBody3D:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	shape.shape = box
	ground.add_child(shape)
	# Mesmo chao da main.tscn: caixa de 0.2 m centrada em y=0 (topo em 0.1).
	ground.position = origin
	test_root.add_child(ground)
	return ground


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
