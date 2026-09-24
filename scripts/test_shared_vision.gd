# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da visao compartilhada por raio: zumbi no raio de um aliado
## aparece para todos; fora do raio de todos fica oculto.
## Uso: SharedVisionTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const SHARED_VISION_SCRIPT := preload("res://scripts/shared_vision.gd")


func run(test_root: Node) -> void:
	_test_ally_reveals_zombie(test_root)


func _test_ally_reveals_zombie(test_root: Node) -> void:
	print("Testando zumbi no raio do aliado aparecendo para todos...")
	var origin := Vector3(930.0, 1.0, -930.0)
	var me := _add_player(test_root, origin, 0.0)
	var zombie := ZOMBIE_SCENE.instantiate() as Node3D
	zombie.name = "SharedVisionTarget"
	# Fora do meu raio, mas a 10 m do aliado.
	zombie.position = origin + Vector3(0.0, 0.0, PlayerCharacter.VIEW_RADIUS + 10.0)
	test_root.add_child(zombie)
	var alone: Array[CharacterBody3D] = [me]
	var alone_sees: bool = SHARED_VISION_SCRIPT.is_seen_by_any(alone, zombie)
	var ally := _add_player(test_root, origin + Vector3(0.0, 0.0, PlayerCharacter.VIEW_RADIUS), PI)
	var together: Array[CharacterBody3D] = [me, ally]
	var shared_sees: bool = SHARED_VISION_SCRIPT.is_seen_by_any(together, zombie)
	me.free()
	ally.free()
	zombie.free()
	if alone_sees or not shared_sees:
		_fail(test_root, "Fora do meu raio nao vejo; no raio do aliado todos veem; sozinho=%s aliado=%s." % [alone_sees, shared_sees])
		return
	print("PASS: Zumbi no raio do aliado aparece para todos.")


func _add_player(test_root: Node, position: Vector3, facing: float) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	player.rotation.y = facing
	test_root.add_child(player)
	return player


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
