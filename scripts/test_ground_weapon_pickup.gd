extends RefCounted

## Regressoes da coleta de arma no chao: com arma de crate na mao ou guardada,
## apertar interagir perto troca a arma (a antiga cai no chao).
## Uso: await GroundWeaponPickupTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")


func run(test_root: Node) -> void:
	await _test_swap_while_holding_crate_weapon(test_root)
	await _test_swap_while_holding_pistol(test_root)
	await _test_pickup_is_big_with_name_near_player(test_root)


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
