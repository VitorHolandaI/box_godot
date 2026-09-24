# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da viabilidade por lote: o arquetipo deixa de ser sorteado por
## hash e passa a ser escolhido por peso, pontuando area, quantos lados do lote
## dão para a rua, declive e distrito (Scharl et al., CESCG 2010, e o
## ZoneSpawnSystem do Cities Skylines 2 - pesquisa em
## procedures/geracao-de-plantas-pesquisa.md).
## Uso: await LotFeasibilityTests.new().run(test_root)

const FEASIBILITY_SCRIPT := preload("res://scripts/procedural/generators/lot_feasibility.gd")
const CITY_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/city_generator.gd")
const ROAD_BLUEPRINT_SCRIPT := preload("res://scripts/procedural/blueprints/road_blueprint.gd")
const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")


func run(test_root: Node) -> void:
	_test_street_facing_sides(test_root)
	_test_steep_slope_has_no_building(test_root)
	_test_lot_without_street_has_no_commerce(test_root)
	_test_suburban_has_no_apartment(test_root)
	_test_gun_shop_requires_urban_street(test_root)
	_test_commercial_variants_have_distinct_details(test_root)
	_test_survival_biases_toward_houses(test_root)
	_test_choice_is_deterministic_and_varied(test_root)
	_test_city_lots_all_get_a_building(test_root)


## Lote de esquina em rua isolada: so a lateral vizinha da rua conta.
func _test_street_facing_sides(test_root: Node) -> void:
	print("Testando lados do lote voltados para a rua...")
	var road_x: Array = [ROAD_BLUEPRINT_SCRIPT.new("local", Vector2(-24.0, -96.0), Vector2(-24.0, 96.0), 7.0)]
	var facing := FEASIBILITY_SCRIPT.street_facing_sides(Vector2(-10.5, 0.0), Vector2(19.0, 19.0), road_x)
	var isolated := FEASIBILITY_SCRIPT.street_facing_sides(Vector2(0.0, 0.0), Vector2(19.0, 19.0), road_x)
	var no_roads := FEASIBILITY_SCRIPT.street_facing_sides(Vector2(-10.5, 0.0), Vector2(19.0, 19.0), [])
	var corner_roads: Array = [
		ROAD_BLUEPRINT_SCRIPT.new("local", Vector2(-24.0, -96.0), Vector2(-24.0, 96.0), 7.0),
		ROAD_BLUEPRINT_SCRIPT.new("collector", Vector2(-96.0, -24.0), Vector2(96.0, -24.0), 6.0),
	]
	var corner := FEASIBILITY_SCRIPT.street_facing_sides(Vector2(-10.5, -10.5), Vector2(19.0, 19.0), corner_roads)
	if facing != 1 or isolated != 0 or no_roads != 0 or corner != 2:
		_fail(test_root, "Lados de rua: vizinha=%d isolado=%d sem_rua=%d esquina=%d; esperado 1/0/0/2." % [facing, isolated, no_roads, corner])
		return
	print("PASS: Lote de esquina conta 2 lados, vizinho de uma rua conta 1 e isolado conta 0.")


## Declive acima do limite nao recebe construcao de arquetipo nenhum.
func _test_steep_slope_has_no_building(test_root: Node) -> void:
	print("Testando lote em declive forte sem construcao...")
	var steep := _features({"slope": FEASIBILITY_SCRIPT.MAX_BUILDABLE_SLOPE + 0.2})
	var weights := FEASIBILITY_SCRIPT.archetype_weights(steep)
	var chosen := FEASIBILITY_SCRIPT.choose_archetype(steep, _rng(1))
	var all_zero := true
	for archetype in FEASIBILITY_SCRIPT.ARCHETYPES:
		if float(weights[archetype]) > 0.0:
			all_zero = false
	var flat := FEASIBILITY_SCRIPT.choose_archetype(_features({"slope": FEASIBILITY_SCRIPT.MAX_BUILDABLE_SLOPE - 0.01}), _rng(1))
	if not all_zero or not chosen.is_empty() or flat.is_empty():
		_fail(test_root, "Declive: pesos_zerados=%s escolhido='%s' plano='%s'; esperado tudo zero, vazio no declive e nao-vazio no plano." % [all_zero, chosen, flat])
		return
	print("PASS: Lote acima de %.2f de declive fica sem edificio." % FEASIBILITY_SCRIPT.MAX_BUILDABLE_SLOPE)


## Sem frente para rua nao cabe comercio: so casa ou nada.
func _test_lot_without_street_has_no_commerce(test_root: Node) -> void:
	print("Testando lote sem rua sem loja nem mercado...")
	var weights := FEASIBILITY_SCRIPT.archetype_weights(_features({"street_sides": 0}))
	if float(weights["house"]) <= 0.0 or float(weights["store"]) != 0.0 or float(weights["grocery"]) != 0.0 or float(weights["gun_shop"]) != 0.0 or float(weights["apartment"]) != 0.0:
		_fail(test_root, "Sem rua: casa=%.2f loja=%.2f mercado=%.2f armas=%.2f predio=%.2f; esperado casa>0 e o resto 0." % [weights["house"], weights["store"], weights["grocery"], weights["gun_shop"], weights["apartment"]])
		return
	print("PASS: Lote longe da rua so comporta casa.")


