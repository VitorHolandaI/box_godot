extends RefCounted

## Regressoes da municao por classe: zumbi abatido solta de vez em quando
## municao de qualquer classe, reposicao periodica ate o minimo por classe e item com cor e
## etiqueta da classe (antes toda caixa de municao parecia igual).
## Uso: AmmoLootTests.new().run(test_root)

const DIRECTOR_SCRIPT := preload("res://scripts/ammo_loot_director.gd")


func run(test_root: Node) -> void:
	_test_kill_drop_is_rare_and_any_class(test_root)
	_test_restock_fills_each_class_to_minimum(test_root)
	_test_restock_waits_for_interval(test_root)
	_test_class_ammo_has_distinct_label(test_root)


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


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
