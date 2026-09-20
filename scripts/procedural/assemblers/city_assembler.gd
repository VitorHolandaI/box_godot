class_name ProceduralCityAssembler
extends RefCounted

const BUILDING_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/building_assembler.gd")
const MESH_BATCHER: GDScript = preload("res://scripts/procedural/assemblers/mesh_batcher.gd")
const ASPHALT_SHADER: Shader = preload("res://shaders/street_asphalt.gdshader")
## Material de asfalto por largura de pista; ver _asphalt_material.
static var _asphalt_cache: Dictionary = {}
# Acima do ultimo andar: cobre telhado de casa e a casinha da escada do terraco.
const ROOF_CLEARANCE := 3.0


static func assemble(city, parent: Node3D) -> void:
	assemble_roads(city, parent)
	for block in city.blocks:
		for lot in block.lots:
			assemble_lot(parent, lot)


## Monta so as ruas; usado pela montagem em etapas da cidade.
## Uso: ProceduralCityAssembler.assemble_roads(city, parent)
static func assemble_roads(city, parent: Node3D) -> void:
	for road in city.roads:
		_add_road(parent, road, _asphalt_material(road))


## Asfalto procedural (grao, remendo, trinca, sarjeta e faixa central). O
## material depende so da largura da pista (a faixa precisa saber onde e o meio
## e a sarjeta onde e a borda), entao e cacheado por largura: sao 2 larguras e
## ~80 trechos de rua, e um material por trecho quebraria o batching.
static func _asphalt_material(road) -> ShaderMaterial:
	var key := "%s:%.2f" % [road.road_type, road.width]
	var cached: Variant = _asphalt_cache.get(key)
	if cached != null:
		return cached as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = ASPHALT_SHADER
	material.set_shader_parameter("lane_half_width", road.width * 0.5)
	material.set_shader_parameter("show_center_line", road.road_type != "alley")
	_asphalt_cache[key] = material
	return material


## Monta um lote (predio) isolado; usado pela montagem em etapas para
## espalhar os 36 predios por varios frames em vez de um hitch unico.
## Uso: ProceduralCityAssembler.assemble_lot(parent, lot)
static func assemble_lot(parent: Node3D, lot) -> void:
	_add_lot(parent, lot)


static func _add_road(parent: Node3D, road, material: Material) -> void:
	var center: Vector2 = (road.start + road.finish) * 0.5
	var length: float = road.start.distance_to(road.finish)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(road.width, 0.04, length)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Road_%s" % road.road_type
	instance.position = Vector3(center.x, 0.11, center.y)
	var direction: Vector2 = (road.finish - road.start).normalized()
	instance.rotation.y = atan2(direction.x, direction.y)
	instance.mesh = mesh
	parent.add_child(instance)


static func _add_lot(parent: Node3D, lot) -> void:
	if lot.building == null:
		return
	var building: StaticBody3D = BUILDING_ASSEMBLER.assemble(lot.building)
	building.name = lot.id + "_" + lot.building.archetype
	var half_size := Vector2(lot.building.width, lot.building.depth) * 0.5
	# O assembler cria predios a partir do canto local (0, 0). Posicionar o
	# centro depois da rotacao mantem o lote correto para yaw 0, PI e +/- PI/2.
	var origin_offset := Vector3(-half_size.x, 0.0, -half_size.y).rotated(Vector3.UP, lot.building_rotation_y)
	building.position = Vector3(lot.position.x, 0.16, lot.position.y) + origin_offset
	building.rotation.y = lot.building_rotation_y
	parent.add_child(building)
	_configure_building_cutout(building, lot.building)
	# Depois dos limites de recorte: os materiais ja carregam os parametros do predio.
	MESH_BATCHER.merge_static_meshes(building)


static func _configure_building_cutout(building: StaticBody3D, blueprint) -> void:
	var building_min := Vector3(INF, building.global_position.y, INF)
	var building_max := Vector3(-INF, building.global_position.y + blueprint.floors * blueprint.floor_height + ROOF_CLEARANCE, -INF)
	for local_corner in [Vector3.ZERO, Vector3(blueprint.width, 0.0, 0.0), Vector3(0.0, 0.0, blueprint.depth), Vector3(blueprint.width, 0.0, blueprint.depth)]:
		var corner := building.to_global(local_corner)
		building_min.x = minf(building_min.x, corner.x)
		building_min.z = minf(building_min.z, corner.z)
		building_max.x = maxf(building_max.x, corner.x)
		building_max.z = maxf(building_max.z, corner.z)
	configure_cutout_bounds(building, building_min, building_max)


static func configure_cutout_bounds(building: StaticBody3D, building_min: Vector3, building_max: Vector3) -> void:
	building.add_to_group("visibility_building")
	building.set_meta("visibility_min", building_min)
	building.set_meta("visibility_max", building_max)
	for mesh_node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.mesh is PrimitiveMesh:
			continue
		var material := (mesh_instance.mesh as PrimitiveMesh).material as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("use_building_bounds", true)
		material.set_shader_parameter("building_min", building_min)
		material.set_shader_parameter("building_max", building_max)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
