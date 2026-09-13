class_name ProceduralBuildingAssembler
extends RefCounted

const WALL_HEIGHT := 2.6
const WALL_THICKNESS := 0.12


static func assemble(building) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = building.archetype
	var wall_material := _material(Color(0.55, 0.38, 0.28))
	var floor_material := _material(Color(0.27, 0.29, 0.31))
	var trim_material := _material(Color(0.16, 0.18, 0.20))
	for floor_blueprint in building.floor_blueprints:
		var floor_y: float = float(floor_blueprint.floor_index) * building.floor_height
		_add_box(body, "Floor_%d" % floor_blueprint.floor_index, Vector3(building.width, 0.12, building.depth), Vector3(building.width * 0.5, floor_y, building.depth * 0.5), floor_material, true)
		for placement in floor_blueprint.units:
			_draw_unit(body, placement["blueprint"], placement["position"], floor_y + 0.08, wall_material, trim_material)
	if building.floors > 1:
		_add_stairs(body, building)
	_add_box(body, "Roof", Vector3(building.width, 0.18, building.depth), Vector3(building.width * 0.5, building.floors * building.floor_height, building.depth * 0.5), trim_material, true)
	return body


static func _draw_unit(body: StaticBody3D, unit, origin: Vector2, floor_y: float, wall_material: Material, trim_material: Material) -> void:
	for room in unit.rooms:
		var room_center := Vector3(origin.x + room.bounds.position.x + room.bounds.size.x * 0.5, floor_y + 0.07, origin.y + room.bounds.position.y + room.bounds.size.y * 0.5)
		_add_box(body, "Room_%s" % room.id, Vector3(room.bounds.size.x, 0.04, room.bounds.size.y), room_center, trim_material, false)
		if is_zero_approx(room.bounds.position.x):
			_draw_wall_edge(body, unit, room, "vertical", room.bounds.position.x, room.bounds.position.y, room.bounds.end.y, origin, floor_y, wall_material)
		if is_zero_approx(room.bounds.position.y):
			_draw_wall_edge(body, unit, room, "horizontal", room.bounds.position.y, room.bounds.position.x, room.bounds.end.x, origin, floor_y, wall_material)
		if is_zero_approx(room.bounds.end.x - unit.width):
			_draw_wall_edge(body, unit, room, "vertical", room.bounds.end.x, room.bounds.position.y, room.bounds.end.y, origin, floor_y, wall_material)
		if is_zero_approx(room.bounds.end.y - unit.depth):
			_draw_wall_edge(body, unit, room, "horizontal", room.bounds.end.y, room.bounds.position.x, room.bounds.end.x, origin, floor_y, wall_material)
	for window in unit.windows:
		_draw_window(body, window, origin, floor_y, trim_material)


static func _draw_wall_edge(body: StaticBody3D, unit, room, axis: String, line: float, start: float, finish: float, origin: Vector2, floor_y: float, material: Material) -> void:
	var openings: Array[Dictionary] = []
	for door in unit.doors:
		var belongs_to_room: bool = door.get("room_a", "") == room.id or door.get("room_b", "") == room.id
		if not belongs_to_room or door.get("axis", "") != axis:
			continue
		var center: Vector2 = door["center"]
		var door_line := center.x if axis == "vertical" else center.y
		if is_equal_approx(door_line, line):
			var along := center.y if axis == "vertical" else center.x
			openings.append({"start": along - float(door["width"]) * 0.5, "end": along + float(door["width"]) * 0.5})
	openings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left["start"] < right["start"])
	var cursor := start
	for opening in openings:
		_add_wall_segment(body, axis, line, cursor, minf(opening["start"], finish), origin, floor_y, material)
		cursor = maxf(cursor, float(opening["end"]))
	_add_wall_segment(body, axis, line, cursor, finish, origin, floor_y, material)


static func _add_wall_segment(body: StaticBody3D, axis: String, line: float, start: float, finish: float, origin: Vector2, floor_y: float, material: Material) -> void:
	if finish - start <= 0.05:
		return
	var center: Vector3
	var size: Vector3
	if axis == "vertical":
		center = Vector3(origin.x + line, floor_y + WALL_HEIGHT * 0.5, origin.y + (start + finish) * 0.5)
		size = Vector3(WALL_THICKNESS, WALL_HEIGHT, finish - start)
	else:
		center = Vector3(origin.x + (start + finish) * 0.5, floor_y + WALL_HEIGHT * 0.5, origin.y + line)
		size = Vector3(finish - start, WALL_HEIGHT, WALL_THICKNESS)
	_add_box(body, "Wall", size, center, material, true)


static func _draw_window(body: StaticBody3D, window: Dictionary, origin: Vector2, floor_y: float, material: Material) -> void:
	var center: Vector2 = window["center"]
	var axis: String = window["axis"]
	var size := Vector3(float(window["width"]), 0.85, 0.05) if axis == "horizontal" else Vector3(0.05, 0.85, float(window["width"]))
	var position := Vector3(origin.x + center.x, floor_y + 1.45, origin.y + center.y)
	_add_box(body, "Window_%s" % window["room_id"], size, position, material, false)


static func _add_stairs(body: StaticBody3D, building) -> void:
	var step_count := 10
	for step in step_count:
		var height: float = building.floor_height / float(step_count) * float(step + 1)
		_add_box(body, "Stair_%d" % step, Vector3(2.0, height, 3.0 / step_count), Vector3(building.width * 0.5, height * 0.5, -1.5 + float(step) * 3.0 / step_count), _material(Color(0.35, 0.35, 0.37)), true)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material


static func _add_box(body: StaticBody3D, node_name: String, size: Vector3, position: Vector3, material: Material, collision: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	body.add_child(instance)
	if not collision:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	collision_shape.position = position
	body.add_child(collision_shape)
