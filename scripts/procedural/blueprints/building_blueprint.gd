class_name ProceduralBuildingBlueprint
extends RefCounted

var archetype: String
var seed: int
var width: float
var depth: float
var floors: int
var floor_height: float
var floor_blueprints: Array = []


func _init(building_archetype: String, building_seed: int, building_width: float, building_depth: float, floor_count: int) -> void:
	archetype = building_archetype
	seed = building_seed
	width = building_width
	depth = building_depth
	floors = floor_count
	floor_height = 3.4


func add_floor(floor_blueprint) -> void:
	floor_blueprints.append(floor_blueprint)


func signature() -> String:
	var result := "%s:%d:%.2f:%.2f:%d|" % [archetype, seed, width, depth, floors]
	for floor_blueprint in floor_blueprints:
		result += floor_blueprint.signature()
	return result
