# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes dos itens arremessaveis (pedido de variedade): contagem de
## granadas/facas/chamadas, teclas proprias sem conflito, granada em arco que
## explode na horda e faca de arremesso silenciosa.
## Uso: await EquipmentTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const EQUIPMENT_SCRIPT := preload("res://scripts/player_equipment.gd")
const GRENADE_SCRIPT := preload("res://scripts/thrown_grenade.gd")
const NEW_ACTIONS := ["grenade", "throw_knife", "air_strike", "swat"]


func run(test_root: Node) -> void:
	_test_counts_start_clamp_and_consume(test_root)
	_test_new_actions_have_free_keys(test_root)
	await _test_grenade_explodes_on_zombies_only(test_root)
	await _test_player_throws_grenade_and_knife(test_root)
	_test_supply_pickup_adds_grenades(test_root)


func _test_counts_start_clamp_and_consume(test_root: Node) -> void:
	print("Testando contagem de granadas, facas e chamadas...")
	var equipment = EQUIPMENT_SCRIPT.new()
	var grenade: int = EQUIPMENT_SCRIPT.Item.GRENADE
	var start_ok: bool = equipment.count_of(grenade) == 2 and equipment.count_of(EQUIPMENT_SCRIPT.Item.THROWING_KNIFE) == 3 and equipment.count_of(EQUIPMENT_SCRIPT.Item.AIR_STRIKE) == 0
	var added: int = equipment.add(grenade, 10)
	var clamped: bool = equipment.count_of(grenade) == int(EQUIPMENT_SCRIPT.MAX_COUNTS[grenade])
	var consumed := 0
	for _try in 10:
		if equipment.try_consume(grenade):
			consumed += 1
	var no_air_strike: bool = not equipment.try_consume(EQUIPMENT_SCRIPT.Item.AIR_STRIKE)
	var copy = EQUIPMENT_SCRIPT.new()
	copy.apply_counts(equipment.to_counts())
	if not start_ok or added != 3 or not clamped or consumed != 5 or not no_air_strike or copy.to_counts() != equipment.to_counts():
		_fail(test_root, "Itens: inicio=%s adicionou=%d (esperado 3) limitado=%s consumiu=%d (esperado 5) sem_aereo=%s copia=%s." % [start_ok, added, clamped, consumed, no_air_strike, copy.to_counts()])
		return
	print("PASS: Contagem de itens com inicio, limite e consumo.")


func _test_new_actions_have_free_keys(test_root: Node) -> void:
	print("Testando teclas novas sem conflito em cada perfil...")
	var problems: Array[String] = []
	for action in NEW_ACTIONS:
		if not GameConfig.ACTIONS.has(action):
			problems.append("acao %s ausente" % action)
	for slot in 4:
		var config: Dictionary = GameConfig.create_keyboard_config(slot)
		var seen: Dictionary = {}
		for action in GameConfig.ACTIONS:
			var event := config["bindings"].get(action) as InputEventKey
			if event == null:
				problems.append("perfil %d sem tecla para %s" % [slot, action])
				continue
			if seen.has(event.physical_keycode):
				problems.append("perfil %d repete tecla em %s e %s" % [slot, seen[event.physical_keycode], action])
			seen[event.physical_keycode] = action
	var pad: Dictionary = GameConfig.create_gamepad_config(0)
	for action in NEW_ACTIONS:
		if not pad["bindings"].has(action):
			problems.append("controle sem botao para %s" % action)
	if not problems.is_empty():
		_fail(test_root, "Teclas dos itens: %s." % [problems])
		return
	print("PASS: Itens com teclas proprias em todos os perfis e no controle.")


