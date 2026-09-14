class_name BuildingNavigation
extends Node

## Navmesh proprio de um edificio procedural, assado a partir das caixas de
## colisao do corpo estatico (paredes, lajes, rampas, moveis, guarda-corpos).
## Portas NAO entram na geometria: o caminho atravessa o vao e o zumbi quebra
## a porta fechada que encontrar. Cada edificio usa um mapa de navegacao
## isolado, entao consultas nunca atravessam paredes de um vizinho.
## Uso:
##   building.add_child(BuildingNavigation.new(Vector3(20.0, 20.4, 16.0)))
##   var path := BuildingNavigation.find_for_position(tree, zombie_pos).get_path_between(zombie_pos, target_pos)

const GROUP_NAME := "building_navigation"
const OUTDOOR_MARGIN := 2.5
const CELL_SIZE := 0.15
const CELL_HEIGHT := 0.1
const AGENT_RADIUS := 0.45
const AGENT_HEIGHT := 2.0
const AGENT_MAX_CLIMB := 0.3
const AGENT_MAX_SLOPE := 40.0
const FEET_OFFSET := 1.1

var local_size := Vector3.ZERO
var map_rid := RID()
var region_rid := RID()
var navigation_mesh: NavigationMesh = null
var global_bounds := AABB()


func _init(building_local_size: Vector3 = Vector3.ZERO) -> void:
	name = "BuildingNavigation"
	local_size = building_local_size


func _ready() -> void:
	# Somente quem simula zumbis (servidor ou partida local) precisa do navmesh.
	if NetworkSession.is_client():
		return
	if local_size.x <= 0.0 or local_size.z <= 0.0:
		push_error("BuildingNavigation com tamanho invalido %s; esperado Vector3 positivo (largura, altura, profundidade)." % local_size)
		return
	var building := get_parent() as StaticBody3D
	if building == null:
		push_error("BuildingNavigation precisa ser filho de StaticBody3D; pai atual: %s." % get_parent())
		return
	add_to_group(GROUP_NAME)
	global_bounds = _compute_global_bounds(building)
	navigation_mesh = _create_navigation_mesh()
	var source := build_source_geometry(building)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	map_rid = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map_rid, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map_rid, CELL_HEIGHT)
	NavigationServer3D.map_set_up(map_rid, Vector3.UP)
	# Sincronizacao no proximo tick de fisica, sem esperar iteracoes em thread.
	NavigationServer3D.map_set_use_async_iterations(map_rid, false)
	region_rid = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region_rid, map_rid)
	NavigationServer3D.region_set_transform(region_rid, building.global_transform)
	NavigationServer3D.region_set_navigation_mesh(region_rid, navigation_mesh)
	NavigationServer3D.map_set_active(map_rid, true)


func _exit_tree() -> void:
	if region_rid.is_valid():
		NavigationServer3D.free_rid(region_rid)
		region_rid = RID()
	if map_rid.is_valid():
		NavigationServer3D.free_rid(map_rid)
		map_rid = RID()


## Caminho em coordenadas globais entre dois pontos (pes do agente), restrito
## a este edificio. Vazio quando o mapa ainda nao existe.
## Uso: var path := navigation.get_path_between(from_feet, to_feet)
func get_path_between(from_feet: Vector3, to_feet: Vector3) -> PackedVector3Array:
	if not map_rid.is_valid():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map_rid, from_feet, to_feet, true)


## Verdadeiro depois que o NavigationServer sincronizou o mapa ja com o navmesh
## da regiao. A primeira iteracao do mapa pode chegar antes dos poligonos, por
## isso a checagem pergunta quem e dono do ponto mais proximo do edificio.
## Uso: while not navigation.is_ready(): await get_tree().physics_frame
func is_ready() -> bool:
	if not map_rid.is_valid() or NavigationServer3D.map_get_iteration_id(map_rid) <= 0:
		return false
	return NavigationServer3D.map_get_closest_point_owner(map_rid, global_bounds.get_center()) == region_rid


func contains_point(global_point: Vector3) -> bool:
	return global_bounds.has_point(global_point)


## Navegacao do edificio cujo volume (com margem externa) contem o ponto.
## Uso: var navigation := BuildingNavigation.find_for_position(get_tree(), global_position)
static func find_for_position(tree: SceneTree, global_point: Vector3) -> BuildingNavigation:
	for node in tree.get_nodes_in_group(GROUP_NAME):
		var navigation := node as BuildingNavigation
		if navigation != null and navigation.contains_point(global_point):
			return navigation
	return null


## Geometria-fonte: todas as BoxShape3D do corpo (exceto portas, que sao
## corpos filhos proprios) e um anel de chao ao redor para ligar a porta
## externa a rua.
## Uso: var source := navigation.build_source_geometry(building)
func build_source_geometry(building: StaticBody3D) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	for child in building.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.disabled or not shape_node.shape is BoxShape3D:
			continue
		var box_mesh := BoxMesh.new()
		box_mesh.size = (shape_node.shape as BoxShape3D).size
		source.add_faces(box_mesh.get_faces(), shape_node.transform)
	var ground := BoxMesh.new()
	ground.size = Vector3(local_size.x + OUTDOOR_MARGIN * 2.0, 0.1, local_size.z + OUTDOOR_MARGIN * 2.0)
	source.add_faces(ground.get_faces(), Transform3D(Basis.IDENTITY, Vector3(local_size.x * 0.5, -0.1, local_size.z * 0.5)))
	return source


func _create_navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_HEIGHT
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = AGENT_MAX_CLIMB
	mesh.agent_max_slope = AGENT_MAX_SLOPE
	# O telhado fica fora do volume assado: nenhuma ilha inalcancavel no topo.
	mesh.filter_baking_aabb = AABB(Vector3(-OUTDOOR_MARGIN, -0.5, -OUTDOOR_MARGIN), Vector3(local_size.x + OUTDOOR_MARGIN * 2.0, local_size.y - 0.3, local_size.z + OUTDOOR_MARGIN * 2.0))
	return mesh


func _compute_global_bounds(building: StaticBody3D) -> AABB:
	var local_box := AABB(Vector3(-OUTDOOR_MARGIN, -1.0, -OUTDOOR_MARGIN), Vector3(local_size.x + OUTDOOR_MARGIN * 2.0, local_size.y + 3.0, local_size.z + OUTDOOR_MARGIN * 2.0))
	return building.global_transform * local_box
