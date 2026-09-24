# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ProceduralFloorBlueprint
extends RefCounted

var archetype: String
var floor_index: int
var units: Array = []


func _init(floor_archetype: String, index: int) -> void:
	archetype = floor_archetype
	floor_index = index


func add_unit(unit, position: Vector2) -> void:
	units.append({"blueprint": unit, "position": position})


func signature() -> String:
	var result := "%s:%d|" % [archetype, floor_index]
	for placement in units:
		result += "%s@%s;" % [placement["blueprint"].signature(), placement["position"]]
	return result
