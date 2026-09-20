class_name ProceduralBuildingBlueprint
extends RefCounted

var archetype: String
var seed: int
var width: float
var depth: float
var floors: int
var floor_height: float
var floor_blueprints: Array = []
## Lances de escada em coordenadas locais do edificio. Cada item:
## {"floor_index": int, "center_x": float, "width": float, "bottom_z": float, "top_z": float}
var stair_flights: Array[Dictionary] = []
## Passagens entre unidades vizinhas do mesmo andar (ex.: nucleo da escada ->
## apartamento). Cada item: {"floor_index", "axis", "center": Vector2, "width",
## "node_a": "unidade:comodo", "node_b": "unidade:comodo"} em coordenadas do edificio.
var unit_links: Array[Dictionary] = []
## Predios com terraco ganham um lance extra ate a laje do topo, com mureta.
var has_roof_terrace := false
## Dados extras do arquetipo lidos pelo assembler. Hoje o comercio guarda aqui
## o layout da loja (entrada, estoque e escritorio) vindo do room_generator.
var metadata: Dictionary = {}


func _init(building_archetype: String, building_seed: int, building_width: float, building_depth: float, floor_count: int) -> void:
	archetype = building_archetype
	seed = building_seed
	width = building_width
	depth = building_depth
	floors = floor_count
	floor_height = 3.4


func add_floor(floor_blueprint) -> void:
	floor_blueprints.append(floor_blueprint)


func add_stair_flight(flight: Dictionary) -> void:
	stair_flights.append(flight)


func add_unit_link(link: Dictionary) -> void:
	unit_links.append(link)


func signature() -> String:
	var result := "%s:%d:%.2f:%.2f:%d|" % [archetype, seed, width, depth, floors]
	for floor_blueprint in floor_blueprints:
		result += floor_blueprint.signature()
	for flight in stair_flights:
		result += "stair:%s;" % [flight]
	return result
