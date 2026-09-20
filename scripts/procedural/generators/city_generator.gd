class_name ProceduralCityGenerator
extends RefCounted

const CITY_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/city_blueprint.gd")
const ROAD_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/road_blueprint.gd")
const BLOCK_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/block_blueprint.gd")
const LOT_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/lot_blueprint.gd")
const BUILDING_GENERATOR: GDScript = preload("res://scripts/procedural/generators/building_generator.gd")
const LOT_FEASIBILITY: GDScript = preload("res://scripts/procedural/generators/lot_feasibility.gd")

const ROAD_LINES := [-72.0, -24.0, 24.0, 72.0]
const ROAD_ANCHORS := [-96.0, -72.0, -24.0, 24.0, 72.0, 96.0]
const ROAD_BEND_LIMIT := 0.9
const BLOCK_SIZE := Vector2(42.0, 42.0)
const LOT_SIZE := Vector2(19.0, 19.0)
## Um beco atravessa cada quadra, abrindo rotas curtas e quebrando a leitura de
## grade perfeita. A largura ainda deixa folga para os maiores predios atuais.
const ALLEY_WIDTH := 2.5
const ALLEY_OFFSET_LIMIT := 1.0
const BUILDABLE_HALF_X := 21.0
const BUILDABLE_HALF_Z := 20.5


static func generate_world(world_seed: int, survival_mode: bool = false, pvp_mode: bool = false):
	var city = CITY_BLUEPRINT.new(world_seed)
	_generate_roads(city, world_seed)
	_generate_blocks(city, world_seed, survival_mode, pvp_mode)
	return city


static func _generate_roads(city, world_seed: int) -> void:
	for line_index in ROAD_LINES.size():
		_add_curved_road(city, ROAD_LINES[line_index], true, 6.0, world_seed + line_index * 173)
		_add_curved_road(city, ROAD_LINES[line_index], false, 7.0, world_seed + 1009 + line_index * 211)


