extends RefCounted

## Regressoes do layout de comercio procedural: a entrada varia de posicao por
## seed, estoque/escritorio trocam de lado e os moveis respeitam a zona de
## descompressao, o caixa e o ATM. Baseado nos principios de varejo de
## procedures/lojas-layout-pesquisa.md.
## Uso: await CommercialLayoutTests.new().run(test_root)

const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const ROOM_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/room_generator.gd")
const COMMERCIAL_ARCHETYPES: Array[String] = ["store", "grocery", "gun_shop"]
const SEEDS: Array[int] = [18273, 4242, 777, 99120, 240912]


func run(test_root: Node) -> void:
	_test_store_entrance_varies_by_seed(test_root)
	_test_store_rooms_vary_by_seed(test_root)
	_test_commercial_has_atm_off_entrance_side(test_root)
	_test_commercial_fixtures_avoid_doorways(test_root)
	_test_grocery_has_aisles(test_root)


## A porta nao pode ficar sempre no centro: a posicao da entrada muda por seed.
func _test_store_entrance_varies_by_seed(test_root: Node) -> void:
	print("Testando variacao da posicao da entrada das lojas...")
	var entrances := {}
	for building_seed in SEEDS:
		var layout: Dictionary = ROOM_GENERATOR_SCRIPT.store_layout_for_seed(building_seed, 18.0, 14.0)
		entrances[snappedf(float(layout["entrance_x"]), 0.1)] = true
	if entrances.size() < 2:
		_fail(test_root, "Entrada das lojas nao variou: %d posicao(oes) para %d seeds." % [entrances.size(), SEEDS.size()])
		return
	print("PASS: Entradas de loja em %d posicoes diferentes." % entrances.size())


## Estoque e escritorio trocam de lado e a profundidade dos fundos varia.
func _test_store_rooms_vary_by_seed(test_root: Node) -> void:
	print("Testando variacao de comodos das lojas...")
	var signatures := {}
	for building_seed in SEEDS:
		var layout: Dictionary = ROOM_GENERATOR_SCRIPT.store_layout_for_seed(building_seed, 18.0, 14.0)
		signatures["%s:%.1f" % [layout["office_on_left"], float(layout["sales_depth"])]] = true
	if signatures.size() < 2:
		_fail(test_root, "Comodos de loja nao variaram: %d assinatura(s) para %d seeds." % [signatures.size(), SEEDS.size()])
		return
	print("PASS: %d arranjos de estoque/escritorio diferentes." % signatures.size())


## O ATM existe e fica na parede oposta a entrada, perto da porta.
func _test_commercial_has_atm_off_entrance_side(test_root: Node) -> void:
	print("Testando ATM na parede oposta a entrada...")
	for building_seed in SEEDS:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, "store")
		var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
		var atm := building.get_node_or_null("AtmMachine") as Node3D
		var entrance_x := float(blueprint.metadata["store_layout"]["entrance_x"])
		var valid: bool = atm != null and absf(atm.position.x - entrance_x) > blueprint.width * 0.3
		building.free()
		if not valid:
			_fail(test_root, "Seed %d: ATM deveria existir longe da entrada (x=%.1f)." % [building_seed, entrance_x])
			return
	print("PASS: ATM presente e afastado da entrada em todas as seeds.")


## Nenhum movel de comercio pode cobrir um vao de porta.
func _test_commercial_fixtures_avoid_doorways(test_root: Node) -> void:
	print("Testando moveis de comercio livres dos vaos de porta...")
	for archetype in COMMERCIAL_ARCHETYPES:
		for building_seed in SEEDS:
			var blueprint = BUILDING_GENERATOR_SCRIPT.generate(building_seed, archetype)
			var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
			var problem := _doorway_overlap(building)
			building.free()
			if not problem.is_empty():
				_fail(test_root, "%s seed %d: %s" % [archetype, building_seed, problem])
				return
	print("PASS: Nenhum movel de loja, mercado ou loja de armas cobre vao.")


## Primeiro movel que cobre um vao ("" quando esta tudo livre). Uso: interno.
func _doorway_overlap(building: StaticBody3D) -> String:
	for door_node in building.find_children("Door_*", "AnimatableBody3D", true, false):
		var door := door_node as AnimatableBody3D
		var panel := door.get_node_or_null("DoorPanel") as MeshInstance3D
		if panel == null:
			continue
		var panel_box := panel.mesh as BoxMesh
		var doorway_center: Vector3 = door.position + panel.position
		var doorway_size := Vector3(panel_box.size.x * 0.7, panel_box.size.y * 0.7, panel_box.size.z * 0.7)
		for node in building.find_children("*", "MeshInstance3D", true, false):
			var fixture := node as MeshInstance3D
			if fixture == panel or String(fixture.name).begins_with("Door"):
				continue
			var fixture_box := fixture.mesh as BoxMesh
			if fixture_box == null:
				continue
			var half := (fixture_box.size + doorway_size) * 0.5
			var offset := fixture.position - doorway_center
			if absf(offset.x) < half.x and absf(offset.y) < half.y and absf(offset.z) < half.z:
				return "movel '%s' cobre o vao %s." % [fixture.name, door.name]
	return ""


## Mercado precisa de corredores (gondolas) de verdade, nao so o caixa.
func _test_grocery_has_aisles(test_root: Node) -> void:
	print("Testando corredores do mercado...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(18273, "grocery")
	var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var aisles := building.find_children("GroceryAisle*", "MeshInstance3D", true, false).size()
	building.free()
	if aisles < 3:
		_fail(test_root, "Mercado deveria ter ao menos 3 corredores; tem %d." % aisles)
		return
	print("PASS: Mercado com %d corredores de gondola." % aisles)


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
