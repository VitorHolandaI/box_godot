class_name ProceduralCityAssembler
extends RefCounted

const BUILDING_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/building_assembler.gd")


static func assemble(city, parent: Node3D) -> void:
	var road_material := _material(Color(0.07, 0.08, 0.09))
	var sidewalk_material := _material(Color(0.48, 0.49, 0.47))
	for road in city.roads:
		_add_road(parent, road, road_material)
	for block in city.blocks:
		for lot in block.lots:
			_add_lot(parent, lot, sidewalk_material)


static func _add_road(parent: Node3D, road, material: Material) -> void:
	var center: Vector2 = (road.start + road.finish) * 0.5
	var length: float = road.start.distance_to(road.finish)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(road.width, 0.04, length) if is_zero_approx(road.start.x - road.finish.x) else Vector3(length, 0.04, road.width)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Road_%s" % road.road_type
	instance.position = Vector3(center.x, 0.11, center.y)
	instance.mesh = mesh
	parent.add_child(instance)


static func _add_lot(parent: Node3D, lot, sidewalk_material: Material) -> void:
	var sidewalk := MeshInstance3D.new()
	sidewalk.name = lot.id + "_Sidewalk"
	var sidewalk_mesh := BoxMesh.new()
	sidewalk_mesh.size = Vector3(lot.size.x, 0.08, lot.size.y)
	sidewalk_mesh.material = sidewalk_material
	sidewalk.position = Vector3(lot.position.x, 0.15, lot.position.y)
	sidewalk.mesh = sidewalk_mesh
	parent.add_child(sidewalk)
	if lot.building == null:
		return
	var building: StaticBody3D = BUILDING_ASSEMBLER.assemble(lot.building)
	building.name = lot.id + "_" + lot.building.archetype
	building.position = Vector3(lot.position.x - lot.building.width * 0.5, 0.16, lot.position.y - lot.building.depth * 0.5)
	parent.add_child(building)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
