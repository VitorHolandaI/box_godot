# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do limite de jogadores por servidor (antes fixo em 4, o mesmo
## numero da tela dividida) e do spawn de quem passa dos 4 marcadores.
## Uso: PlayerCapacityTests.new().run(test_root)

const PLAYER_CAPACITY_SCRIPT := preload("res://scripts/player_capacity.gd")


func run(test_root: Node) -> void:
	_test_max_players_argument(test_root)
	_test_join_rejection(test_root)
	_test_spawn_offsets_do_not_stack(test_root)


func _test_max_players_argument(test_root: Node) -> void:
	print("Testando --max-players do servidor...")
	var default_cap: int = PLAYER_CAPACITY_SCRIPT.max_players_from_arguments(PackedStringArray(["--server"]))
	var custom_cap: int = PLAYER_CAPACITY_SCRIPT.max_players_from_arguments(PackedStringArray(["--max-players=12"]))
	var invalid_cap: int = PLAYER_CAPACITY_SCRIPT.max_players_from_arguments(PackedStringArray(["--max-players=0"]))
	var huge_cap: int = PLAYER_CAPACITY_SCRIPT.max_players_from_arguments(PackedStringArray(["--max-players=99999"]))
	var expected_default: int = PLAYER_CAPACITY_SCRIPT.DEFAULT_MAX_PLAYERS
	if default_cap != expected_default or custom_cap != 12 or invalid_cap != expected_default or huge_cap != expected_default:
		_fail(test_root, "--max-players esperado default=%d custom=12 invalido/enorme=default; veio %d/%d/%d/%d." % [expected_default, default_cap, custom_cap, invalid_cap, huge_cap])
		return
	print("PASS: Argumento --max-players validado.")


func _test_join_rejection(test_root: Node) -> void:
	print("Testando entrada de jogadores alem de 4 no servidor...")
	var fifth_ok: String = PLAYER_CAPACITY_SCRIPT.join_rejection(4, 1, 32)
	var split_screen_ok: String = PLAYER_CAPACITY_SCRIPT.join_rejection(20, 4, 32)
	var too_many_local: String = PLAYER_CAPACITY_SCRIPT.join_rejection(0, 5, 32)
	var zero_local: String = PLAYER_CAPACITY_SCRIPT.join_rejection(0, 0, 32)
	var server_full: String = PLAYER_CAPACITY_SCRIPT.join_rejection(31, 2, 32)
	if not fifth_ok.is_empty() or not split_screen_ok.is_empty() or too_many_local.is_empty() or zero_local.is_empty() or not server_full.contains("32"):
		_fail(test_root, "Entrada esperada: 5o e tela dividida aceitos, 0/5 locais recusados, cheio cita o limite; veio '%s' '%s' '%s' '%s' '%s'." % [fifth_ok, split_screen_ok, too_many_local, zero_local, server_full])
		return
	print("PASS: Entrada alem de 4 jogadores validada.")


func _test_spawn_offsets_do_not_stack(test_root: Node) -> void:
	print("Testando spawn de jogadores alem dos 4 marcadores...")
	var marker_count := 4
	var seen: Dictionary = {}
	for slot in 32:
		var marker_index := slot % marker_count
		var offset: Vector3 = PLAYER_CAPACITY_SCRIPT.spawn_offset(slot, marker_count)
		var key := "%d:%.2f:%.2f" % [marker_index, offset.x, offset.z]
		if seen.has(key) or offset.y != 0.0 or Vector2(offset.x, offset.z).length() > PLAYER_CAPACITY_SCRIPT.MAX_SPAWN_OFFSET + 0.001:
			_fail(test_root, "Slot %d repete posicao ou sai do raio de spawn; offset=%s." % [slot, offset])
			return
		seen[key] = true
	if PLAYER_CAPACITY_SCRIPT.spawn_offset(3, marker_count) != Vector3.ZERO:
		_fail(test_root, "Os 4 primeiros jogadores nascem exatamente nos marcadores.")
		return
	print("PASS: Spawn alem dos marcadores sem empilhar.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
