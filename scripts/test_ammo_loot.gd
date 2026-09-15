extends RefCounted

## Regressoes da municao por classe: zumbi abatido solta de vez em quando
## municao de qualquer classe, reposicao periodica ate o minimo por classe e item com cor e
## etiqueta da classe (antes toda caixa de municao parecia igual).
## Uso: AmmoLootTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DIRECTOR_SCRIPT := preload("res://scripts/ammo_loot_director.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")


func run(test_root: Node) -> void:
	_test_kill_drop_is_rare_and_any_class(test_root)
	_test_restock_fills_each_class_to_minimum(test_root)
	_test_restock_waits_for_interval(test_root)
	_test_class_ammo_has_distinct_label(test_root)
	_test_class_ammo_always_counts(test_root)
	_test_zombie_weapon_drop_is_rare_and_worn(test_root)
	_test_zombie_weapon_drops_are_capped(test_root)


func _test_kill_drop_is_rare_and_any_class(test_root: Node) -> void:
	print("Testando queda ocasional de municao de qualquer classe...")
	var drops: Dictionary = {}
	var dropped := 0
	var samples := 1000
	for index in samples:
		var roll := (float(index) + 0.5) / float(samples)
		var pick := fmod(float(index) * 0.618034, 1.0)
		var supply_kind := DIRECTOR_SCRIPT.drop_kind_for_kill(roll, pick)
		if supply_kind < 0:
			continue
		dropped += 1
		drops[supply_kind] = true
	var drop_rate := float(dropped) / float(samples)
	var all_kinds := drops.size() == DIRECTOR_SCRIPT.RESTOCKED_KINDS.size()
	var smaller := DIRECTOR_SCRIPT.drop_amount_for(GroundSupplyPickup.Kind.AMMO_UZI) < DIRECTOR_SCRIPT.amount_for(GroundSupplyPickup.Kind.AMMO_UZI)
	if absf(drop_rate - DIRECTOR_SCRIPT.KILL_DROP_CHANCE) > 0.01 or not all_kinds or not smaller:
		_fail(test_root, "Queda deveria ser rara (%.0f%%), de qualquer classe e com meia carga; taxa=%.3f classes=%d/%d menor=%s." % [DIRECTOR_SCRIPT.KILL_DROP_CHANCE * 100.0, drop_rate, drops.size(), DIRECTOR_SCRIPT.RESTOCKED_KINDS.size(), smaller])
		return
	print("PASS: Zumbi solta municao de qualquer classe em %.0f%% das mortes, com meia carga." % (drop_rate * 100.0))


func _test_restock_fills_each_class_to_minimum(test_root: Node) -> void:
	print("Testando reposicao de municao por classe...")
	var counts := {GroundSupplyPickup.Kind.AMMO_UZI: DIRECTOR_SCRIPT.MIN_ITEMS_PER_CLASS + 2, GroundSupplyPickup.Kind.AMMO_SHOTGUN: 1}
	var kinds: Array[int] = DIRECTOR_SCRIPT.kinds_to_restock(counts)
	var shotgun := kinds.count(GroundSupplyPickup.Kind.AMMO_SHOTGUN)
	var uzi := kinds.count(GroundSupplyPickup.Kind.AMMO_UZI)
	var carbine := kinds.count(GroundSupplyPickup.Kind.AMMO_CARBINE)
	var pistol := kinds.count(GroundSupplyPickup.Kind.AMMO)
	var minimum: int = DIRECTOR_SCRIPT.MIN_ITEMS_PER_CLASS
	if shotgun != minimum - 1 or uzi != 0 or carbine != minimum or pistol != minimum or kinds.has(GroundSupplyPickup.Kind.HEALTH):
		_fail(test_root, "Reposicao deveria completar ate %d por classe (inclusive pistola); escopeta=%d uzi=%d carabina=%d pistola=%d lista=%s." % [minimum, shotgun, uzi, carbine, pistol, kinds])
		return
	print("PASS: Reposicao completa cada classe ate %d itens no mapa." % minimum)


