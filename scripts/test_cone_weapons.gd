extends RefCounted

## Regressoes da motosserra e do lanca-chamas (pedido de variedade): dano em
## cone curto com linha de visao, sem empurrao a cada tick, e fogo que queima
## com o tempo e passa para zumbis colados.
## Uso: await ConeWeaponsTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CONE_SCRIPT := preload("res://scripts/weapon_cone_attack.gd")
const BURN_SCRIPT := preload("res://scripts/zombie_burn.gd")


func run(test_root: Node) -> void:
	await _test_cone_picks_front_targets_with_line_of_sight(test_root)
	await _test_chainsaw_hits_group_without_knockback(test_root)
	await _test_fire_burns_over_time_and_spreads(test_root)
	_test_cone_weapons_in_arsenal(test_root)


func _zombie_at(test_root: Node, position: Vector3, zombie_name: String) -> CharacterBody3D:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = zombie_name
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	zombie.position = position
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	return zombie


func _test_cone_picks_front_targets_with_line_of_sight(test_root: Node) -> void:
	print("Testando alvos no cone com linha de visao...")
	var origin := Vector3(1200.0, 1.0, 1200.0)
	var front := _zombie_at(test_root, origin + Vector3(0.0, 0.0, -1.8), "ConeFront")
	var side := _zombie_at(test_root, origin + Vector3(3.0, 0.0, -0.5), "ConeSide")
	var far := _zombie_at(test_root, origin + Vector3(0.0, 0.0, -9.0), "ConeFar")
	var walled := _zombie_at(test_root, origin + Vector3(-1.2, 0.0, -2.2), "ConeWalled")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 3.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = origin + Vector3(-0.7, 0.5, -1.2)
	test_root.add_child(wall)
	await test_root.get_tree().physics_frame
	await test_root.get_tree().physics_frame
	var targets: Array[Node3D] = CONE_SCRIPT.targets_in_cone(test_root.get_tree(), origin + Vector3.UP * 0.55, Vector3.FORWARD, 3.0, 60.0)
	var names: Array[String] = []
	for target in targets:
		names.append(String(target.name))
	for node in [front, side, far, walled, wall]:
		node.free()
	if names != ["ConeFront"]:
		_fail(test_root, "Cone de 3 m/60 graus deveria pegar so o zumbi da frente (lado, longe e atras da parede ficam fora); veio %s." % [names])
		return
	print("PASS: Cone pega so quem esta na frente, perto e visivel.")


func _test_chainsaw_hits_group_without_knockback(test_root: Node) -> void:
	print("Testando motosserra cortando o grupo sem empurrar...")
	var origin := Vector3(1250.0, 1.0, 1200.0)
	var shooter := PLAYER_SCENE.instantiate() as CharacterBody3D
	shooter.set("reads_local_input", false)
	shooter.set("simulation_enabled", false)
	shooter.position = origin
	test_root.add_child(shooter)
	var zombies: Array[CharacterBody3D] = []
	for index in 3:
		zombies.append(_zombie_at(test_root, origin + Vector3(-0.6 + index * 0.6, 0.0, -1.6), "Saw%d" % index))
	await test_root.get_tree().physics_frame
	var stats := WeaponStats.stats_for(WeaponStats.Kind.CHAINSAW)
	var hits: int = CONE_SCRIPT.strike(test_root.get_tree(), origin + Vector3.UP * 0.55, Vector3.FORWARD, stats, shooter)
	var all_hurt := zombies.all(func(zombie: CharacterBody3D) -> bool: return int(zombie.get("health")) < int(zombie.get("max_health")))
	var pushed := zombies.any(func(zombie: CharacterBody3D) -> bool: return Vector2(zombie.velocity.x, zombie.velocity.z).length() > 0.01)
	shooter.free()
	for zombie in zombies:
		zombie.free()
	if hits != 3 or not all_hurt or pushed:
		_fail(test_root, "Motosserra deveria ferir os 3 zumbis da frente sem empurrar; acertos=%d feridos=%s empurrados=%s." % [hits, all_hurt, pushed])
		return
	print("PASS: Motosserra corta o grupo sem empurrar.")


func _test_fire_burns_over_time_and_spreads(test_root: Node) -> void:
	print("Testando fogo queimando com o tempo e passando para vizinho...")
	var origin := Vector3(1300.0, 1.0, 1200.0)
	var burning := _zombie_at(test_root, origin, "Burning")
	var neighbor := _zombie_at(test_root, origin + Vector3(1.0, 0.0, 0.0), "Neighbor")
	var distant := _zombie_at(test_root, origin + Vector3(6.0, 0.0, 0.0), "Distant")
	burning.set("max_health", 1000)
	burning.set("health", 1000)
	burning.call("ignite", 4.0, 20.0, null)
	var burn = burning.get("burn")
	for _tick in 45:
		burn.update(burning, 0.1)
	var burned := int(burning.get("health"))
	var neighbor_on_fire: bool = neighbor.get("burn").is_burning() or int(neighbor.get("health")) < int(neighbor.get("max_health"))
	var distant_safe: bool = not distant.get("burn").is_burning()
	var extinguished: bool = not burn.is_burning()
	for zombie in [burning, neighbor, distant]:
		zombie.free()
	# 4 s a 20 dps = 80 de dano (tolerancia de 1 tick).
	if absi(1000 - burned - 80) > 5 or not neighbor_on_fire or not distant_safe or not extinguished:
		_fail(test_root, "Fogo: dano=%d (esperado ~80), vizinho pegou=%s, distante seguro=%s, apagou=%s." % [1000 - burned, neighbor_on_fire, distant_safe, extinguished])
		return
	print("PASS: Fogo queima com o tempo, passa ao vizinho e apaga.")


func _test_cone_weapons_in_arsenal(test_root: Node) -> void:
	print("Testando motosserra e lanca-chamas no arsenal...")
	var saw := WeaponStats.stats_for(WeaponStats.Kind.CHAINSAW)
	var flame := WeaponStats.stats_for(WeaponStats.Kind.FLAMETHROWER)
	var saw_ok := float(saw.get("cone_range", 0.0)) > 0.0 and bool(saw.get("is_auto", false)) and not saw.has("burn_seconds")
	var flame_ok := float(flame.get("cone_range", 0.0)) > float(saw.get("cone_range", 0.0)) and float(flame.get("burn_seconds", 0.0)) > 0.0 and bool(flame.get("is_auto", false))
	if not saw_ok or not flame_ok:
		_fail(test_root, "Motosserra: cone curto automatico sem fogo; lanca-chamas: cone maior, automatico e incendeia; serra=%s chamas=%s." % [saw, flame])
		return
	print("PASS: Motosserra e lanca-chamas configurados.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
