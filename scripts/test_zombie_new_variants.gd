extends RefCounted

## Regressoes das variantes bloater (explode ao morrer), leaper (bote) e
## armored (colete corta dano de tiro), e do mix das ondas com elas.
## Uso: ZombieNewVariantsTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ABILITIES_SCRIPT := preload("res://scripts/zombie_variant_abilities.gd")
const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")


func run(test_root: Node) -> void:
	_test_new_variants_have_own_stats(test_root)
	_test_armored_halves_bullet_damage(test_root)
	_test_bloater_burst_hits_only_nearby(test_root)
	_test_leaper_lunges_then_cools_down(test_root)
	_test_late_waves_mix_new_variants(test_root)


func _test_new_variants_have_own_stats(test_root: Node) -> void:
	print("Testando stats de bloater, leaper e armored...")
	var bloater := _add_zombie(test_root, "VariantBloater", ZombieMutator.Type.BLOATER, Vector3(-980.0, 1.0, 0.0))
	var leaper := _add_zombie(test_root, "VariantLeaper", ZombieMutator.Type.LEAPER, Vector3(-980.0, 1.0, 5.0))
	var armored := _add_zombie(test_root, "VariantArmored", ZombieMutator.Type.ARMORED, Vector3(-980.0, 1.0, 10.0))
	var types_ok := int(bloater.get("zombie_type")) == ZombieMutator.Type.BLOATER and int(leaper.get("zombie_type")) == ZombieMutator.Type.LEAPER and int(armored.get("zombie_type")) == ZombieMutator.Type.ARMORED
	var stats_ok := int(bloater.get("max_health")) == 140 and float(bloater.get("speed")) >= 3.0 and float(leaper.get("speed")) > 2.4 and int(armored.get("max_health")) == 160
	var report := "bloater=%s/%s leaper=%s armored=%s" % [bloater.get("max_health"), bloater.get("speed"), leaper.get("speed"), armored.get("max_health")]
	for zombie in [bloater, leaper, armored]:
		zombie.free()
	if not types_ok or not stats_ok:
		_fail(test_root, "Variantes novas com tipo e stats proprios; %s." % report)
		return
	print("PASS: Bloater, leaper e armored nascem com stats proprios.")


func _test_armored_halves_bullet_damage(test_root: Node) -> void:
	print("Testando colete do armored contra tiro e faca...")
	var bullet: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.ARMORED, 40, "bullet")
	var knife: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.ARMORED, 40, "knife")
	var walker_bullet: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.WALKER, 40, "bullet")
	if bullet != 20 or knife != 40 or walker_bullet != 40:
		_fail(test_root, "Armored: tiro 40 vira 20, faca fica 40, walker sem reducao; veio %d/%d/%d." % [bullet, knife, walker_bullet])
		return
	print("PASS: Colete do armored corta metade do dano de tiro.")


func _test_bloater_burst_hits_only_nearby(test_root: Node) -> void:
	print("Testando explosao do bloater em area...")
	var origin := Vector3(-990.0, 1.0, -990.0)
	var near_player := _add_player(test_root, origin + Vector3(2.0, 0.0, 0.0))
	var far_player := _add_player(test_root, origin + Vector3(12.0, 0.0, 0.0))
	var neighbor := _add_zombie(test_root, "BurstNeighbor", ZombieMutator.Type.WALKER, origin + Vector3(0.0, 0.0, 2.0))
	var near_before := int(near_player.get("health"))
	var neighbor_before := int(neighbor.get("health"))
	ABILITIES_SCRIPT.bloater_burst(test_root.get_tree(), origin, null)
	var near_hit := int(near_player.get("health")) < near_before
	var far_safe := int(far_player.get("health")) == int(far_player.get("max_health"))
	var neighbor_hit := int(neighbor.get("health")) < neighbor_before
	near_player.free()
	far_player.free()
	neighbor.free()
	if not near_hit or not far_safe or not neighbor_hit:
		_fail(test_root, "Explosao deveria ferir jogador e zumbi a 2 m e poupar o jogador a 12 m; perto=%s longe_ileso=%s zumbi=%s." % [near_hit, far_safe, neighbor_hit])
		return
	print("PASS: Bloater explode ferindo quem esta perto.")


