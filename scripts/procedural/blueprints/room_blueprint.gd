class_name ProceduralRoomBlueprint
extends RefCounted

var id: String
var room_type: String
var bounds: Rect2
var doors: Array[Dictionary] = []
var windows: Array[Dictionary] = []


func _init(room_id: String, type: String, room_bounds: Rect2) -> void:
	id = room_id
	room_type = type
	bounds = room_bounds


func signature() -> String:
	return "%s:%s:%s" % [id, room_type, bounds]
