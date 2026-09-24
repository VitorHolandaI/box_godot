# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do minimapa: seta de direcao do jogador (item 8) e desenho do
## mapa gerado no fundo (item 9).
## Uso: MinimapTests.new().run(test_root)

const SPLIT_SCREEN_MANAGER: GDScript = preload("res://scripts/split_screen_manager.gd")
const CITY_GENERATOR_SCRIPT: GDScript = preload("res://scripts/city_generator.gd")
const PROCEDURAL_CITY_GENERATOR: GDScript = preload("res://scripts/procedural/generators/city_generator.gd")
const WORLD_SEED := 240912
## MAP_HALF_EXTENT e 96; o minimapa cobre +-160. Margem para o jitter/bend.
const MAX_LAYOUT_RADIUS := 110.0


func run(test_root: Node) -> void:
	_test_facing_to_minimap(test_root)
	_test_city_layout_has_roads_and_buildings(test_root)
	_test_rotated_lots_swap_minimap_footprint(test_root)


## A seta segue o forward (-Z) do Node3D projetado no plano (x, z) do minimapa.
func _test_facing_to_minimap(test_root: Node) -> void:
	print("Testando a direcao da seta do jogador no minimapa...")
	var minimap_view: GDScript = SPLIT_SCREEN_MANAGER.MinimapView
	var north: Vector2 = minimap_view.facing_to_minimap(Basis.IDENTITY)
	var west: Vector2 = minimap_view.facing_to_minimap(Basis(Vector3.UP, PI * 0.5))
	var east: Vector2 = minimap_view.facing_to_minimap(Basis(Vector3.UP, -PI * 0.5))
	if north.distance_to(Vector2(0.0, -1.0)) > 0.01 \
			or west.distance_to(Vector2(-1.0, 0.0)) > 0.01 \
			or east.distance_to(Vector2(1.0, 0.0)) > 0.01:
		_fail(test_root, "Seta deveria apontar norte/oeste/leste; veio %s/%s/%s." % [north, west, east])
		return
	print("PASS: Seta do jogador aponta para o forward do boneco.")


## O layout tem uma pegada por predio e ruas com largura, tudo no alcance do mapa.
func _test_city_layout_has_roads_and_buildings(test_root: Node) -> void:
	print("Testando o mapa gerado (ruas e predios) para o minimapa...")
	var city = PROCEDURAL_CITY_GENERATOR.generate_world(WORLD_SEED)
	var layout: Dictionary = CITY_GENERATOR_SCRIPT.build_minimap_layout(city)
	var roads: Array = layout.get("roads", [])
	var buildings: Array = layout.get("buildings", [])
	var expected: int = city.building_count()
	if roads.is_empty() or expected == 0 or buildings.size() != expected:
		_fail(test_root, "Layout deveria ter ruas e %d predios; veio %d ruas e %d predios." % [expected, roads.size(), buildings.size()])
		return
	for building in buildings:
		var center: Vector2 = building["center"]
		var size: Vector2 = building["size"]
		if size.x <= 0.0 or size.y <= 0.0 or center.length() > MAX_LAYOUT_RADIUS:
			_fail(test_root, "Predio fora do alcance ou sem tamanho: centro=%s tamanho=%s." % [center, size])
			return
	for road in roads:
		if float(road["width"]) <= 0.0 or (road["start"] as Vector2).distance_to(road["finish"] as Vector2) <= 0.0:
			_fail(test_root, "Rua sem largura ou comprimento: %s." % [road])
			return
	print("PASS: Mapa gerado tem %d ruas e %d predios dentro do alcance." % [roads.size(), buildings.size()])


## Regressao: predio girado 90 graus tinha a pegada desenhada com largura e
## profundidade invertidas no minimapa, cobrindo a rua que ele encara. A pegada
## esperada e recalculada aqui de forma independente (troca em yaw de 90 graus)
## para o teste nao herdar o mesmo bug do codigo de producao.
func _test_rotated_lots_swap_minimap_footprint(test_root: Node) -> void:
	print("Testando pegada de predio rotacionado no minimapa...")
	var city = PROCEDURAL_CITY_GENERATOR.generate_world(WORLD_SEED)
	var layout: Dictionary = CITY_GENERATOR_SCRIPT.build_minimap_layout(city)
	var buildings: Array = layout.get("buildings", [])
	var index := 0
	var rotated_lots := 0
	for block in city.blocks:
		for lot in block.lots:
			if lot.building == null:
				continue
			if index >= buildings.size():
				_fail(test_root, "Minimapa tem menos predios que a cidade no indice %d." % index)
				return
			var expected := Vector2(lot.building.width, lot.building.depth)
			if absf(sin(lot.building_rotation_y)) > 0.5:
				expected = Vector2(lot.building.depth, lot.building.width)
				rotated_lots += 1
			var size: Vector2 = buildings[index]["size"]
			if size.distance_to(expected) > 0.001:
				_fail(test_root, "Pegada do lote %s ignorou rotacao %.2f: minimapa=%s esperado=%s." % [lot.id, lot.building_rotation_y, size, expected])
				return
			index += 1
	if index != buildings.size():
		_fail(test_root, "Minimapa tem %d predios, cidade percorreu %d." % [buildings.size(), index])
		return
	if rotated_lots == 0:
		_fail(test_root, "Teste precisa de ao menos um lote girado para valer.")
		return
	print("PASS: Pegada do minimapa respeita a rotacao em %d lotes girados." % rotated_lots)


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
