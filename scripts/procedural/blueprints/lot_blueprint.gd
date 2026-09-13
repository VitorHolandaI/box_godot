class_name ProceduralLotBlueprint
extends RefCounted

var id: String
var seed: int
var district: String
var position: Vector2
var size: Vector2
var building


func _init(lot_id: String, lot_seed: int, district_type: String, lot_position: Vector2, lot_size: Vector2) -> void:
	id = lot_id
	seed = lot_seed
	district = district_type
	position = lot_position
	size = lot_size


func signature() -> String:
	return "%s:%d:%s:%s:%s:%s" % [id, seed, district, position, size, building.signature() if building != null else "empty"]