func _test_restock_waits_for_interval(test_root: Node) -> void:
	print("Testando intervalo da reposicao de municao...")
	var director = DIRECTOR_SCRIPT.new()
	var first: bool = director.is_restock_due(1.0)
	var early: bool = director.is_restock_due(DIRECTOR_SCRIPT.RESTOCK_INTERVAL * 0.5)
	var due: bool = director.is_restock_due(DIRECTOR_SCRIPT.RESTOCK_INTERVAL * 0.5)
	if not first or early or not due:
		_fail(test_root, "Reposicao: primeira na hora, depois a cada %.0f s; primeira=%s cedo=%s na_hora=%s." % [DIRECTOR_SCRIPT.RESTOCK_INTERVAL, first, early, due])
		return
	print("PASS: Reposicao roda logo ao comecar e depois a cada %.0f s." % DIRECTOR_SCRIPT.RESTOCK_INTERVAL)


func _test_class_ammo_has_distinct_label(test_root: Node) -> void:
	print("Testando cor e etiqueta da municao por classe...")
	var labels: Dictionary = {}
	var colors: Dictionary = {}
	for kind in GroundSupplyPickup.KIND_TO_WEAPON:
		var item := GroundSupplyPickup.new()
		item.setup(int(kind), 10)
		test_root.add_child(item)
		var label := item.find_child("ClassLabel", true, false) as Label3D
		labels[label.text if label != null else ""] = true
		colors[GroundSupplyPickup.color_for(int(kind))] = true
		item.free()
	var expected := GroundSupplyPickup.KIND_TO_WEAPON.size()
	if labels.size() != expected or labels.has("") or colors.size() != expected:
		_fail(test_root, "Cada classe deveria ter etiqueta e cor proprias; etiquetas=%s cores=%d esperado=%d." % [labels.keys(), colors.size(), expected])
		return
	print("PASS: Municao de cada classe tem etiqueta e cor proprias.")


func _test_class_ammo_always_counts(test_root: Node) -> void:
	print("Testando municao de classe contando com ou sem a arma...")
	var without_weapon := PLAYER_SCENE.instantiate() as CharacterBody3D
	without_weapon.set("reads_local_input", false)
	without_weapon.set("is_local_controller", false)
	test_root.add_child(without_weapon)
	without_weapon.set("reserve_ammo", 0)
	var foreign := _add_supply(test_root, GroundSupplyPickup.Kind.AMMO_SHOTGUN, 12)
	foreign.call("_on_body_entered", without_weapon)
	var pistol_reserve := int(without_weapon.get("reserve_ammo"))
	var foreign_taken := foreign.is_queued_for_deletion()
	var with_weapon := PLAYER_SCENE.instantiate() as CharacterBody3D
	with_weapon.set("reads_local_input", false)
	with_weapon.set("is_local_controller", false)
	test_root.add_child(with_weapon)
	with_weapon.call("take_crate_weapon", WeaponStats.Kind.SHOTGUN)
	var slots: WeaponSlots = with_weapon.get("weapon_slots")
	slots.state_of(WeaponStats.Kind.SHOTGUN)["reserve"] = 0
	var own := _add_supply(test_root, GroundSupplyPickup.Kind.AMMO_SHOTGUN, 12)
	own.call("_on_body_entered", with_weapon)
	var shotgun_reserve := int(slots.state_of(WeaponStats.Kind.SHOTGUN).get("reserve", 0))
	for node in [without_weapon, with_weapon, foreign, own]:
		node.free()
	if pistol_reserve != GroundSupplyPickup.PISTOL_ROUNDS_FROM_FOREIGN_CLASS or not foreign_taken or shotgun_reserve != 12:
		_fail(test_root, "Sem a arma vira %d balas de pistola; com a arma vai para a reserva dela; pistola=%d coletado=%s escopeta=%d." % [GroundSupplyPickup.PISTOL_ROUNDS_FROM_FOREIGN_CLASS, pistol_reserve, foreign_taken, shotgun_reserve])
		return
	print("PASS: Municao do chao sempre conta (sem a arma vira bala de pistola).")


