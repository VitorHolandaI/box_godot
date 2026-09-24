# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ProceduralLotBlueprint
extends RefCounted

var id: String
var seed: int
var district: String
var position: Vector2
var size: Vector2
var building_rotation_y := 0.0
var building


func _init(lot_id: String, lot_seed: int, district_type: String, lot_position: Vector2, lot_size: Vector2) -> void:
	id = lot_id
	seed = lot_seed
	district = district_type
	position = lot_position
	size = lot_size


func signature() -> String:
	return "%s:%d:%s:%s:%s:%.3f:%s" % [id, seed, district, position, size, building_rotation_y, building.signature() if building != null else "empty"]


## Pegada do predio no plano do mundo (eixos x/z), ja com building_rotation_y
## aplicada. Para yaw de 90 graus equivale a trocar largura e profundidade; para
## angulos arbitrarios devolve a caixa envolvente, que e o que minimapa e
## clearance de poste precisam (ambos alinham com os eixos do mundo).
## Uso: var footprint := lot.building_footprint_size()
func building_footprint_size() -> Vector2:
	if building == null:
		return size
	var width := float(building.width)
	var depth := float(building.depth)
	var cosine := absf(cos(building_rotation_y))
	var sine := absf(sin(building_rotation_y))
	return Vector2(
		cosine * width + sine * depth,
		sine * width + cosine * depth
	)
