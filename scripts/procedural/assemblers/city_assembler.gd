class_name ProceduralCityAssembler
extends RefCounted

const BUILDING_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/building_assembler.gd")
const MESH_BATCHER: GDScript = preload("res://scripts/procedural/assemblers/mesh_batcher.gd")
# Acima do ultimo andar: cobre telhado de casa e a casinha da escada do terraco.
const ROOF_CLEARANCE := 3.0


static func assemble(city, parent: Node3D) -> void:
	var road_material := _material(Color(0.07, 0.08, 0.09))
	for road in city.roads:
		_add_road(parent, road, road_material)
	for block in city.blocks:
		for lot in block.lots:
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
	var origin: Vector2 = lot.position - half_size if is_zero_approx(lot.building_rotation_y) else lot.position + half_size
	building.position = Vector3(origin.x, 0.16, origin.y)
	building.rotation.y = lot.building_rotation_y
	parent.add_child(building)
	_configure_building_cutout(building, lot.building)
	# Depois dos limites de recorte: os materiais ja carregam os parametros do predio.
	MESH_BATCHER.merge_static_meshes(building)


static func _configure_building_cutout(building: StaticBody3D, blueprint) -> void:
	var corner_a := building.to_global(Vector3.ZERO)
	var corner_b := building.to_global(Vector3(blueprint.width, 0.0, blueprint.depth))
	var building_min := Vector3(minf(corner_a.x, corner_b.x), building.global_position.y, minf(corner_a.z, corner_b.z))
	var building_max := Vector3(maxf(corner_a.x, corner_b.x), building.global_position.y + blueprint.floors * blueprint.floor_height + ROOF_CLEARANCE, maxf(corner_a.z, corner_b.z))
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
