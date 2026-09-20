class_name ProceduralHouseRoofAssembler
extends RefCounted

## Telhado de duas aguas de casa: aguas grossas a ~30 graus, empenas
## triangulares fechadas na cor da parede, cumeeira, testeiras nos beirais,
## cor de telha propria e chamine em parte das casas.
## Uso: ProceduralHouseRoofAssembler.add_gable_roof(body, building, wall_material)

const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")
const PITCH_DEGREES := 30.0
const OVERHANG := 0.5
const SLOPE_THICKNESS := 0.22
const GABLE_THICKNESS := 0.14
# Faixa entre o topo das paredes (3.28 m) e a base do telhado (3.4 m).
const GABLE_BAND_HEIGHT := 0.2
## Altura de cada fiada de telha na agua do telhado (metros).
const SHINGLE_PERIOD := 0.32
const ROOF_TEXTURE: Texture2D = preload("res://assets/models/modular_urban/Textures/roof.png")
const ROOF_PALETTE: Array[Color] = [
	Color(0.52, 0.24, 0.15), # telha ceramica
	Color(0.22, 0.23, 0.26), # ardosia
	Color(0.36, 0.24, 0.17), # telha marrom
	Color(0.27, 0.30, 0.27), # fibrocimento esverdeado
]


## Monta o telhado sobre o ultimo andar. A cumeeira corre ao longo da
## profundidade (z), com as empenas na frente e no fundo.
## Uso: ProceduralHouseRoofAssembler.add_gable_roof(body, building, wall_material)
static func add_gable_roof(body: StaticBody3D, building, wall_material: Material) -> void:
	var width: float = building.width
	var depth: float = building.depth
	if width <= 0.0 or depth <= 0.0:
		push_error("Casa com tamanho invalido %.2fx%.2f para telhado; esperado > 0." % [width, depth])
		return
	var slope := tan(deg_to_rad(PITCH_DEGREES))
	var roof_y: float = float(building.floors) * building.floor_height
	var ridge_height := width * 0.5 * slope
	var roof_depth := depth + OVERHANG * 2.0
	var roof_material: Material = BUILDING_MATERIALS.textured_opaque(ROOF_PALETTE[absi(int(building.seed)) % ROOF_PALETTE.size()], building.floor_height, ROOF_TEXTURE, 1.1, true)
	# Fiada de telha: sem ela a agua do telhado vira uma chapa de cor unica, que
	# e o que mais chama atencao na vista de cima.
	roof_material.set_shader_parameter("shingle_period", SHINGLE_PERIOD)
	var trim_material: Material = BUILDING_MATERIALS.opaque(Color(0.16, 0.14, 0.12), building.floor_height, true)
	_add_slopes(body, width, depth, roof_y, slope, roof_material)
	_add_gables(body, width, depth, roof_y, ridge_height, wall_material)
	BOX_BUILDER.add_box(body, "RoofRidge", Vector3(0.3, 0.16, roof_depth + 0.04), Vector3(width * 0.5, roof_y + ridge_height + 0.1, depth * 0.5), trim_material, false)
	var eave_drop := OVERHANG * slope
	for side in [-1.0, 1.0]:
		var eave_x: float = width * 0.5 + side * (width * 0.5 + OVERHANG)
		BOX_BUILDER.add_box(body, "RoofFasciaLeft" if side < 0.0 else "RoofFasciaRight", Vector3(0.08, 0.26, roof_depth), Vector3(eave_x, roof_y - eave_drop - 0.1, depth * 0.5), trim_material, false)
	if absi(int(building.seed)) % 3 != 0:
		_add_chimney(body, width, depth, roof_y, slope, trim_material)


static func _add_slopes(body: StaticBody3D, width: float, depth: float, roof_y: float, slope: float, material: Material) -> void:
	var angle := atan(slope)
	var half_run := width * 0.5 + OVERHANG
	var slope_length := half_run / cos(angle)
	var size := Vector3(slope_length, SLOPE_THICKNESS, depth + OVERHANG * 2.0)
	for side in [-1.0, 1.0]:
		var eave := Vector2(width * 0.5 + side * half_run, roof_y - OVERHANG * slope)
		var ridge := Vector2(width * 0.5, roof_y + width * 0.5 * slope)
		var normal := Vector2(side * sin(angle), cos(angle))
		var center := (eave + ridge) * 0.5 - normal * SLOPE_THICKNESS * 0.5
		var node_name := "RoofLeftSlope" if side < 0.0 else "RoofRightSlope"
		_add_tilted_box(body, node_name, size, Vector3(center.x, center.y, depth * 0.5), -side * angle, material)


static func _add_gables(body: StaticBody3D, width: float, depth: float, roof_y: float, ridge_height: float, material: Material) -> void:
	for gable_index in 2:
		var gable_z := GABLE_THICKNESS * 0.5 if gable_index == 0 else depth - GABLE_THICKNESS * 0.5
		var suffix := "Front" if gable_index == 0 else "Back"
		var prism := PrismMesh.new()
		prism.size = Vector3(width, ridge_height, GABLE_THICKNESS)
		prism.material = material
		var gable := MeshInstance3D.new()
		gable.name = "RoofGable" + suffix
		gable.mesh = prism
		gable.position = Vector3(width * 0.5, roof_y + ridge_height * 0.5, gable_z)
		body.add_child(gable)
		BOX_BUILDER.add_box(body, "RoofGableBand" + suffix, Vector3(width, GABLE_BAND_HEIGHT, GABLE_THICKNESS), Vector3(width * 0.5, roof_y - GABLE_BAND_HEIGHT * 0.5 + 0.02, gable_z), material, false)


static func _add_chimney(body: StaticBody3D, width: float, depth: float, roof_y: float, slope: float, material: Material) -> void:
	var chimney_x := width * 0.74
	var surface_y := roof_y + (width - chimney_x) * slope
	var brick: Material = BUILDING_MATERIALS.opaque(Color(0.42, 0.22, 0.16), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT, true)
	BOX_BUILDER.add_box(body, "RoofChimney", Vector3(0.7, 1.9, 0.7), Vector3(chimney_x, surface_y + 0.45, depth * 0.3), brick, false)
	BOX_BUILDER.add_box(body, "RoofChimneyCap", Vector3(0.86, 0.12, 0.86), Vector3(chimney_x, surface_y + 1.46, depth * 0.3), material, false)


static func _add_tilted_box(body: StaticBody3D, node_name: String, size: Vector3, position: Vector3, rotation_z: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation.z = rotation_z
	body.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = node_name + "Collision"
	collision_shape.shape = shape
	collision_shape.position = position
	collision_shape.rotation.z = rotation_z
	body.add_child(collision_shape)
