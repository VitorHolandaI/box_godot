class_name ProceduralCityGenerator
extends RefCounted

const CITY_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/city_blueprint.gd")
const ROAD_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/road_blueprint.gd")
const BLOCK_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/block_blueprint.gd")
const LOT_BLUEPRINT: GDScript = preload("res://scripts/procedural/blueprints/lot_blueprint.gd")
const BUILDING_GENERATOR: GDScript = preload("res://scripts/procedural/generators/building_generator.gd")

const ROAD_LINES := [-72.0, -24.0, 24.0, 72.0]
const BLOCK_SIZE := Vector2(42.0, 42.0)
const LOT_SIZE := Vector2(19.0, 19.0)


static func generate_world(world_seed: int):
	var city = CITY_BLUEPRINT.new(world_seed)
	_generate_roads(city)
	_generate_blocks(city, world_seed)
	return city


static func _generate_roads(city) -> void:
	for x in ROAD_LINES:
		city.add_road(ROAD_BLUEPRINT.new("local", Vector2(x, -96.0), Vector2(x, 96.0), 6.0))
	for z in ROAD_LINES:
		city.add_road(ROAD_BLUEPRINT.new("collector", Vector2(-96.0, z), Vector2(96.0, z), 7.0))


static func _generate_blocks(city, world_seed: int) -> void:
	var block_index := 0
	for x_index in 3:
		for z_index in 3:
			var center: Vector2 = Vector2(-48.0 + float(x_index) * 48.0, -48.0 + float(z_index) * 48.0)
			var district := "urban" if z_index < 2 else "suburban"
			var block = BLOCK_BLUEPRINT.new("Block_%02d" % block_index, district, center, BLOCK_SIZE)
			_generate_lots(block, world_seed + block_index * 97)
			city.add_block(block)
			block_index += 1


static func _generate_lots(block, block_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = block_seed
	var lot_index := 0
	for x_index in 2:
		for z_index in 2:
			var is_safehouse_lot := is_zero_approx(block.position.x) and is_zero_approx(block.position.y) and x_index == 0 and z_index == 1
			var jitter := Vector2.ZERO if is_safehouse_lot else Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			var lot_position: Vector2 = block.position + Vector2(-10.5 + float(x_index) * 21.0, -10.5 + float(z_index) * 21.0) + jitter
			var lot_seed := block_seed + lot_index * 31
			var archetype := "house"
			if block.district == "urban":
				var urban_variant := absi(block_seed + lot_index) % 6
				archetype = "store" if urban_variant == 0 else "grocery" if urban_variant == 1 else "apartment"
			var lot = LOT_BLUEPRINT.new("%s_Lot_%d" % [block.id, lot_index], lot_seed, block.district, lot_position, LOT_SIZE)
			if not is_safehouse_lot:
				lot.building = BUILDING_GENERATOR.generate(lot_seed, archetype)
			block.add_lot(lot)
			lot_index += 1
