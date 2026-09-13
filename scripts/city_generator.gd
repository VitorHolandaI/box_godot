extends Node3D

const SOLID_VENUE_SCENE := preload("res://scenes/solid_venue.tscn")
const BuildingAssembler: GDScript = preload("res://scripts/building_assembler_3d.gd")
const SafehouseBuilder: GDScript = preload("res://scripts/safehouse_builder.gd")
const TREE_SCENES := [
	preload("res://scenes/tree.tscn"),
	preload("res://scenes/tree_pine.tscn"),
	preload("res://scenes/tree_dead.tscn"),
	preload("res://scenes/tree_sequoia.tscn"),
	preload("res://scenes/tree_araucaria.tscn"),
	preload("res://scenes/tree_ipe.tscn"),
]
const BUSH_SCENE := preload("res://scenes/bush.tscn")
const ROCK_SCENE := preload("res://scenes/rock.tscn")
const GRASS_SCENE := preload("res://scenes/grass_tuft.tscn")
const ROAD_OFFSETS := [-72.0, -48.0, -24.0, 24.0, 48.0, 72.0]
const LOT_CENTERS := [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]
const VENUE_SEQUENCE := [
	"house", "apartment", "store", "house",
	"grocery", "apartment", "house", "house",
	"apartment", "store", "house", "grocery",
	"house", "apartment", "mall", "house",
]
const ROAD_LENGTH := 188.0
const MAP_HALF_EXTENT := 96.0
const BOUNDARY_HEIGHT := 3.0
const BOUNDARY_THICKNESS := 1.0
const WALL_SEGMENT_COUNT := 47
const WALL_SEGMENT_SPACING := 4.0
const FOREST_DEPTH_INNER := 100.0
const FOREST_DEPTH_OUTER := 150.0
const RUIN_INNER_RADIUS := 78.0
const RUIN_OUTER_RADIUS := 95.0
const PLAYER_ONLY_BOUNDARY_LAYER := 16
const CAR_RUST_SHADER: Shader = preload("res://shaders/car_rust.gdshader")
const BUILDING_COLORS := [
	Color(0.48, 0.25, 0.18),
	Color(0.25, 0.36, 0.46),
	Color(0.47, 0.42, 0.24),
	Color(0.31, 0.43, 0.29),
	Color(0.42, 0.28, 0.39),
]

@export var city_seed := 240912

var road_material: StandardMaterial3D
var line_material: StandardMaterial3D
var boundary_material: StandardMaterial3D
var sidewalk_material: StandardMaterial3D


func _ready() -> void:
	_create_materials()
	_create_roads()
	_create_outer_buildings()
	_create_street_props()
	_create_boundaries()
	_create_forest()


func _create_materials() -> void:
	road_material = StandardMaterial3D.new()
	road_material.albedo_color = Color(0.075, 0.08, 0.085)
	road_material.roughness = 0.9

	line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(0.95, 0.72, 0.08)
	line_material.roughness = 0.8

	boundary_material = StandardMaterial3D.new()
	boundary_material.albedo_color = Color(0.16, 0.19, 0.17)
	boundary_material.roughness = 0.92

	sidewalk_material = StandardMaterial3D.new()
	sidewalk_material.albedo_color = Color(0.68, 0.68, 0.66)
	sidewalk_material.roughness = 0.88


func _create_roads() -> void:
	for index in ROAD_OFFSETS.size():
		var offset: float = ROAD_OFFSETS[index]
		_create_visual_box(
			"RoadVertical%d" % index,
			Vector3(8.0, 0.04, ROAD_LENGTH),
			Vector3(offset, 0.12, 0.0),
			road_material
		)
		_create_visual_box(
			"RoadHorizontal%d" % index,
			Vector3(ROAD_LENGTH, 0.04, 8.0),
			Vector3(0.0, 0.13, offset),
			road_material
		)
		_create_visual_box(
			"RoadLineVertical%d" % index,
			Vector3(0.14, 0.02, ROAD_LENGTH),
			Vector3(offset, 0.155, 0.0),
			line_material
		)
		_create_visual_box(
			"RoadLineHorizontal%d" % index,
			Vector3(ROAD_LENGTH, 0.02, 0.14),
			Vector3(0.0, 0.165, offset),
			line_material
		)


func _create_outer_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = city_seed
	var building_index := 0
	for x in LOT_CENTERS:
		for z in LOT_CENTERS:
			_spawn_lot_building(building_index, Vector3(x, 0.12, z), rng)
			building_index += 1