func _test_grenade_explodes_on_zombies_only(test_root: Node) -> void:
	print("Testando granada explodindo na horda sem ferir jogador...")
	var origin := Vector3(1400.0, 1.0, 1300.0)
	var thrower := PLAYER_SCENE.instantiate() as CharacterBody3D
	thrower.set("reads_local_input", false)
	thrower.set("simulation_enabled", false)
	thrower.position = origin + Vector3(0.0, 0.0, 3.0)
	test_root.add_child(thrower)
	var near := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	near.position = origin + Vector3(1.5, 0.0, 0.0)
	test_root.add_child(near)
	near.set_physics_process(false)
	var far := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	far.position = origin + Vector3(GRENADE_SCRIPT.RADIUS + 3.0, 0.0, 0.0)
	test_root.add_child(far)
	far.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 0.2, 20.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = origin + Vector3(0.0, -0.1, 0.0)
	test_root.add_child(floor_body)
	var grenade = GRENADE_SCRIPT.new()
	test_root.add_child(grenade)
	grenade.set_physics_process(false)
	grenade.setup(origin + Vector3.UP * 0.2, Vector3.ZERO, true, thrower)
	await test_root.get_tree().physics_frame
	var steps := 0
	while is_instance_valid(grenade) and not grenade.is_queued_for_deletion() and steps < 200:
		grenade.advance(0.05)
		steps += 1
	var near_hurt := int(near.get("health")) < int(near.get("max_health"))
	var far_safe := int(far.get("health")) == int(far.get("max_health"))
	var thrower_safe := int(thrower.get("health")) == int(thrower.get("max_health"))
	var exploded_on_time: bool = absf(steps * 0.05 - GRENADE_SCRIPT.FUSE_SECONDS) <= 0.051
	for node in [thrower, near, far, floor_body]:
		node.free()
	if not near_hurt or not far_safe or not thrower_safe or not exploded_on_time:
		_fail(test_root, "Granada: zumbi perto ferido=%s, longe seguro=%s, jogador seguro=%s, explodiu em %.2f s (pavio %.2f)." % [near_hurt, far_safe, thrower_safe, steps * 0.05, GRENADE_SCRIPT.FUSE_SECONDS])
		return
	print("PASS: Granada explode no pavio, fere zumbis perto e poupa jogadores.")


func _test_player_throws_grenade_and_knife(test_root: Node) -> void:
	print("Testando jogador arremessando granada e faca...")
	var origin := Vector3(1450.0, 1.0, 1300.0)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.position = origin
	test_root.add_child(player)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.position = origin + Vector3(0.0, 0.0, -5.0)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	await test_root.get_tree().physics_frame
	player.set("aim_input", Vector2(0.0, -1.0))
	player.set("grenade_pressed", true)
	player.call("_handle_equipment_input")
	var grenades_left := int(player.get("equipment").count_of(EQUIPMENT_SCRIPT.Item.GRENADE))
	var thrown := test_root.get_tree().get_nodes_in_group("thrown_grenades").size()
	player.set("equipment_cooldown", 0.0)
	player.set("grenade_pressed", false)
	player.set("throw_knife_pressed", true)
	player.call("_handle_equipment_input")
	var knives_left := int(player.get("equipment").count_of(EQUIPMENT_SCRIPT.Item.THROWING_KNIFE))
	var knifed := int(zombie.get("health")) < int(zombie.get("max_health"))
	for node in test_root.get_tree().get_nodes_in_group("thrown_grenades"):
		node.free()
	player.free()
	zombie.free()
	if grenades_left != 1 or thrown != 1 or knives_left != 2 or not knifed:
		_fail(test_root, "Arremesso: granadas=%d (esperado 1), granadas no mundo=%d, facas=%d (esperado 2), zumbi ferido pela faca=%s." % [grenades_left, thrown, knives_left, knifed])
		return
	print("PASS: Jogador arremessa granada e faca gastando os itens.")


func _test_supply_pickup_adds_grenades(test_root: Node) -> void:
	print("Testando item de granadas no chao...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	test_root.add_child(player)
	var pickup := GroundSupplyPickup.new()
	pickup.setup(GroundSupplyPickup.Kind.EQUIP_GRENADES, 2)
	test_root.add_child(pickup)
	pickup.call("_on_body_entered", player)
	var grenades := int(player.get("equipment").count_of(EQUIPMENT_SCRIPT.Item.GRENADE))
	var taken := pickup.is_queued_for_deletion()
	player.free()
	if is_instance_valid(pickup):
		pickup.free()
	if grenades != 4 or not taken:
		_fail(test_root, "Item de granadas deveria somar 2 (2 -> 4) e sumir; granadas=%d sumiu=%s." % [grenades, taken])
		return
	print("PASS: Item de granadas soma na contagem.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
