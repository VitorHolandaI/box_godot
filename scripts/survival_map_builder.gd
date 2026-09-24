# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name SurvivalMapBuilder
extends RefCounted

const ARENA_HALF_EXTENT := 30.0
const WALL_HEIGHT := 3.5
const WALL_THICKNESS := 0.8
const SURVIVAL_BOUNDARY_LAYER := 24


static func build(parent: Node3D) -> void:
	_add_wall(parent, "SurvivalNorth", Vector3(ARENA_HALF_EXTENT * 2.0, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, WALL_HEIGHT * 0.5, -ARENA_HALF_EXTENT))
	_add_wall(parent, "SurvivalSouth", Vector3(ARENA_HALF_EXTENT * 2.0, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, WALL_HEIGHT * 0.5, ARENA_HALF_EXTENT))
	_add_wall(parent, "SurvivalWest", Vector3(WALL_THICKNESS, WALL_HEIGHT, ARENA_HALF_EXTENT * 2.0), Vector3(-ARENA_HALF_EXTENT, WALL_HEIGHT * 0.5, 0.0))
	_add_wall(parent, "SurvivalEast", Vector3(WALL_THICKNESS, WALL_HEIGHT, ARENA_HALF_EXTENT * 2.0), Vector3(ARENA_HALF_EXTENT, WALL_HEIGHT * 0.5, 0.0))


static func _add_wall(parent: Node3D, wall_name: String, size: Vector3, position: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = wall_name
	wall.collision_layer = SURVIVAL_BOUNDARY_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	wall.position = position
	parent.add_child(wall)