func _spawn_lot_building(index: int, building_position: Vector3, rng: RandomNumberGenerator) -> void:
	_create_lot_sidewalk(index, building_position)
	if is_equal_approx(building_position.x, -12.0) and is_equal_approx(building_position.z, 12.0):
		var safehouse: StaticBody3D = SafehouseBuilder.build_safehouse()
		safehouse.name = "CentralSafehouse"
		safehouse.position = building_position
		add_child(safehouse)
		return
	var venue_kind: String = VENUE_SEQUENCE[index % VENUE_SEQUENCE.size()]
	var lot: Node3D = BuildingAssembler.build_lot(venue_kind, rng)
	lot.name = "Generated%s%d" % [venue_kind.capitalize(), index]
	lot.position = building_position
	lot.rotation.y = rng.randi_range(0, 3) * PI * 0.5
	add_child(lot)


func _create_lot_sidewalk(index: int, pos: Vector3) -> void:
	var pad := BoxMesh.new()
	pad.size = Vector3(16.0, 0.08, 16.0)
	pad.material = sidewalk_material
	var inst := MeshInstance3D.new()
	inst.name = "LotSidewalk%d" % index
	inst.mesh = pad
	inst.position = Vector3(pos.x, 0.14, pos.z)
	add_child(inst)


func _create_street_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = city_seed + 942
	_create_streetlights(rng)
	_create_abandoned_cars(rng)


func _create_streetlights(rng: RandomNumberGenerator) -> void:
	var light_scene := load("res://assets/models/city/streetlight.gltf") as PackedScene
	if light_scene == null:
		return
	for offset in ROAD_OFFSETS:
		for z_pos in [-60.0, -36.0, -12.0, 12.0, 36.0, 60.0]:
			var side := 4.4 if rng.randf() < 0.5 else -4.4
			var light_inst := light_scene.instantiate() as Node3D
			light_inst.position = Vector3(offset + side, 0.12, z_pos)
			light_inst.rotation.y = 0.0 if side > 0.0 else PI
			light_inst.scale = Vector3.ONE * 1.6
			add_child(light_inst)


func _create_abandoned_cars(rng: RandomNumberGenerator) -> void:
	var vehicle_configs: Array[Dictionary] = [
		{"path": "res://assets/models/city/car_police.gltf", "scale": 5.0, "size": Vector3(2.1, 1.8, 4.7)},
		{"path": "res://assets/models/city/car_taxi.gltf", "scale": 5.0, "size": Vector3(2.1, 1.8, 4.7)},
		{"path": "res://assets/models/city/car_sedan.gltf", "scale": 5.0, "size": Vector3(2.1, 1.8, 4.7)},
		{"path": "res://assets/models/city/car_hatchback.gltf", "scale": 5.0, "size": Vector3(2.1, 1.8, 4.5)},
		{"path": "res://assets/models/city/car_stationwagon.gltf", "scale": 5.0, "size": Vector3(2.1, 1.8, 4.8)},
		{"path": "res://assets/models/modular_urban/truck-green-cargo.glb", "scale": 2.8, "size": Vector3(2.4, 2.8, 4.6)},
		{"path": "res://assets/models/modular_urban/truck-grey-cargo.glb", "scale": 2.8, "size": Vector3(2.4, 2.8, 4.6)},
		{"path": "res://assets/models/modular_urban/truck-flat.glb", "scale": 2.8, "size": Vector3(2.4, 2.2, 4.6)},
	]
	var car_spots: Array[Vector3] = [
		Vector3(-24.0, 0.12, -30.0),
		Vector3(-24.0, 0.12, 18.0),
		Vector3(24.0, 0.12, -15.0),
		Vector3(24.0, 0.12, 42.0),
		Vector3(-48.0, 0.12, -8.0),
		Vector3(48.0, 0.12, 10.0),
		Vector3(-18.0, 0.12, 24.0),
		Vector3(32.0, 0.12, -24.0),
		Vector3(-36.0, 0.12, -48.0),
		Vector3(15.0, 0.12, 48.0),
		Vector3(-60.0, 0.12, 24.0),
		Vector3(60.0, 0.12, -24.0),
	]
	for spot in car_spots:
		var cfg: Dictionary = vehicle_configs[rng.randi_range(0, vehicle_configs.size() - 1)]
		var car_scene := load(cfg["path"] as String) as PackedScene
		if car_scene == null:
			continue
		var car_body := StaticBody3D.new()
		car_body.position = spot
		car_body.rotation.y = rng.randf_range(-0.4, 0.4) if rng.randf() < 0.7 else rng.randf() * TAU
		var car_inst := car_scene.instantiate() as Node3D
		car_inst.scale = Vector3.ONE * (cfg["scale"] as float)

		var is_burnt: bool = rng.randf() < 0.25
		_apply_corrosion_to_vehicle(car_inst, rng, is_burnt)

		if rng.randf() < 0.4:
			car_body.rotation.z = rng.randf_range(-0.08, 0.08)
			car_body.position.y = 0.08

		car_body.add_child(car_inst)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = cfg["size"] as Vector3
		col.shape = shape
		col.position = Vector3(0.0, (cfg["size"] as Vector3).y * 0.5, 0.0)
		car_body.add_child(col)
		add_child(car_body)