func _test_zombie_weapon_drop_is_rare_and_worn(test_root: Node) -> void:
	print("Testando arma solta por zumbi (rara, usada)...")
	var samples := 2000
	var dropped := 0
	var kinds: Dictionary = {}
	var worn_ok := true
	for index in samples:
		var roll := (float(index) + 0.5) / float(samples)
		var weapon := DIRECTOR_SCRIPT.weapon_drop_for_kill(roll, fmod(float(index) * 0.618034, 1.0), fmod(float(index) * 0.414214, 1.0))
		if weapon.is_empty():
			continue
		dropped += 1
		kinds[int(weapon["kind"])] = true
		var stats := WeaponStats.stats_for(int(weapon["kind"]))
		var durability := int(weapon["durability"])
		worn_ok = worn_ok and durability < int(stats["max_durability"]) and durability >= 1 and int(weapon["reserve"]) < int(stats["grant_reserve"]) and int(weapon["mag"]) == int(stats["mag_size"])
	var rate := float(dropped) / float(samples)
	if absf(rate - DIRECTOR_SCRIPT.WEAPON_DROP_CHANCE) > 0.01 or kinds.size() != DIRECTOR_SCRIPT.DROPPABLE_WEAPONS.size() or not worn_ok:
		_fail(test_root, "Arma de zumbi: %.0f%% das mortes, todas as classes, pente cheio e desgastada; taxa=%.3f classes=%d usada=%s." % [DIRECTOR_SCRIPT.WEAPON_DROP_CHANCE * 100.0, rate, kinds.size(), worn_ok])
		return
	if DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS <= 0 or DIRECTOR_SCRIPT.ZOMBIE_WEAPON_LIFETIME > 120.0:
		_fail(test_root, "Drop frequente precisa de limite e vida curta no chao; limite=%d vida=%.0f." % [DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS, DIRECTOR_SCRIPT.ZOMBIE_WEAPON_LIFETIME])
		return
	print("PASS: Zumbi solta arma usada em %.1f%% das mortes." % (rate * 100.0))


func _test_zombie_weapon_drops_are_capped(test_root: Node) -> void:
	print("Testando limite de armas soltas por zumbis no chao...")
	var main = MAIN_SCRIPT.new()
	var pickups: Array[GroundWeaponPickup] = []
	for index in DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS + 5:
		var pickup := GroundWeaponPickup.new()
		pickups.append(pickup)
		main.call("_track_zombie_weapon_drop", pickup)
	var tracked: int = (main.get("zombie_weapon_drops") as Array).size()
	var oldest_removed := pickups[0].is_queued_for_deletion() and pickups[4].is_queued_for_deletion()
	var newest_kept := not pickups[pickups.size() - 1].is_queued_for_deletion()
	var short_life := is_equal_approx(pickups[pickups.size() - 1].lifetime_seconds, DIRECTOR_SCRIPT.ZOMBIE_WEAPON_LIFETIME)
	for pickup in pickups:
		pickup.free()
	main.free()
	if tracked != DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS or not oldest_removed or not newest_kept or not short_life:
		_fail(test_root, "Limite de %d armas de zumbi: rastreadas=%d antigas_removidas=%s nova_mantida=%s vida_curta=%s." % [DIRECTOR_SCRIPT.MAX_ZOMBIE_WEAPON_DROPS, tracked, oldest_removed, newest_kept, short_life])
		return
	print("PASS: So as %d armas de zumbi mais novas ficam no chao." % tracked)


func _add_supply(test_root: Node, kind: int, amount: int) -> GroundSupplyPickup:
	var item := GroundSupplyPickup.new()
	item.setup(kind, amount)
	test_root.add_child(item)
	return item


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
