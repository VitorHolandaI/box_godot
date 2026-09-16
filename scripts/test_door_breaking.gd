extends RefCounted

## Regressoes da porta arrombavel: animacao de destrocos, passagem liberada,
## tremida ao apanhar, faca do jogador e replicacao sem explodir portas antigas.
## Uso: await DoorBreakingTests.new().run(test_root)

const DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")
const DEBRIS_SCRIPT := preload("res://scripts/door_debris_effect.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DOOR_REPLICATOR_SCRIPT := preload("res://scripts/door_state_replicator.gd")
const DOOR_NETWORK_STATE_SCRIPT := preload("res://scripts/door_network_state.gd")


func run(test_root: Node) -> void:
	await _test_broken_door_frees_doorway_and_bursts(test_root)
	_test_hit_shakes_panel_before_breaking(test_root)
	_test_open_door_can_still_be_broken(test_root)
	await _test_player_knife_breaks_door(test_root)
	_test_network_break_animates_only_after_first_snapshot(test_root)
	_test_debris_rejects_invalid_size(test_root)
	_test_replicator_sends_only_changed_doors(test_root)
	_test_replicator_watches_late_doors(test_root)
	_test_replicator_full_state_once_per_peer(test_root)
	_test_client_applies_door_change_with_animation(test_root)


func _test_broken_door_frees_doorway_and_bursts(test_root: Node) -> void:
	print("Testando porta arrombada liberando o vao com destrocos...")
	var door := _add_door(test_root, Vector3(-700.0, 0.0, -700.0))
	door.take_damage(int(door.get("max_health")), Vector3.FORWARD, "melee", null)
	# set_deferred so roda no fim do frame ocioso; so o physics_frame nao basta
	# quando este grupo roda sozinho.
	await test_root.get_tree().process_frame
	await test_root.get_tree().physics_frame
	var collision := door.get_node("DoorCollision") as CollisionShape3D
	var panel := door.get_node("DoorPanel") as Node3D
	var debris := door.get_node_or_null("DoorDebris") as Node3D
	if not collision.disabled or panel.visible or debris == null:
		_fail(test_root, "Porta quebrada deveria desligar colisao, esconder a folha e soltar destrocos; colisao=%s folha=%s destrocos=%s." % [collision.disabled, panel.visible, debris])
		door.queue_free()
		return
	var first_piece := debris.get_child(0) as Node3D
	var start_position := first_piece.position
	debris.call("_physics_process", 0.2)
	if first_piece.position.distance_to(start_position) < 0.1:
		_fail(test_root, "Destrocos deveriam voar ao quebrar; moveram %.3f m." % first_piece.position.distance_to(start_position))
		door.queue_free()
		return
	debris.call("_physics_process", DEBRIS_SCRIPT.LIFETIME)
	if not debris.is_queued_for_deletion():
		_fail(test_root, "Destrocos deveriam sumir apos %.1f s." % DEBRIS_SCRIPT.LIFETIME)
	door.queue_free()
	print("PASS: Porta quebrada vira destrocos animados e libera a passagem.")


func _test_hit_shakes_panel_before_breaking(test_root: Node) -> void:
	print("Testando porta tremendo ao apanhar...")
	var door := _add_door(test_root, Vector3(-704.0, 0.0, -700.0))
	var panel := door.get_node("DoorPanel") as Node3D
	var rest_position := panel.position
	door.take_damage(10, Vector3.FORWARD, "melee", null)
	door.call("_physics_process", 1.0 / 60.0)
	var shaken := panel.position.distance_to(rest_position) > 0.001
	door.call("_physics_process", 1.0)
	var settled := panel.position.distance_to(rest_position) < 0.001
	var still_standing := not bool(door.get("is_destroyed"))
	door.queue_free()
	if not shaken or not settled or not still_standing:
		_fail(test_root, "Golpe sem quebrar deveria tremer e depois assentar a folha; tremeu=%s assentou=%s inteira=%s." % [shaken, settled, still_standing])
		return
	print("PASS: Golpes fazem a porta tremer antes de ceder.")


func _test_open_door_can_still_be_broken(test_root: Node) -> void:
	print("Testando arrombamento de porta aberta...")
	var door = DOOR_SCRIPT.new()
	door.configure(Vector3(1.4, 2.6, 0.12), null)
	door.interact()
	door.take_damage(door.max_health, Vector3.FORWARD, "knife", null)
	var destroyed: bool = door.is_destroyed
	door.free()
	if not destroyed:
		_fail(test_root, "Porta aberta tambem deveria poder ser destruida.")
		return
	print("PASS: Porta aberta pode ser destruida.")


func _test_player_knife_breaks_door(test_root: Node) -> void:
	print("Testando jogador arrombando porta com a faca...")
	var door := _add_door(test_root, Vector3(-708.7, 0.0, -701.0))
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = Vector3(-708.0, 1.2, -699.8)
	test_root.add_child(player)
	await test_root.get_tree().physics_frame
	var hits := 0
	while not bool(door.get("is_destroyed")) and hits < 10:
		player.call("_attack_with_knife")
		hits += 1
	var destroyed := bool(door.get("is_destroyed"))
	player.queue_free()
	door.queue_free()
	var expected_hits := ceili(float(DOOR_SCRIPT.new().max_health) / float(player.get("knife_damage")))
	if not destroyed or hits != expected_hits:
		_fail(test_root, "Faca deveria quebrar a porta em %d golpes; quebrou=%s golpes=%d." % [expected_hits, destroyed, hits])
		return
	print("PASS: Jogador quebra a porta com %d golpes de faca." % hits)


func _test_network_break_animates_only_after_first_snapshot(test_root: Node) -> void:
	print("Testando replicacao da quebra sem explodir portas antigas...")
	var late_joiner_door := _add_door(test_root, Vector3(-712.0, 0.0, -700.0))
	late_joiner_door.apply_network_state(true, true)
	var late_debris := late_joiner_door.get_node_or_null("DoorDebris")
	var live_door := _add_door(test_root, Vector3(-716.0, 0.0, -700.0))
	live_door.apply_network_state(false, false)
	live_door.apply_network_state(true, true)
	var live_debris := live_door.get_node_or_null("DoorDebris")
	var live_destroyed := bool(live_door.get("is_destroyed"))
	late_joiner_door.queue_free()
	live_door.queue_free()
	if late_debris != null or live_debris == null or not live_destroyed:
		_fail(test_root, "Primeiro snapshot nao anima; quebra posterior anima. inicial=%s posterior=%s." % [late_debris, live_debris])
		return
	print("PASS: Clientes veem a quebra ao vivo e nao reexplodem portas antigas.")


func _test_debris_rejects_invalid_size(test_root: Node) -> void:
	print("Testando validacao de tamanho dos destrocos...")
	var debris = DEBRIS_SCRIPT.new()
	var default_size: Vector3 = debris.panel_size
	debris.configure(Vector3(0.0, 2.0, 0.1), Vector3.FORWARD, null, 1)
	var kept_default: bool = debris.panel_size == default_size
	debris.free()
	if not kept_default:
		_fail(test_root, "Destrocos com tamanho invalido deveriam manter o tamanho padrao.")
		return
	print("PASS: Destrocos recusam tamanho invalido.")


func _test_replicator_sends_only_changed_doors(test_root: Node) -> void:
	print("Testando replicacao de portas so quando mudam...")
	var door := _add_door(test_root, Vector3(-720.0, 0.0, -700.0))
	var replicator = DOOR_REPLICATOR_SCRIPT.new()
	replicator.watch(test_root.get_tree())
	var idle: Dictionary = replicator.take_changes()
	door.interact()
	var opened: Dictionary = replicator.take_changes()
	var drained: Dictionary = replicator.take_changes()
	door.take_damage(int(door.get("max_health")), Vector3.FORWARD, "melee", null)
	var broken: Dictionary = replicator.take_changes()
	var path := str(test_root.get_tree().current_scene.get_path_to(door))
	door.queue_free()
	var opened_ok: bool = opened.get(path, []) == [true, false]
	var broken_ok: bool = broken.get(path, []) == [true, true]
	if not idle.is_empty() or not opened_ok or not drained.is_empty() or not broken_ok:
		_fail(test_root, "Replicador deveria enviar so mudancas; parado=%s aberta=%s repetido=%s quebrada=%s." % [idle, opened, drained, broken])
		return
	print("PASS: Portas vao para a rede apenas quando abrem, fecham ou quebram.")


func _test_replicator_watches_late_doors(test_root: Node) -> void:
	print("Testando re-watch de portas montadas depois do watch...")
	var replicator = DOOR_REPLICATOR_SCRIPT.new()
	# A cidade monta em etapas: watch() pode rodar antes de qualquer porta.
	replicator.watch(test_root.get_tree())
	var door := _add_door(test_root, Vector3(-726.0, 0.0, -700.0))
	door.name = "DoorLateRewatch"
	door.interact()
	if not replicator.take_changes().is_empty():
		_fail(test_root, "Porta montada depois do watch nao deveria emitir sem novo watch; o bug 'portas desativadas' seria silenciado.")
		door.queue_free()
		return
	# Re-watch apos a montagem (o que main.gd faz em city_ready).
	replicator.watch(test_root.get_tree())
	# A primeira interacao (sem listener) deixou is_open=true; agora captura o fechamento.
	door.interact()
	var changes: Dictionary = replicator.take_changes()
	var path := str(test_root.get_tree().current_scene.get_path_to(door))
	door.queue_free()
	if changes.get(path, []) != [false, false]:
		_fail(test_root, "Re-watch deveria assinar a porta tardia e capturar a mudanca; veio %s." % [changes])
		return
	print("PASS: Re-watch apos a montagem assina portas tardias e replica as mudancas.")


func _test_replicator_full_state_once_per_peer(test_root: Node) -> void:
	print("Testando estado completo de portas uma vez por jogador...")
	var replicator = DOOR_REPLICATOR_SCRIPT.new()
	var first: Array[int] = replicator.take_unsynced_peers([7, 9])
	var second: Array[int] = replicator.take_unsynced_peers([7, 9, 11])
	var after_leave: Array[int] = replicator.take_unsynced_peers([11])
	var rejoin: Array[int] = replicator.take_unsynced_peers([7, 11])
	if first != [7, 9] or second != [11] or not after_leave.is_empty() or rejoin != [7]:
		_fail(test_root, "Estado completo esperado [7,9] / [11] / [] / [7]; veio %s / %s / %s / %s." % [first, second, after_leave, rejoin])
		return
	print("PASS: Jogador que entra recebe o estado completo das portas uma unica vez.")


func _test_client_applies_door_change_with_animation(test_root: Node) -> void:
	print("Testando cliente aplicando mudanca de porta recebida...")
	var door := _add_door(test_root, Vector3(-724.0, 0.0, -700.0))
	DOOR_NETWORK_STATE_SCRIPT.apply(test_root.get_tree(), {})
	var path := str(test_root.get_tree().current_scene.get_path_to(door))
	DOOR_NETWORK_STATE_SCRIPT.apply_changes(test_root.get_tree(), {path: [true, true], "Nao/Existe": [true, true]})
	var destroyed := bool(door.get("is_destroyed"))
	var debris := door.get_node_or_null("DoorDebris")
	door.queue_free()
	if not destroyed or debris == null:
		_fail(test_root, "Mudanca recebida depois do estado completo deveria quebrar a porta com destrocos; quebrada=%s destrocos=%s." % [destroyed, debris])
		return
	print("PASS: Cliente quebra a porta ao vivo e ignora caminhos invalidos.")


func _add_door(test_root: Node, position: Vector3) -> AnimatableBody3D:
	var door := DOOR_SCRIPT.new() as AnimatableBody3D
	door.configure(Vector3(1.4, 2.75, 0.12), null)
	door.position = position
	test_root.add_child(door)
	return door


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
