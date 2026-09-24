# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do telhado da casa segura: laje com alcapao, escada da passarela
## ate o telhado e saida pelos fundos (descida so de ida, sem escada externa
## para a horda subir).
## Uso: await SafehouseRoofTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SAFEHOUSE_BUILDER_SCRIPT := preload("res://scripts/safehouse_builder.gd")
const ROOF_BUILDER_SCRIPT := preload("res://scripts/safehouse_roof_builder.gd")
const STEP_DELTA := 1.0 / 60.0


func run(test_root: Node) -> void:
	_test_roof_structure(test_root)
	await _test_player_climbs_to_roof(test_root)
	await _test_player_leaves_through_back_exit(test_root)


func _test_roof_structure(test_root: Node) -> void:
	print("Testando telhado, mureta e saida da casa segura...")
	var safehouse: StaticBody3D = SAFEHOUSE_BUILDER_SCRIPT.build_safehouse()
	var parts := ["RoofSlabWestMesh", "RoofRampCol", "RoofParapetNorthMesh", "RoofParapetBackLeftMesh", "RoofParapetBackRightMesh", "RoofExitLedgeMesh"]
	var missing: Array[String] = []
	for part in parts:
		if not safehouse.has_node(part):
			missing.append(part)
	var gap_left := safehouse.get_node_or_null("RoofParapetBackLeftMesh") as MeshInstance3D
	var gap_right := safehouse.get_node_or_null("RoofParapetBackRightMesh") as MeshInstance3D
	var gap := 0.0
	if gap_left != null and gap_right != null:
		var left_end := gap_left.position.x + (gap_left.mesh as BoxMesh).size.x * 0.5
		var right_start := gap_right.position.x - (gap_right.mesh as BoxMesh).size.x * 0.5
		gap = right_start - left_end
	safehouse.free()
	if not missing.is_empty() or gap < ROOF_BUILDER_SCRIPT.EXIT_GAP_WIDTH - 0.01:
		_fail(test_root, "Telhado deveria ter laje, rampa, mureta e vao de saida de %.1f m; faltando=%s vao=%.2f." % [ROOF_BUILDER_SCRIPT.EXIT_GAP_WIDTH, missing, gap])
		return
	print("PASS: Telhado com laje, rampa, mureta e vao de saida de %.1f m." % gap)


func _test_player_climbs_to_roof(test_root: Node) -> void:
	print("Testando jogador subindo da passarela ao telhado...")
	var origin := Vector3(-700.0, 0.0, -950.0)
	var safehouse := _add_safehouse(test_root, origin)
	var player := _add_player(test_root, safehouse.global_position + Vector3(ROOF_BUILDER_SCRIPT.RAMP_CENTER_X, SAFEHOUSE_BUILDER_SCRIPT.FLOOR_HEIGHT + 1.1, ROOF_BUILDER_SCRIPT.RAMP_BOTTOM_Z + 0.6))
	await test_root.get_tree().physics_frame
	var roof_top: float = safehouse.global_position.y + ROOF_BUILDER_SCRIPT.ROOF_Y
	var reached := await _walk(test_root, player, Vector2(0.0, -1.0), 360, func() -> bool: return player.global_position.y - 0.9 >= roof_top - 0.2)
	var final_local := player.global_position - safehouse.global_position
	player.free()
	safehouse.free()
	if not reached:
		_fail(test_root, "Jogador deveria subir a rampa ate o telhado (pes >= %.1f); parou em %s (local)." % [ROOF_BUILDER_SCRIPT.ROOF_Y - 0.2, final_local])
		return
	print("PASS: Jogador sobe da passarela ao telhado.")


func _test_player_leaves_through_back_exit(test_root: Node) -> void:
	print("Testando saida pelo vao dos fundos do telhado...")
	var origin := Vector3(-680.0, 0.0, -950.0)
	var ground := _add_ground(test_root, origin)
	var safehouse := _add_safehouse(test_root, origin)
	var player := _add_player(test_root, safehouse.global_position + Vector3(0.0, ROOF_BUILDER_SCRIPT.ROOF_Y + 1.2, 4.5))
	await test_root.get_tree().physics_frame
	var outside := await _walk(test_root, player, Vector2(0.0, 1.0), 480, func() -> bool:
		var local := player.global_position - safehouse.global_position
		return local.z > 8.5 and local.y < 1.6)
	var final_local := player.global_position - safehouse.global_position
	player.free()
	safehouse.free()
	ground.free()
	if not outside:
		_fail(test_root, "Jogador no telhado deveria sair pelo vao dos fundos e chegar ao chao do lado de fora; parou em %s (local)." % final_local)
		return
	print("PASS: Jogador sai por cima e desce pelos fundos da casa segura.")


func _walk(test_root: Node, player: CharacterBody3D, direction: Vector2, max_steps: int, is_done: Callable) -> bool:
	for step in max_steps:
		player.set("remote_input_age", 0.0)
		player.set("move_input", direction)
		player.call("_physics_process", STEP_DELTA)
		if bool(is_done.call()):
			return true
		if step % 30 == 29:
			await test_root.get_tree().process_frame
	return false


func _add_safehouse(test_root: Node, origin: Vector3) -> StaticBody3D:
	var safehouse: StaticBody3D = SAFEHOUSE_BUILDER_SCRIPT.build_safehouse()
	safehouse.position = origin + Vector3(0.0, 0.12, 0.0)
	test_root.add_child(safehouse)
	return safehouse


func _add_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
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
	# Mesmo chao da main.tscn: caixa de 0.2 m centrada em y=0.
	ground.position = origin
	test_root.add_child(ground)
	return ground


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