static func _add_curved_road(city, axis_position: float, vertical: bool, width: float, road_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = road_seed
	var road_type := "local" if vertical else "collector"
	for anchor_index in range(ROAD_ANCHORS.size() - 1):
		var start_value: float = ROAD_ANCHORS[anchor_index]
		var finish_value: float = ROAD_ANCHORS[anchor_index + 1]
		var midpoint_value := (start_value + finish_value) * 0.5
		var bend := rng.randf_range(-ROAD_BEND_LIMIT, ROAD_BEND_LIMIT)
		var start := Vector2(axis_position, start_value) if vertical else Vector2(start_value, axis_position)
		var midpoint := Vector2(axis_position + bend, midpoint_value) if vertical else Vector2(midpoint_value, axis_position + bend)
		var finish := Vector2(axis_position, finish_value) if vertical else Vector2(finish_value, axis_position)
		city.add_road(ROAD_BLUEPRINT.new(road_type, start, midpoint, width))
		city.add_road(ROAD_BLUEPRINT.new(road_type, midpoint, finish, width))


static func _generate_blocks(city, world_seed: int, survival_mode: bool, pvp_mode: bool = false) -> void:
	var block_index := 0
	for x_index in 3:
		for z_index in 3:
			var center: Vector2 = Vector2(-48.0 + float(x_index) * 48.0, -48.0 + float(z_index) * 48.0)
			var district := "urban" if z_index < 2 else "suburban"
			var block = BLOCK_BLUEPRINT.new("Block_%02d" % block_index, district, center, BLOCK_SIZE)
			var layout := _block_layout(world_seed + block_index * 313, block_index)
			_add_alley(city, block, layout)
			_generate_lots(block, world_seed + block_index * 97, survival_mode, pvp_mode, city.roads, layout)
			city.add_block(block)
			block_index += 1


static func _block_layout(layout_seed: int, block_index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	# Os dois primeiros blocos garantem os dois formatos, mesmo numa seed cuja
	# sequencia aleatoria escolheria a mesma orientacao nove vezes.
	var vertical := true if block_index == 0 else false if block_index == 1 else rng.randf() < 0.5
	return {
		"vertical": vertical,
		"offset": rng.randf_range(-ALLEY_OFFSET_LIMIT, ALLEY_OFFSET_LIMIT),
	}


static func _add_alley(city, block, layout: Dictionary) -> void:
	var offset := float(layout["offset"])
	if bool(layout["vertical"]):
		var x: float = float(block.position.x) + offset
		city.add_road(ROAD_BLUEPRINT.new(
			"alley",
			Vector2(x, block.position.y - BLOCK_SIZE.y * 0.5),
			Vector2(x, block.position.y + BLOCK_SIZE.y * 0.5),
			ALLEY_WIDTH
		))
		return
	var z: float = float(block.position.y) + offset
	city.add_road(ROAD_BLUEPRINT.new(
		"alley",
		Vector2(block.position.x - BLOCK_SIZE.x * 0.5, z),
		Vector2(block.position.x + BLOCK_SIZE.x * 0.5, z),
		ALLEY_WIDTH
	))


static func _generate_lots(block, block_seed: int, survival_mode: bool, pvp_mode: bool, roads: Array, layout: Dictionary) -> void:
	var lot_index := 0
	for x_index in 2:
		for z_index in 2:
			var is_safehouse_lot := is_zero_approx(block.position.x) and is_zero_approx(block.position.y) and x_index == 0 and z_index == 1
			# PVP: as duas casas ficam nos cantos opostos do mapa (lote sudoeste
			# do bloco -48/-48 e lote nordeste do bloco 48/48), entao esses lotes
			# nascem vazios.
			var is_pvp_safehouse_lot := pvp_mode and (
				(is_equal_approx(block.position.x, -48.0) and is_equal_approx(block.position.y, -48.0) and x_index == 0 and z_index == 0)
				or (is_equal_approx(block.position.x, 48.0) and is_equal_approx(block.position.y, 48.0) and x_index == 1 and z_index == 1)
			)
			var reserved_lot := is_safehouse_lot or is_pvp_safehouse_lot
			var lot_position := _lot_position(block, layout, x_index, z_index)
			var lot_size := _lot_size(block, layout, x_index, z_index)
			if reserved_lot:
				# Main e PVP constroem as safehouses em coordenadas fixas; esse lote
				# precisa continuar batendo com elas apesar do layout irregular ao redor.
				lot_position = block.position + Vector2(-10.5 + float(x_index) * 21.0, -10.5 + float(z_index) * 21.0)
				lot_size = LOT_SIZE
			var lot_seed := block_seed + lot_index * 31
			# Viabilidade no lugar do sorteio seco: area, frentes de rua, declive
			# e distrito pesam qual arquetipo cabe (lot_feasibility.gd).
			var features := {
				"area": lot_size.x * lot_size.y,
				"street_sides": LOT_FEASIBILITY.street_facing_sides(lot_position, lot_size, roads),
				# Terreno ainda e plano; o declive entra aqui quando houver relevo.
				"slope": 0.0,
				"district": block.district,
				"survival": survival_mode,
			}
			var pick_rng := RandomNumberGenerator.new()
			pick_rng.seed = lot_seed
			var archetype: String = LOT_FEASIBILITY.choose_archetype(features, pick_rng)
			var lot = LOT_BLUEPRINT.new("%s_Lot_%d" % [block.id, lot_index], lot_seed, block.district, lot_position, lot_size)
			lot.building_rotation_y = _lot_rotation(layout, x_index, z_index)
			if not reserved_lot and not archetype.is_empty():
				lot.building = BUILDING_GENERATOR.generate(lot_seed, archetype)
			block.add_lot(lot)
			lot_index += 1


static func _lot_position(block, layout: Dictionary, x_index: int, z_index: int) -> Vector2:
	var offset := float(layout["offset"])
	if bool(layout["vertical"]):
		var alley_x: float = float(block.position.x) + offset
		var x: float = (float(block.position.x) - BUILDABLE_HALF_X + alley_x - ALLEY_WIDTH * 0.5) * 0.5 if x_index == 0 else (alley_x + ALLEY_WIDTH * 0.5 + float(block.position.x) + BUILDABLE_HALF_X) * 0.5
		return Vector2(x, block.position.y - 10.5 + float(z_index) * 21.0)
	var alley_z: float = float(block.position.y) + offset
	var z: float = (float(block.position.y) - BUILDABLE_HALF_Z + alley_z - ALLEY_WIDTH * 0.5) * 0.5 if z_index == 0 else (alley_z + ALLEY_WIDTH * 0.5 + float(block.position.y) + BUILDABLE_HALF_Z) * 0.5
	return Vector2(block.position.x - 10.5 + float(x_index) * 21.0, z)


static func _lot_size(block, layout: Dictionary, x_index: int, z_index: int) -> Vector2:
	var offset := float(layout["offset"])
	if bool(layout["vertical"]):
		var width := BUILDABLE_HALF_X - ALLEY_WIDTH * 0.5 + offset if x_index == 0 else BUILDABLE_HALF_X - ALLEY_WIDTH * 0.5 - offset
		return Vector2(width, LOT_SIZE.y)
	var depth := BUILDABLE_HALF_Z - ALLEY_WIDTH * 0.5 + offset if z_index == 0 else BUILDABLE_HALF_Z - ALLEY_WIDTH * 0.5 - offset
	return Vector2(LOT_SIZE.x, depth)


static func _lot_rotation(layout: Dictionary, x_index: int, z_index: int) -> float:
	if bool(layout["vertical"]):
		# Predios giram 90 graus para o lado menor (18 m) encarar o beco; dois
		# apartamentos ainda cabem entre o beco e a rua sem sobrepor o asfalto.
		return -PI * 0.5 if x_index == 0 else PI * 0.5
	return 0.0 if z_index == 0 else PI
