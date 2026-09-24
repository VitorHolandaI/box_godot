# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da coleta de arma no chao: com arma de crate na mao ou guardada,
## apertar interagir perto troca a arma (a antiga cai no chao).
## Uso: await GroundWeaponPickupTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")


func run(test_root: Node) -> void:
	await _test_swap_while_holding_crate_weapon(test_root)
	await _test_swap_while_holding_pistol(test_root)
	await _test_pickup_is_big_with_name_near_player(test_root)
	_test_split_ammo_takes_reserve_then_mag(test_root)
	_test_walking_over_same_weapon_takes_ammo(test_root)
	_test_other_weapon_or_far_player_keeps_ammo(test_root)


func _test_swap_while_holding_crate_weapon(test_root: Node) -> void:
	print("Testando troca de arma no chao com o laser na mao...")
	var result := await _swap_scenario(test_root, Vector3(-800.0, 1.0, -800.0), true)
	if not result.is_empty():
		_fail(test_root, "Com laser na mao: %s." % result)
		return
	print("PASS: Laser na mao troca pela arma do chao com E.")


func _test_swap_while_holding_pistol(test_root: Node) -> void:
	print("Testando troca de arma no chao com a pistola na mao e laser guardado...")
	var result := await _swap_scenario(test_root, Vector3(-780.0, 1.0, -800.0), false)
	if not result.is_empty():
		_fail(test_root, "Com pistola na mao e laser guardado: %s." % result)
		return
	print("PASS: Pistola na mao com laser guardado tambem troca com E.")


func _test_pickup_is_big_with_name_near_player(test_root: Node) -> void:
	print("Testando arma no chao grande, assentada e com nome perto do jogador...")
	var origin := Vector3(-760.0, 0.0, -800.0)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10.0, 0.2, 10.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = origin
	test_root.add_child(floor_body)
	var pickup := GroundWeaponPickup.new()
	pickup.setup(WeaponStats.Kind.AK47, 30, 60, 200)
	test_root.add_child(pickup)
	pickup.global_position = origin + Vector3(0.0, 0.9, 0.0)
	await test_root.get_tree().physics_frame
	pickup.call("_process", 0.2)
	var label := pickup.get_node("NameLabel") as Label3D
	var hidden_far := not label.visible
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", true)
	player.position = origin + Vector3(1.0, 1.0, 0.0)
	test_root.add_child(player)
	pickup.call("_process", 0.2)
	var shown_near := label.visible and label.text.contains("AK-47")
	var on_floor := absf(pickup.global_position.y - (origin.y + 0.12)) < 0.05
	var model := pickup.find_child("CrateWeapon%d" % WeaponStats.Kind.AK47, true, false) as Node3D
	var big := model != null and model.scale.x >= 1.5
	var synced: Array = GroundWeaponSync.collect(test_root.get_tree()).filter(func(entry: Array) -> bool: return String(entry[0]) == String(pickup.name))
	var has_lifetime := not synced.is_empty() and (synced[0][5] as Array).size() >= 5
	player.free()
	pickup.free()
	floor_body.free()
	if not hidden_far or not shown_near or not on_floor or not big or not has_lifetime:
		_fail(test_root, "Arma no chao: nome so perto, assentada no piso, modelo grande e tempo no sync; longe_oculto=%s perto_visivel=%s no_chao=%s grande=%s tempo=%s." % [hidden_far, shown_near, on_floor, big, has_lifetime])
		return
	print("PASS: Arma no chao grande, no piso e com nome para quem chega perto.")


func _test_split_ammo_takes_reserve_then_mag(test_root: Node) -> void:
	print("Testando divisao da municao da arma no chao...")
	var partial: Dictionary = GroundWeaponPickup.split_ammo(22, 80, 50)
	var drained: Dictionary = GroundWeaponPickup.split_ammo(22, 10, 50)
	var no_space: Dictionary = GroundWeaponPickup.split_ammo(22, 80, 0)
	var partial_ok := int(partial["taken"]) == 50 and int(partial["reserve"]) == 30 and int(partial["mag"]) == 22
	var drained_ok := int(drained["taken"]) == 32 and int(drained["reserve"]) == 0 and int(drained["mag"]) == 0
	var no_space_ok := int(no_space["taken"]) == 0 and int(no_space["reserve"]) == 80 and int(no_space["mag"]) == 22
	if not partial_ok or not drained_ok or not no_space_ok:
		_fail(test_root, "Municao do chao sai da reserva e depois do pente ate o espaco; parcial=%s esvaziada=%s sem_espaco=%s." % [partial, drained, no_space])
		return
	print("PASS: Municao do chao sai da reserva e depois do pente.")