## Apartamento e coisa de zona urbana: subúrbio nao pontua predio.
func _test_suburban_has_no_apartment(test_root: Node) -> void:
	print("Testando subúrbio sem apartamento na pontuacao...")
	var weights := FEASIBILITY_SCRIPT.archetype_weights(_features({"district": "suburban"}))
	if float(weights["apartment"]) != 0.0 or float(weights["house"]) <= 0.0:
		_fail(test_root, "Subúrbio: predio=%.2f casa=%.2f; esperado predio 0 e casa>0." % [weights["apartment"], weights["house"]])
		return
	print("PASS: Subúrbio nao pontua apartamento.")


## Loja de armas precisa de zona urbana e frente para rua; assim nao aparece
## no miolo residencial. Uso: interno do run.
func _test_gun_shop_requires_urban_street(test_root: Node) -> void:
	print("Testando requisitos da loja de armas...")
	var urban := FEASIBILITY_SCRIPT.archetype_weights(_features())
	var suburban := FEASIBILITY_SCRIPT.archetype_weights(_features({"district": "suburban"}))
	var no_street := FEASIBILITY_SCRIPT.archetype_weights(_features({"street_sides": 0}))
	if float(urban["gun_shop"]) <= 0.0 or float(suburban["gun_shop"]) != 0.0 or float(no_street["gun_shop"]) != 0.0:
		_fail(test_root, "Loja de armas: urbana=%.2f suburbio=%.2f sem_rua=%.2f; esperado >0/0/0." % [urban["gun_shop"], suburban["gun_shop"], no_street["gun_shop"]])
		return
	print("PASS: Loja de armas so pontua em lote urbano com frente de rua.")


## Cada comercio precisa de fachada e interior identificaveis sem compartilhar
## apenas o mesmo caixa generico. Uso: interno do run.
func _test_commercial_variants_have_distinct_details(test_root: Node) -> void:
	print("Testando detalhes distintos dos comercios...")
	var variants: Array[Array] = [
		["store", "Shop_A", "StoreCheckout"],
		["grocery", "Grocery_A", "GroceryAisle"],
		["gun_shop", "GunShop_A", "GunShopDisplayRack"],
	]
	for variant in variants:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(18273, variant[0])
		var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
		var valid: bool = String(blueprint.archetype) == String(variant[1]) and not building.find_children(String(variant[2]) + "*", "MeshInstance3D", true, false).is_empty()
		building.free()
		if not valid:
			_fail(test_root, "Comercio '%s' deveria gerar '%s' com detalhe '%s'." % variant)
			return
	print("PASS: Loja, mercado e loja de armas possuem detalhes distintos.")


## O modo sobrevivencia empurra o mapa para casas e corta a densidade.
func _test_survival_biases_toward_houses(test_root: Node) -> void:
	print("Testando sobrevivencia puxando o mapa para casas...")
	var normal := FEASIBILITY_SCRIPT.archetype_weights(_features())
	var survival := FEASIBILITY_SCRIPT.archetype_weights(_features({"survival": true}))
	if float(survival["house"]) < float(normal["house"]) or float(survival["apartment"]) >= float(normal["apartment"]):
		_fail(test_root, "Sobrevivencia: casa %.2f->%.2f predio %.2f->%.2f; esperado casa subir e predio cair." % [normal["house"], survival["house"], normal["apartment"], survival["apartment"]])
		return
	print("PASS: Sobrevivencia aumenta casas e reduz apartamentos.")


## Mesma caracteristica e mesma seed dao o mesmo arquetipo, mas o conjunto varia.
func _test_choice_is_deterministic_and_varied(test_root: Node) -> void:
	print("Testando escolha deterministica e variada...")
	var features := _features()
	var first := FEASIBILITY_SCRIPT.choose_archetype(features, _rng(7))
	var again := FEASIBILITY_SCRIPT.choose_archetype(features, _rng(7))
	var seen := {}
	for pick_seed in range(64):
		var archetype := FEASIBILITY_SCRIPT.choose_archetype(features, _rng(pick_seed))
		if not FEASIBILITY_SCRIPT.ARCHETYPES.has(archetype):
			_fail(test_root, "Escolha devolveu '%s', fora de %s." % [archetype, FEASIBILITY_SCRIPT.ARCHETYPES])
			return
		seen[archetype] = true
	if first != again or seen.size() < 2:
		_fail(test_root, "Escolha: deterministico=%s (primeiro=%s de novo=%s) variedade=%d; esperado deterministico e >=2 arquetipos." % [first == again, first, again, seen.size()])
		return
	print("PASS: Escolha repetivel por seed e com %d arquetipos diferentes na mesma caracteristica." % seen.size())


## Integracao: a cidade inteira usa a pontuacao e so o lote reservado fica vazio.
func _test_city_lots_all_get_a_building(test_root: Node) -> void:
	print("Testando cidade pontuada com lote reservado vazio...")
	var city = CITY_GENERATOR_SCRIPT.generate_world(4242)
	var empty := 0
	for block in city.blocks:
		for lot in block.lots:
			if lot.building == null:
				empty += 1
				continue
			var archetype: String = lot.building.archetype
			if not archetype.begins_with("House") and not archetype.begins_with("Shop") and not archetype.begins_with("Grocery") and not archetype.begins_with("GunShop") and not archetype.begins_with("ApartmentBuilding"):
				_fail(test_root, "Lote %s gerou arquetipo inesperado '%s'." % [lot.id, archetype])
				return
	if empty != 1:
		_fail(test_root, "Cidade deveria ter so o lote reservado vazio (1), mas tem %d." % empty)
		return
	print("PASS: Cidade pontuada, 1 lote reservado vazio e arquetipos validos.")


func _features(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"area": 361.0,
		"street_sides": 2,
		"slope": 0.0,
		"district": "urban",
		"survival": false,
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _rng(pick_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = pick_seed
	return rng


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
