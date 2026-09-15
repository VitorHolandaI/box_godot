extends RefCounted

## Regressoes do botao "Destravar personagem" do menu: busca de espaco livre
## acima (ou ao redor) do boneco, recarga contra abuso e teleporte no cliente.
## Uso: await PlayerUnstuckTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const UNSTUCK_LOCATOR_SCRIPT := preload("res://scripts/player_unstuck_locator.gd")


func run(test_root: Node) -> void:
	await _test_unstuck_lifts_player_out_of_block(test_root)
	await _test_unstuck_goes_sideways_under_low_ceiling(test_root)
	await _test_unstuck_has_cooldown(test_root)
	_test_client_snaps_on_teleport_sequence(test_root)


func _test_unstuck_lifts_player_out_of_block(test_root: Node) -> void:
	print("Testando destravar jogador preso dentro de um bloco...")
	var origin := Vector3(700.0, 0.0, 700.0)
	# Bloco de 1.2 m de altura engolindo as pernas do boneco.
	var block := _add_box(test_root, Vector3(3.0, 1.2, 3.0), origin + Vector3(0.0, 0.6, 0.0))
	var player := _add_player(test_root, origin + Vector3(0.0, 0.9, 0.0))
	await test_root.get_tree().physics_frame
	var moved: bool = player.unstuck()
	var final_position := player.global_position
	var free_now: bool = UNSTUCK_LOCATOR_SCRIPT.is_position_free(player, final_position)
	player.free()
	block.free()
	if not moved or final_position.y < origin.y + 2.0 or not free_now:
		_fail(test_root, "Destravar deveria subir o boneco para fora do bloco; moveu=%s posicao=%s livre=%s." % [moved, final_position, free_now])
		return
	print("PASS: Destravar joga o boneco para cima, fora do bloco.")


func _test_unstuck_goes_sideways_under_low_ceiling(test_root: Node) -> void:
	print("Testando destravar sob teto baixo indo para o lado...")
	var origin := Vector3(720.0, 0.0, 700.0)
	var ground := _add_box(test_root, Vector3(20.0, 0.2, 20.0), origin)
	# Laje grossa colada na cabeca: nenhum ponto acima cabe o boneco.
	var slab := _add_box(test_root, Vector3(3.0, 6.0, 3.0), origin + Vector3(0.0, 5.0, 0.0))
	var pillar := _add_box(test_root, Vector3(1.0, 2.0, 1.0), origin + Vector3(0.0, 1.0, 0.0))
	var player := _add_player(test_root, origin + Vector3(0.3, 1.0, 0.0))
	await test_root.get_tree().physics_frame
	var moved: bool = player.unstuck()
	var offset := player.global_position - origin
	var free_now: bool = UNSTUCK_LOCATOR_SCRIPT.is_position_free(player, player.global_position)
	player.free()
	for node in [ground, slab, pillar]:
		node.free()
	if not moved or Vector2(offset.x, offset.z).length() < 1.4 or not free_now:
		_fail(test_root, "Sem espaco acima, destravar deveria mover para o lado; moveu=%s deslocamento=%s livre=%s." % [moved, offset, free_now])
		return
	print("PASS: Sem espaco acima, o boneco sai pelo lado.")


func _test_unstuck_has_cooldown(test_root: Node) -> void:
	print("Testando recarga do destravar...")
	var origin := Vector3(740.0, 0.0, 700.0)
	var player := _add_player(test_root, origin + Vector3(0.0, 1.0, 0.0))
	await test_root.get_tree().physics_frame
	var first: bool = player.unstuck()
	var second: bool = player.unstuck()
	player.call("_physics_process", player.UNSTUCK_COOLDOWN + 0.1)
	var after_cooldown: bool = player.unstuck()
	var cooldown: float = player.UNSTUCK_COOLDOWN
	player.free()
	if not first or second or not after_cooldown:
		_fail(test_root, "Destravar: primeiro ok, repetido em seguida bloqueado, depois da recarga ok; veio %s/%s/%s." % [first, second, after_cooldown])
		return
	print("PASS: Destravar tem recarga de %.0f s." % cooldown)


func _test_client_snaps_on_teleport_sequence(test_root: Node) -> void:
	print("Testando cliente teleportando o boneco destravado...")
	var player := _add_player(test_root, Vector3(760.0, 1.0, 700.0))
	player.simulation_enabled = false
	player.apply_network_state({"position": Vector3(760.0, 3.5, 700.0), "teleport_sequence": 0})
	var interpolated := player.global_position.is_equal_approx(Vector3(760.0, 1.0, 700.0))
	player.apply_network_state({"position": Vector3(760.0, 3.5, 700.0), "teleport_sequence": 1})
	var snapped := player.global_position.is_equal_approx(Vector3(760.0, 3.5, 700.0))
	player.free()
	if not interpolated or not snapped:
		_fail(test_root, "Mesma sequencia interpola; sequencia nova teleporta; interpolou=%s teleportou=%s." % [interpolated, snapped])
		return
	print("PASS: Cliente teleporta quando o servidor destrava o boneco.")


func _add_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	return player


func _add_box(test_root: Node, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	test_root.add_child(body)
	return body


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