## Pedido: com uma Uzi na mao, passar por cima de outra Uzi pega a municao dela
## sem apertar E; o que nao cabe fica na arma do chao.
func _test_walking_over_same_weapon_takes_ammo(test_root: Node) -> void:
	print("Testando passar por cima da mesma arma pegando a municao...")
	var origin := Vector3(-740.0, 1.0, -800.0)
	var player := _ammo_player(test_root, origin, 200)
	var pickup := GroundWeaponPickup.new()
	pickup.setup(WeaponStats.Kind.UZI, 20, 30, 150)
	test_root.add_child(pickup)
	pickup.global_position = origin
	pickup.absorb_ammo_from_nearby_players(test_root.get_tree())
	var reserve := int((player.get("weapon_slots") as WeaponSlots).state_of(WeaponStats.Kind.UZI)["reserve"])
	var left_mag := pickup.mag
	var left_reserve := pickup.reserve
	var still_there := not pickup.is_queued_for_deletion()
	player.free()
	var empty_player := _ammo_player(test_root, origin, 100)
	pickup.absorb_ammo_from_nearby_players(test_root.get_tree())
	var emptied := pickup.is_queued_for_deletion()
	empty_player.free()
	pickup.free()
	if reserve != 240 or left_mag != 10 or left_reserve != 0 or not still_there or not emptied:
		_fail(test_root, "Uzi no chao: reserva do jogador=%d (esperado 240), sobra pente=%d reserva=%d (esperado 10/0), ficou=%s, some ao esvaziar=%s." % [reserve, left_mag, left_reserve, still_there, emptied])
		return
	print("PASS: Passar pela mesma arma pega a municao e deixa o resto.")


func _test_other_weapon_or_far_player_keeps_ammo(test_root: Node) -> void:
	print("Testando arma diferente ou jogador longe sem pegar municao...")
	var origin := Vector3(-720.0, 1.0, -800.0)
	var player := _ammo_player(test_root, origin + Vector3(GroundWeaponPickup.AMMO_ABSORB_RADIUS + 1.0, 0.0, 0.0), 200)
	var far_uzi := GroundWeaponPickup.new()
	far_uzi.setup(WeaponStats.Kind.UZI, 20, 30, 150)
	test_root.add_child(far_uzi)
	far_uzi.global_position = origin
	far_uzi.absorb_ammo_from_nearby_players(test_root.get_tree())
	var near_ak := GroundWeaponPickup.new()
	near_ak.setup(WeaponStats.Kind.AK47, 30, 60, 200)
	test_root.add_child(near_ak)
	near_ak.global_position = player.global_position
	near_ak.absorb_ammo_from_nearby_players(test_root.get_tree())
	var untouched := far_uzi.reserve == 30 and far_uzi.mag == 20 and near_ak.reserve == 60 and near_ak.mag == 30
	player.free()
	far_uzi.free()
	near_ak.free()
	if not untouched:
		_fail(test_root, "Uzi longe (>%.1f m) e AK perto de quem tem Uzi deveriam manter a municao." % GroundWeaponPickup.AMMO_ABSORB_RADIUS)
		return
	print("PASS: Arma diferente ou longe nao perde municao.")


func _ammo_player(test_root: Node, position: Vector3, uzi_reserve: int) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	player.call("take_crate_weapon", WeaponStats.Kind.UZI)
	(player.get("weapon_slots") as WeaponSlots).state_of(WeaponStats.Kind.UZI)["reserve"] = uzi_reserve
	return player


## Devolve "" quando a troca funcionou; senao a descricao do que falhou.
func _swap_scenario(test_root: Node, origin: Vector3, hold_crate: bool) -> String:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("is_local_controller", false)
	player.position = origin
	test_root.add_child(player)
	player.call("take_crate_weapon", WeaponStats.Kind.LASER_RIFLE)
	player.set("current_weapon", WeaponStats.Kind.LASER_RIFLE if hold_crate else PlayerCharacter.Weapon.PISTOL)
	var pickup := GroundWeaponPickup.new()
	pickup.setup(WeaponStats.Kind.AK47, 30, 60, 200)
	test_root.add_child(pickup)
	pickup.global_position = Vector3(origin.x + 1.5, 0.02, origin.z)
	await test_root.get_tree().process_frame
	player.set("interact_pressed", true)
	player.call("_handle_interaction_input")
	var slots: WeaponSlots = player.get("weapon_slots")
	var has_ak := slots.has_kind(WeaponStats.Kind.AK47)
	var holding := int(player.get("current_weapon"))
	var taken := pickup.is_queued_for_deletion() or not is_instance_valid(pickup)
	var report := "tem_ak=%s na_mao=%d arma_saiu_do_chao=%s" % [has_ak, holding, taken]
	player.free()
	if is_instance_valid(pickup):
		pickup.free()
	if not has_ak or holding != WeaponStats.Kind.AK47 or not taken:
		return report
	return ""


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
