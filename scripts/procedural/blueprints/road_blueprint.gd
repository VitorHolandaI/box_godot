class_name ProceduralRoadBlueprint
extends RefCounted

var road_type: String
var start: Vector2
var finish: Vector2
var width: float


func _init(type: String, road_start: Vector2, road_finish: Vector2, road_width: float) -> void:
	road_type = type
	start = road_start
	finish = road_finish
	width = road_width


func signature() -> String:
	return "%s:%s:%s:%.2f" % [road_type, start, finish, width]
