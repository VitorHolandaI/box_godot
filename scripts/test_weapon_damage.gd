extends RefCounted

## Regressoes de dano das armas: hitscan das armas de crate e projetil da
## pistola precisam tirar vida do zumbi a frente (antes so os tracers visuais
## eram testados, entao um raio que acertava o proprio atirador passava).
## Uso: await WeaponDamageTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")


func run(test_root: Node) -> void:
	await _test_crate_hitscan_damages_zombie_ahead(test_root)
	await _test_pistol_bullet_damages_zombie_ahead(test_root)
	await _test_hit_tolerates_network_offset(test_root)


func _test_crate_hitscan_damages_zombie_ahead(test_root: Node) -> void:
	print("Testando dano do hitscan da arma de crate...")
	var origin := Vector3(-960.0, 1.0, 960.0)
	var player := _add_player(test_root, origin)
	var zombie := _add_target_zombie(test_root, origin + Vector3(0.0, 0.0, -5.0))
	await test_root.get_tree().physics_frame
	player.call("take_crate_weapon", WeaponStats.Kind.UZI)
	player.current_weapon = PlayerCharacter.Weapon.UZI
	var before := int(zombie.get("health"))
	player.call("_fire_crate_weapon")
	var after := int(zombie.get("health"))
	var player_health := int(player.get("health"))
	player.free()
	zombie.free()
	if after >= before or player_health < 100:
		_fail(test_root, "Uzi deveria ferir o zumbi a 5 m e nao o atirador; zumbi %d->%d vida_atirador=%d." % [before, after, player_health])
		return
	print("PASS: Hitscan da uzi fere o zumbi a frente.")


func _test_pistol_bullet_damages_zombie_ahead(test_root: Node) -> void:
	print("Testando dano do projetil da pistola...")
	var origin := Vector3(-940.0, 1.0, 960.0)
	var player := _add_player(test_root, origin)
	var zombie := _add_target_zombie(test_root, origin + Vector3(0.0, 0.0, -5.0))
	await test_root.get_tree().physics_frame
	player.current_weapon = PlayerCharacter.Weapon.PISTOL
	var before := int(zombie.get("health"))
	player.call("_fire_pistol")
	for _frame in 30:
		await test_root.get_tree().physics_frame
	var after := int(zombie.get("health"))
	player.free()
	zombie.free()
	if after >= before:
		_fail(test_root, "Bala da pistola deveria ferir o zumbi a 5 m; vida %d->%d." % [before, after])
		return
	print("PASS: Projetil da pistola fere o zumbi a frente.")


## Zumbi 0.8 m ao lado da linha do tiro (o quanto um corredor anda nos ~250 ms
## de atraso do cliente): raio fino errava, a esfera de tolerancia acerta.
func _test_hit_tolerates_network_offset(test_root: Node) -> void:
	print("Testando tolerancia do tiro ao atraso de rede...")
	var origin := Vector3(-920.0, 1.0, 960.0)
	var player := _add_player(test_root, origin)
	var zombie := _add_target_zombie(test_root, origin + Vector3(0.8, 0.0, -8.0))
	await test_root.get_tree().physics_frame
	var before := int(zombie.get("health"))
	Bullet.hitscan_damage(origin + Vector3.UP * 0.55, Vector3.FORWARD, 20, player)
	var after := int(zombie.get("health"))
	player.free()
	zombie.free()
	if after >= before:
		_fail(test_root, "Tiro passando a 0.8 m do centro do zumbi deveria acertar com a tolerancia; vida %d->%d." % [before, after])
		return
	print("PASS: Tiro tolera o atraso de rede (0.8 m fora da linha).")


func _add_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	return player


func _add_target_zombie(test_root: Node, position: Vector3) -> CharacterBody3D:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "WeaponDamageTarget"
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	zombie.set("gravity", 0.0)
	zombie.position = position
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	return zombie


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
