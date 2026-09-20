extends RefCounted

## Regressoes de escala dos postes e do telhado realista das casas.
## Uso: CityPropsTests.new().run(test_root)

const CITY_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/city_generator.gd")
const BUILDING_GENERATOR_SCRIPT := preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const ROOF_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/house_roof_assembler.gd")
const STREET_LIGHT_ASSEMBLER_SCRIPT := preload("res://scripts/procedural/assemblers/street_light_assembler.gd")
const MESH_BATCHER_SCRIPT := preload("res://scripts/procedural/assemblers/mesh_batcher.gd")
const PLAYER_HEIGHT := 2.34


func run(test_root: Node) -> void:
	_test_street_lights_tower_over_player_on_sidewalks(test_root)
	_test_house_roof_is_closed_and_pitched(test_root)
	_test_house_rooms_fit_player_size(test_root)
	_test_building_meshes_merge_without_touching_doors(test_root)
	_test_enterable_buildings_have_interior_loot_anchors(test_root)


func _test_street_lights_tower_over_player_on_sidewalks(test_root: Node) -> void:
	print("Testando postes altos nas calcadas das ruas procedurais...")
	var city = CITY_GENERATOR_SCRIPT.generate_world(240912, true)
	var parent := Node3D.new()
	var count: int = STREET_LIGHT_ASSEMBLER_SCRIPT.assemble(city, parent)
	var lights := parent.get_children()
	if count < 20 or lights.size() != count:
		_fail(test_root, "Cidade deveria ter ao menos 20 postes; criados=%d nos=%d." % [count, lights.size()])
		parent.free()
		return
	var model_height := 0.96
	var light_height := (lights[0] as Node3D).scale.y * model_height
	if light_height < PLAYER_HEIGHT * 2.0:
		_fail(test_root, "Poste com %.2f m deveria ter ao menos o dobro da altura do jogador (%.2f m)." % [light_height, PLAYER_HEIGHT])
		parent.free()
		return
	for light_node in lights:
		var light := light_node as Node3D
		var point := Vector2(light.position.x, light.position.z)
		for road in city.roads:
			var closest := Geometry2D.get_closest_point_to_segment(point, road.start, road.finish)
			if closest.distance_to(point) < road.width * 0.5:
				_fail(test_root, "Poste em %s esta sobre o asfalto da rua %s." % [point, road.signature()])
				parent.free()
				return
		for block in city.blocks:
			for lot in block.lots:
				if lot.building == null:
					continue
				var size := Vector2(lot.building.width, lot.building.depth)
				if Rect2(lot.position - size * 0.5, size).has_point(point):
					_fail(test_root, "Poste em %s caiu dentro do lote %s." % [point, lot.id])
					parent.free()
					return
	parent.free()
	print("PASS: %d postes com %.1f m nas calcadas, fora de lotes e do asfalto." % [count, light_height])


func _test_house_roof_is_closed_and_pitched(test_root: Node) -> void:
	print("Testando telhado de casa com empenas fechadas e caimento real...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var gables := house.find_children("RoofGable*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool: return (node as MeshInstance3D).mesh is PrismMesh)
	var left_slope := house.get_node_or_null("RoofLeftSlope") as MeshInstance3D
	var has_ridge := house.has_node("RoofRidge")
	var pitch := rad_to_deg(absf(left_slope.rotation.z)) if left_slope != null else 0.0
	house.free()
	if gables.size() != 2:
		_fail(test_root, "Telhado deveria fechar frente e fundo com 2 empenas triangulares; encontradas=%d." % gables.size())
		return
	if not has_ridge or absf(pitch - ROOF_ASSEMBLER_SCRIPT.PITCH_DEGREES) > 0.5:
		_fail(test_root, "Telhado deveria ter cumeeira e caimento de %.0f graus; cumeeira=%s caimento=%.1f." % [ROOF_ASSEMBLER_SCRIPT.PITCH_DEGREES, has_ridge, pitch])
		return
	print("PASS: Telhado com empenas, cumeeira e caimento de %.0f graus." % pitch)


