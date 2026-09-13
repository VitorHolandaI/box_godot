class_name ProceduralCityBlueprint
extends RefCounted

var seed: int
var roads: Array = []
var blocks: Array = []


func _init(world_seed: int) -> void:
	seed = world_seed


func add_road(road) -> void:
	roads.append(road)


func add_block(block) -> void:
	blocks.append(block)


func building_count() -> int:
	var result := 0
	for block in blocks:
		result += block.lots.size()
	return result


func signature() -> String:
	var result := "city:%d|" % seed
	for road in roads:
		result += road.signature() + ";"
	for block in blocks:
		result += block.signature()
	return result
