class_name ProceduralBlockBlueprint
extends RefCounted

var id: String
var district: String
var position: Vector2
var size: Vector2
var lots: Array = []


func _init(block_id: String, district_type: String, block_position: Vector2, block_size: Vector2) -> void:
	id = block_id
	district = district_type
	position = block_position
	size = block_size


func add_lot(lot) -> void:
	lots.append(lot)


func signature() -> String:
	var result := "%s:%s:%s:%s|" % [id, district, position, size]
	for lot in lots:
		result += lot.signature() + ";"
	return result