func _apply_corrosion_to_vehicle(node: Node, rng: RandomNumberGenerator, is_burnt: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for surface_idx in mi.mesh.get_surface_count():
				var orig_mat := mi.get_active_material(surface_idx) as StandardMaterial3D
				var rust_mat := ShaderMaterial.new()
				rust_mat.shader = CAR_RUST_SHADER
				if orig_mat != null and orig_mat.albedo_texture != null:
					rust_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
				rust_mat.set_shader_parameter("rust_amount", rng.randf_range(0.4, 0.95))
				rust_mat.set_shader_parameter("dirt_amount", rng.randf_range(0.35, 0.8))
				rust_mat.set_shader_parameter("is_burnt", is_burnt)
				mi.set_surface_override_material(surface_idx, rust_mat)
	for child in node.get_children():
		_apply_corrosion_to_vehicle(child, rng, is_burnt)


func _create_boundaries() -> void:
	var wall_length := MAP_HALF_EXTENT * 2.0
	var wall_y := BOUNDARY_HEIGHT * 0.5
	_create_boundary_collision(
		"BoundaryNorth",
		Vector3(wall_length, BOUNDARY_HEIGHT, BOUNDARY_THICKNESS),
		Vector3(0.0, wall_y, -MAP_HALF_EXTENT)
	)
	_create_boundary_collision(
		"BoundarySouth",
		Vector3(wall_length, BOUNDARY_HEIGHT, BOUNDARY_THICKNESS),
		Vector3(0.0, wall_y, MAP_HALF_EXTENT)
	)
	_create_boundary_collision(
		"BoundaryWest",
		Vector3(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, wall_length),
		Vector3(-MAP_HALF_EXTENT, wall_y, 0.0)
	)
	_create_boundary_collision(
		"BoundaryEast",
		Vector3(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, wall_length),
		Vector3(MAP_HALF_EXTENT, wall_y, 0.0)
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = city_seed + 701
	_create_broken_wall_side(rng, "North", true, -MAP_HALF_EXTENT + 0.45, 0)
	_create_broken_wall_side(rng, "South", true, MAP_HALF_EXTENT - 0.45, 1)
	_create_broken_wall_side(rng, "West", false, -MAP_HALF_EXTENT + 0.45, 2)
	_create_broken_wall_side(rng, "East", false, MAP_HALF_EXTENT - 0.45, 3)


func _create_boundary_collision(node_name: String, wall_size: Vector3, wall_position: Vector3) -> void:
	var boundary := StaticBody3D.new()
	boundary.name = node_name
	boundary.position = wall_position
	boundary.collision_layer = PLAYER_ONLY_BOUNDARY_LAYER
	add_child(boundary)

	var shape := BoxShape3D.new()
	shape.size = wall_size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	boundary.add_child(collision)


func _create_broken_wall_side(
		rng: RandomNumberGenerator,
		side_name: String,
		horizontal: bool,
		fixed_position: float,
		side_index: int
) -> void:
	for segment_index in WALL_SEGMENT_COUNT:
		var along := (segment_index - WALL_SEGMENT_COUNT / 2) * WALL_SEGMENT_SPACING
		var segment_position := Vector3(along, 0.0, fixed_position) if horizontal else Vector3(fixed_position, 0.0, along)
		if (segment_index + side_index * 2) % 7 == 0 or rng.randf() < 0.08:
			_create_wall_rubble(side_name, segment_index, segment_position, horizontal, rng)
			continue
		var segment_height := rng.randf_range(1.4, BOUNDARY_HEIGHT)
		var segment_size := Vector3(3.65, segment_height, 0.72) if horizontal else Vector3(0.72, segment_height, 3.65)
		segment_position.y = segment_height * 0.5
		_create_visual_box(
			"BrokenWall%s%d" % [side_name, segment_index],
			segment_size,
			segment_position,
			boundary_material
		)


func _create_wall_rubble(
		side_name: String,
		segment_index: int,
		segment_position: Vector3,
		horizontal: bool,
		rng: RandomNumberGenerator
) -> void:
	var rubble_size := Vector3(1.15, 0.38, 0.8) if horizontal else Vector3(0.8, 0.38, 1.15)
	segment_position.y = rubble_size.y * 0.5
	segment_position.x += rng.randf_range(-0.7, 0.7)
	segment_position.z += rng.randf_range(-0.35, 0.35)
	_create_visual_box(
		"WallRubble%s%d" % [side_name, segment_index],
		rubble_size,
		segment_position,
		boundary_material
	)


func _create_forest() -> void:
	if NetworkSession.is_server():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = city_seed + 1701
	var tree_index := 0
	var tree_count := GameConfig.get_forest_tree_count()
	for tree_step in tree_count:
		_spawn_tree(tree_index, _random_forest_position(rng), rng)
		tree_index += 1
	_scatter_undergrowth(rng, tree_count)
	_create_ruins(rng)


func _scatter_undergrowth(rng: RandomNumberGenerator, tree_count: int) -> void:
	var bush_count := int(tree_count * 0.5)
	var rock_count := int(tree_count * 0.25)
	var grass_count := tree_count
	for index in bush_count:
		_spawn_bush(index, _random_forest_position(rng), rng)
	for index in rock_count:
		_spawn_rock(index, _random_forest_position(rng), rng)
	for index in grass_count:
		_spawn_grass(index, _random_forest_position(rng), rng)


func _random_forest_position(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(FOREST_DEPTH_INNER, FOREST_DEPTH_OUTER)
	return Vector3(cos(angle) * radius, 0.1, sin(angle) * radius)


func _create_ruins(rng: RandomNumberGenerator) -> void:
	var rubble_count := 130
	for index in rubble_count:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(RUIN_INNER_RADIUS, RUIN_OUTER_RADIUS)
		var position := Vector3(cos(angle) * radius, 0.1, sin(angle) * radius)
		if rng.randf() < 0.4:
			_spawn_bush(index, position, rng)
		else:
			_spawn_rock(index, position, rng)
	for index in 20:
		_spawn_grass(index, _random_ruin_position(rng), rng)


func _random_ruin_position(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(RUIN_INNER_RADIUS, RUIN_OUTER_RADIUS)
	return Vector3(cos(angle) * radius, 0.1, sin(angle) * radius)


func _spawn_bush(index: int, bush_position: Vector3, rng: RandomNumberGenerator) -> void:
	var bush := BUSH_SCENE.instantiate() as Node3D
	bush.name = "Bush%d" % index
	bush.position = bush_position
	bush.rotation.y = rng.randf_range(0.0, TAU)
	var width_scale := rng.randf_range(0.6, 1.6)
	bush.scale = Vector3(width_scale, rng.randf_range(0.6, 1.3), width_scale)
	add_child(bush)


func _spawn_rock(index: int, rock_position: Vector3, rng: RandomNumberGenerator) -> void:
	var rock := ROCK_SCENE.instantiate() as Node3D
	rock.name = "Rock%d" % index
	rock.position = rock_position
	rock.rotation.y = rng.randf_range(0.0, TAU)
	var width_scale := rng.randf_range(0.4, 1.4)
	rock.scale = Vector3(width_scale, rng.randf_range(0.5, 1.2), width_scale)
	add_child(rock)


func _spawn_grass(index: int, grass_position: Vector3, rng: RandomNumberGenerator) -> void:
	var grass := GRASS_SCENE.instantiate() as Node3D
	grass.name = "Grass%d" % index
	grass.position = grass_position
	grass.rotation.y = rng.randf_range(0.0, TAU)
	var width_scale := rng.randf_range(0.7, 1.4)
	grass.scale = Vector3(width_scale, rng.randf_range(0.7, 1.3), width_scale)
	add_child(grass)


func _spawn_tree(index: int, tree_position: Vector3, rng: RandomNumberGenerator) -> void:
	var scene_index := rng.randi_range(0, TREE_SCENES.size() - 1)
	var tree := TREE_SCENES[scene_index].instantiate() as Node3D
	tree.name = "PerimeterTree%d" % index
	tree.position = tree_position
	tree.rotation.y = rng.randf_range(0.0, TAU)
	var width_scale := rng.randf_range(0.75, 1.25)
	tree.scale = Vector3(width_scale, rng.randf_range(0.8, 1.35), width_scale)
	add_child(tree)


func _create_visual_box(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = box_position
	instance.mesh = mesh
	add_child(instance)