func _test_leaper_lunges_then_cools_down(test_root: Node) -> void:
	print("Testando bote do leaper...")
	var leap = ABILITIES_SCRIPT.LeapState.new()
	var toward := Vector3(1.0, 0.0, 0.0)
	var far: Vector3 = leap.update(1.0 / 60.0, Vector3.ZERO, toward, 9.0, true, 22.0)
	var lunge: Vector3 = leap.update(1.0 / 60.0, Vector3.ZERO, toward, 3.5, true, 22.0)
	var mid_air: bool = leap.is_leaping()
	var aloft: Vector3 = leap.update(0.1, Vector3(0.0, -2.0, 0.0), toward, 3.5, false, 22.0)
	var landed: Vector3 = leap.update(0.4, Vector3(0.0, -5.0, 0.0), toward, 3.5, true, 22.0)
	var again: Vector3 = leap.update(1.0 / 60.0, Vector3.ZERO, toward, 3.5, true, 22.0)
	# Arco balistico: vh = d/t alcaca o alvo; vy = g*t/2 devolve ao chao.
	var expected_x: float = 3.5 / ABILITIES_SCRIPT.LEAP_AIRTIME
	var expected_y: float = 0.5 * 22.0 * ABILITIES_SCRIPT.LEAP_AIRTIME
	if far != Vector3.ZERO or not mid_air or landed != Vector3.ZERO or again != Vector3.ZERO:
		_fail(test_root, "Leaper: sem bote longe, aterrissa e respeita recarga; longe=%s no_ar=%s pousou=%s repetido=%s." % [far, mid_air, landed, again])
		return
	if absf(lunge.x - expected_x) > 0.01 or absf(lunge.y - expected_y) > 0.01 or absf(aloft.x - expected_x) > 0.01 or absf(aloft.y + 2.0) > 0.01:
		_fail(test_root, "Leaper balistico: bote=(%s, %s) esperado=(%s, %s) e o voo=(%s) preserva o impulso sem travar no ar." % [lunge.x, lunge.y, expected_x, expected_y, aloft])
		return
	print("PASS: Leaper da bote balistico no alvo e respeita a recarga.")


func _test_late_waves_mix_new_variants(test_root: Node) -> void:
	print("Testando variantes novas no mix das ondas...")
	var schedule = SCHEDULE_SCRIPT.new()
	var early: Dictionary = schedule.variant_mix_for_wave(0)
	var late: Dictionary = schedule.variant_mix_for_wave(7)
	var endgame: Dictionary = schedule.variant_mix_for_wave(12)
	# Bloater e leaper entram desde a hora 1 (especiais estilo L4D); armored segue tardio.
	var early_clean := not early.has(ZombieMutator.Type.ARMORED)
	var late_ok := int(late.get(ZombieMutator.Type.BLOATER, 0)) > 0 and int(late.get(ZombieMutator.Type.LEAPER, 0)) > 0
	var endgame_ok := int(endgame.get(ZombieMutator.Type.ARMORED, 0)) > 0 and int(endgame.get(ZombieMutator.Type.BLOATER, 0)) > 0
	if not early_clean or not late_ok or not endgame_ok:
		_fail(test_root, "Mix: inicio sem armored, hora 7+ com bloater e leaper, hora 11+ com armored; inicio=%s tarde=%s final=%s." % [early, late, endgame])
		return
	print("PASS: Ondas altas misturam bloater, leaper e armored.")


func _add_zombie(test_root: Node, zombie_name: String, variant: int, position: Vector3) -> CharacterBody3D:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = zombie_name
	zombie.set("forced_variant", variant)
	zombie.position = position
	test_root.add_child(zombie)
	return zombie


func _add_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.position = position
	test_root.add_child(player)
	return player


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