func _test_house_rooms_fit_player_size(test_root: Node) -> void:
	print("Testando comodos da casa proporcionais ao boneco...")
	var player_width := 1.16
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	for floor_blueprint in blueprint.floor_blueprints:
		for placement in floor_blueprint.units:
			var unit = placement["blueprint"]
			for room in unit.rooms:
				if minf(room.bounds.size.x, room.bounds.size.y) < player_width * 2.5:
					_fail(test_root, "Comodo '%s' com %s e apertado para boneco de %.2f m de largura." % [room.id, room.bounds.size, player_width])
					return
			for door in unit.doors:
				if float(door["width"]) < player_width * 1.6:
					_fail(test_root, "Porta %s com %.2f m e estreita para o boneco." % [door["center"], float(door["width"])])
					return
	print("PASS: Casa de %.0fx%.0f m com comodos e portas proporcionais ao boneco." % [blueprint.width, blueprint.depth])


func _test_building_meshes_merge_without_touching_doors(test_root: Node) -> void:
	print("Testando fusao de malhas estaticas do predio (draw calls)...")
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	var doors_before := house.find_children("Door_*", "AnimatableBody3D", true, false).size()
	var shapes_before := house.find_children("*", "CollisionShape3D", false, false).size()
	var merged_count: int = MESH_BATCHER_SCRIPT.merge_static_meshes(house)
	var loose_meshes := 0
	for child in house.get_children():
		if child is MeshInstance3D and child.name != MESH_BATCHER_SCRIPT.MERGED_NODE_NAME:
			loose_meshes += 1
	var merged := house.get_node_or_null(MESH_BATCHER_SCRIPT.MERGED_NODE_NAME) as MeshInstance3D
	var surfaces := merged.mesh.get_surface_count() if merged != null else 0
	var doors_after := house.find_children("Door_*", "AnimatableBody3D", true, false).size()
	var shapes_after := house.find_children("*", "CollisionShape3D", false, false).size()
	house.free()
	# A casa procedural varia de 4 a 11 comodos, entao o teto de superficies e
	# folgado; o que importa e continuar 1 malha (soltas=0).
	if merged_count < 50 or loose_meshes != 0 or surfaces == 0 or surfaces > 30:
		_fail(test_root, "Casa deveria virar 1 malha com poucas superficies; fundidas=%d soltas=%d superficies=%d." % [merged_count, loose_meshes, surfaces])
		return
	if doors_after != doors_before or shapes_after != shapes_before:
		_fail(test_root, "Fusao nao pode mexer em portas nem colisoes; portas %d->%d colisoes %d->%d." % [doors_before, doors_after, shapes_before, shapes_after])
		return
	print("PASS: %d malhas da casa viraram 1 no com %d superficies." % [merged_count, surfaces])


## O loot da onda (municao/arma) vai para dentro das casas/apartamentos: cada
## unidade tem uma ancora de loot dentro dos limites do predio.
func _test_enterable_buildings_have_interior_loot_anchors(test_root: Node) -> void:
	print("Testando ancoras de loot dentro das casas e predios...")
	for building_case in [["house", 240912, 1], ["apartment", 18273, 5], ["grocery", 18273, 1]]:
		var blueprint = BUILDING_GENERATOR_SCRIPT.generate(int(building_case[1]), String(building_case[0]))
		var building: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
		var anchors := building.find_children("LootAnchor_*", "Node3D", true, false)
		for anchor_node in anchors:
			var anchor := anchor_node as Node3D
			var local := anchor.position
			if local.x < -0.01 or local.x > blueprint.width + 0.01 or local.z < -0.01 or local.z > blueprint.depth + 0.01 or local.y < -0.01:
				_fail(test_root, "%s: ancora de loot em %s fora do predio (%.1fx%.1f)." % [building_case[0], local, blueprint.width, blueprint.depth])
				building.free()
				return
		building.free()
		if anchors.size() < int(building_case[2]):
			_fail(test_root, "%s deveria ter ao menos %d ancora(s) de loot; tem %d." % [building_case[0], int(building_case[2]), anchors.size()])
			return
	print("PASS: Casas, predios e comercio com ancoras de loot dentro dos limites.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
