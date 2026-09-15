class_name SafehouseRoofBuilder
extends RefCounted

## Telhado da casa segura com saida por cima. Antes a casa era uma caixa aberta
## de paredes de 6.4 m e a unica saida era a porta da frente, onde a horda faz
## cerco. Agora:
## - laje de telhado (material com recorte: some quando o jogador esta dentro);
## - rampa da passarela leste ate um alcapao no telhado;
## - mureta com vao nos fundos e marquise a meia altura para descer pulando.
## A descida e so de ida: nenhuma escada externa, entao a horda nao sobe.
## Uso: SafehouseRoofBuilder.build(house, wall_material, floor_material, stair_material)

const FLOOR_HEIGHT := 3.2
const HALF_SIZE := 6.4
const ROOF_Y := 6.47
const SLAB_THICKNESS := 0.14
const MEZZANINE_TOP := FLOOR_HEIGHT + 0.07
const RAMP_CENTER_X := 5.0
const RAMP_WIDTH := 1.8
const RAMP_BOTTOM_Z := 3.0
const RAMP_TOP_Z := -2.4
const RAMP_THICKNESS := 0.14
# Alcapao sobre a rampa: sem ele a cabeca bate na laje antes do topo.
const HATCH := Rect2(3.9, -2.4, 2.5, 5.6)
const PARAPET_HEIGHT := 1.0
const PARAPET_THICKNESS := 0.3
const EXIT_GAP_WIDTH := 3.0
const LEDGE_SIZE := Vector3(4.0, 0.14, 1.8)
const HATCH_RAIL_HEIGHT := 1.0


## Monta laje, rampa, guarda-corpo do alcapao, mureta com vao e marquise.
## Uso: SafehouseRoofBuilder.build(house, cutout_wall_mat, cutout_floor_mat, wood_mat)
static func build(house: StaticBody3D, wall_material: Material, floor_material: Material, stair_material: Material) -> void:
	_add_roof_slab(house, floor_material)
	_add_ramp(house, stair_material)
	_add_hatch_rails(house, wall_material)
	_add_parapet(house, wall_material)
	_add_exit_ledge(house, floor_material)


static func _add_roof_slab(house: StaticBody3D, material: Material) -> void:
	var slab_y := ROOF_Y - SLAB_THICKNESS * 0.5
	_add_block(house, "RoofSlabWest", Rect2(-HALF_SIZE, -HALF_SIZE, HATCH.position.x + HALF_SIZE, HALF_SIZE * 2.0), slab_y, SLAB_THICKNESS, material)
	_add_block(house, "RoofSlabHatchNorth", Rect2(HATCH.position.x, -HALF_SIZE, HALF_SIZE - HATCH.position.x, HATCH.position.y + HALF_SIZE), slab_y, SLAB_THICKNESS, material)
	_add_block(house, "RoofSlabHatchSouth", Rect2(HATCH.position.x, HATCH.end.y, HALF_SIZE - HATCH.position.x, HALF_SIZE - HATCH.end.y), slab_y, SLAB_THICKNESS, material)


## Rampa da passarela leste (pe em z=3.0) ao telhado (topo em z=-2.4): 31 graus,
## abaixo do floor_max_angle; degraus visuais por cima da colisao inclinada.
static func _add_ramp(house: StaticBody3D, material: Material) -> void:
	var bottom := Vector3(RAMP_CENTER_X, MEZZANINE_TOP, RAMP_BOTTOM_Z)
	var top := Vector3(RAMP_CENTER_X, ROOF_Y + 0.03, RAMP_TOP_Z)
	var along := (top - bottom).normalized()
	var up_axis := Vector3.RIGHT.cross(along).normalized()
	if up_axis.y < 0.0:
		up_axis = -up_axis
	var length := bottom.distance_to(top)
	var shape := BoxShape3D.new()
	shape.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, length)
	var ramp := CollisionShape3D.new()
	ramp.name = "RoofRampCol"
	ramp.shape = shape
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, up_axis, Vector3.RIGHT.cross(up_axis)), (bottom + top) * 0.5 - up_axis * RAMP_THICKNESS * 0.5)
	house.add_child(ramp)
	var steps := 12
	for step in steps:
		var height := (ROOF_Y - MEZZANINE_TOP) / float(steps) * float(step + 1)
		var z := lerpf(RAMP_BOTTOM_Z, RAMP_TOP_Z, (float(step) + 0.5) / float(steps))
		var mesh := BoxMesh.new()
		mesh.size = Vector3(RAMP_WIDTH, height, absf(RAMP_TOP_Z - RAMP_BOTTOM_Z) / float(steps) * 1.05)
		mesh.material = material
		var step_mesh := MeshInstance3D.new()
		step_mesh.name = "RoofRampStep%d" % step
		step_mesh.mesh = mesh
		step_mesh.position = Vector3(RAMP_CENTER_X, MEZZANINE_TOP + height * 0.5, z)
		house.add_child(step_mesh)


