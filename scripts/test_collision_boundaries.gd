# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")


## Verifica que ataques fisicos nao atravessam paredes.
## Uso: await CollisionBoundaryTests.new().run(test_root)
func run(test_root: Node) -> void:
	print("Testando bloqueio de ataques atraves de paredes...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2.0, 3.0, 0.2)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	test_root.add_child(player)
	test_root.add_child(zombie)
	test_root.add_child(wall)
	player.position = Vector3(30.0, 1.0, 0.0)
	zombie.position = Vector3(30.0, 1.0, -1.4)
	wall.position = Vector3(30.0, 1.5, -0.7)
	await test_root.get_tree().physics_frame
	var zombie_health: int = zombie.health
	player.call("_attack_with_knife")
	if zombie.health != zombie_health:
		_fail(test_root, "Faca atingiu zumbi atraves da parede; vida=%d/%d." % [zombie.health, zombie_health])
	var bullet := player.call("_fire_pistol") as Node3D
	bullet.call("_physics_process", 0.1)
	if zombie.health != zombie_health:
		_fail(test_root, "Pistola disparou do outro lado da parede; vida=%d/%d." % [zombie.health, zombie_health])
	var player_health: int = player.health
	zombie.call("_attack_target_or_door", player)
	if player.health != player_health:
		_fail(test_root, "Zumbi atingiu jogador atraves da parede; vida=%d/%d." % [player.health, player_health])
	player.queue_free()
	zombie.queue_free()
	wall.queue_free()
	if is_instance_valid(bullet):
		bullet.queue_free()
	if not bool(test_root.get_meta("unit_test_failed", false)):
		print("PASS: Parede bloqueia faca, pistola e ataque de zumbi.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