## Guarda-corpo no telhado ao redor do alcapao; o lado do topo da rampa fica livre.
static func _add_hatch_rails(house: StaticBody3D, material: Material) -> void:
	var rail_y := ROOF_Y + HATCH_RAIL_HEIGHT * 0.5
	_add_box(house, "RoofHatchRailWest", Vector3(0.08, HATCH_RAIL_HEIGHT, HATCH.size.y), Vector3(HATCH.position.x, rail_y, HATCH.position.y + HATCH.size.y * 0.5), material)
	_add_box(house, "RoofHatchRailSouth", Vector3(HATCH.size.x, HATCH_RAIL_HEIGHT, 0.08), Vector3(HATCH.position.x + HATCH.size.x * 0.5, rail_y, HATCH.end.y), material)


## Mureta nas quatro bordas; nos fundos (z positivo) fica o vao de saida.
static func _add_parapet(house: StaticBody3D, material: Material) -> void:
	var y := ROOF_Y + PARAPET_HEIGHT * 0.5
	var edge := HALF_SIZE - PARAPET_THICKNESS * 0.5
	var length := HALF_SIZE * 2.0
	_add_box(house, "RoofParapetNorth", Vector3(length, PARAPET_HEIGHT, PARAPET_THICKNESS), Vector3(0.0, y, -edge), material)
	_add_box(house, "RoofParapetWest", Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, length), Vector3(-edge, y, 0.0), material)
	_add_box(house, "RoofParapetEast", Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, length), Vector3(edge, y, 0.0), material)
	var side_length := (length - EXIT_GAP_WIDTH) * 0.5
	_add_box(house, "RoofParapetBackLeft", Vector3(side_length, PARAPET_HEIGHT, PARAPET_THICKNESS), Vector3(-HALF_SIZE + side_length * 0.5, y, edge), material)
	_add_box(house, "RoofParapetBackRight", Vector3(side_length, PARAPET_HEIGHT, PARAPET_THICKNESS), Vector3(HALF_SIZE - side_length * 0.5, y, edge), material)


## Marquise nos fundos, a meia altura, embaixo do vao: divide a descida em dois
## pulos de ~3 m.
static func _add_exit_ledge(house: StaticBody3D, material: Material) -> void:
	var ledge_z := HALF_SIZE + LEDGE_SIZE.z * 0.5
	_add_box(house, "RoofExitLedge", LEDGE_SIZE, Vector3(0.0, FLOOR_HEIGHT, ledge_z), material)


static func _add_block(house: StaticBody3D, node_name: String, area: Rect2, center_y: float, thickness: float, material: Material) -> void:
	if area.size.x <= 0.05 or area.size.y <= 0.05:
		return
	_add_box(house, node_name, Vector3(area.size.x, thickness, area.size.y), Vector3(area.position.x + area.size.x * 0.5, center_y, area.position.y + area.size.y * 0.5), material)


static func _add_box(house: StaticBody3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name + "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	house.add_child(mesh_instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name + "Col"
	collision.shape = shape
	collision.position = position
	house.add_child(collision)
