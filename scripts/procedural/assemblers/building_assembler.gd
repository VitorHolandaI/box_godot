class_name ProceduralBuildingAssembler
extends RefCounted

const WALL_HEIGHT := 2.6
const WALL_THICKNESS := 0.12
const CUTOUT_SHADER: Shader = preload("res://shaders/building_cutout.gdshader")


static func assemble(building) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = building.archetype
	var facade_color := _facade_color(building.seed)
	var wall_material := _cutout_material(facade_color)
	var floor_material := _cutout_material(Color(0.27, 0.29, 0.31))
	var trim_material := _cutout_material(facade_color.darkened(0.45))
	var ceiling_material := _cutout_material(facade_color.darkened(0.45), true)
	for floor_blueprint in building.floor_blueprints:
		var floor_y: float = float(floor_blueprint.floor_index) * building.floor_height
		_add_floor_slab(body, building, floor_blueprint.floor_index, floor_y, floor_material)
		for placement in floor_blueprint.units:
			_draw_unit(body, placement["blueprint"], placement["position"], floor_y + 0.08, wall_material, trim_material)
	if building.floors > 1:
		_add_stairs(body, building)
	_add_box(body, "Roof", Vector3(building.width, 0.18, building.depth), Vector3(building.width * 0.5, building.floors * building.floor_height, building.depth * 0.5), ceiling_material, true)
	if building.archetype == "Shop_A" or building.archetype == "Grocery_A":
		_add_commercial_front(body, building)
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
		if not _window_overlaps_door(unit, window):
			_draw_window(body, window, origin, floor_y, trim_material)


static func _add_floor_slab(body: StaticBody3D, building, floor_index: int, floor_y: float, material: Material) -> void:
	if floor_index == 0 or building.floors <= 1:
		_add_box(body, "Floor_%d" % floor_index, Vector3(building.width, 0.12, building.depth), Vector3(building.width * 0.5, floor_y, building.depth * 0.5), material, true)
		return
	var stair_center_x: float = float(building.width) * 0.15
	var stair_start_z: float = float(building.depth) - 1.0
	var stair_end_z: float = maxf(0.8, float(building.depth) - 6.0)
	var hole_left: float = maxf(0.0, stair_center_x - 1.15)
	var hole_right: float = minf(float(building.width), stair_center_x + 1.15)
	var hole_front: float = maxf(0.0, stair_end_z - 0.45)
	var hole_back: float = minf(float(building.depth), stair_start_z + 0.45)
	_add_box(body, "Floor_%d_Left" % floor_index, Vector3(hole_left, 0.12, building.depth), Vector3(hole_left * 0.5, floor_y, building.depth * 0.5), material, true)
	_add_box(body, "Floor_%d_Right" % floor_index, Vector3(building.width - hole_right, 0.12, building.depth), Vector3((hole_right + building.width) * 0.5, floor_y, building.depth * 0.5), material, true)
	_add_box(body, "Floor_%d_Front" % floor_index, Vector3(hole_right - hole_left, 0.12, hole_front), Vector3((hole_left + hole_right) * 0.5, floor_y, hole_front * 0.5), material, true)
	_add_box(body, "Floor_%d_Back" % floor_index, Vector3(hole_right - hole_left, 0.12, building.depth - hole_back), Vector3((hole_left + hole_right) * 0.5, floor_y, (hole_back + building.depth) * 0.5), material, true)


static func _window_overlaps_door(unit, window: Dictionary) -> bool:
	var window_center: Vector2 = window["center"]
	var window_axis: String = window["axis"]
	var window_along: float = window_center.y if window_axis == "vertical" else window_center.x
	var window_line: float = window_center.x if window_axis == "vertical" else window_center.y
	var window_start: float = window_along - float(window["width"]) * 0.5
	var window_end: float = window_along + float(window["width"]) * 0.5
	for door in unit.doors:
		if door.get("axis", "") != window_axis:
			continue
		var door_center: Vector2 = door["center"]
		var door_line: float = door_center.x if window_axis == "vertical" else door_center.y
		if not is_equal_approx(door_line, window_line):
			continue
		var door_along: float = door_center.y if window_axis == "vertical" else door_center.x
		var door_start: float = door_along - float(door["width"]) * 0.5
		var door_end: float = door_along + float(door["width"]) * 0.5
		if window_start < door_end and door_start < window_end:
			return true
	return false


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
	var stair_x: float = float(building.width) * 0.15
	var start_z: float = float(building.depth) - 1.0
	var end_z: float = maxf(0.8, float(building.depth) - 6.0)
	for floor_index in range(building.floors - 1):
		var base_y: float = float(floor_index) * float(building.floor_height)
		for step in step_count:
			var height: float = building.floor_height / float(step_count) * float(step + 1)
			var z: float = start_z - float(step) * (start_z - end_z) / float(step_count)
			_add_box(body, "Stair_%d_%d" % [floor_index, step], Vector3(2.0, height, (start_z - end_z) / step_count), Vector3(stair_x, base_y + height * 0.5, z), _material(Color(0.35, 0.35, 0.37)), false)
		_add_stair_ramp(body, floor_index, base_y, stair_x, start_z, end_z, building.floor_height)


static func _add_stair_ramp(body: StaticBody3D, floor_index: int, base_y: float, stair_x: float, start_z: float, end_z: float, height: float) -> void:
	var run := start_z - end_z
	var ramp := CollisionShape3D.new()
	ramp.name = "StairRamp_%d" % floor_index
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 0.14, run)
	ramp.shape = shape
	ramp.position = Vector3(stair_x, base_y + height * 0.5, (start_z + end_z) * 0.5)
	ramp.rotation.x = atan2(height, run)
	body.add_child(ramp)


static func _add_commercial_front(body: StaticBody3D, building) -> void:
	var accent := Color(0.26, 0.58, 0.32) if building.archetype == "Grocery_A" else Color(0.84, 0.36, 0.14)
	_add_box(body, "StoreAwning", Vector3(building.width * 0.72, 0.22, 0.9), Vector3(building.width * 0.5, 2.2, -0.38), _material(accent), false)
	_add_box(body, "StoreSign", Vector3(building.width * 0.48, 0.55, 0.08), Vector3(building.width * 0.5, 2.52, -0.08), _material(accent.lightened(0.2)), false)


static func _facade_color(seed: int) -> Color:
	var palette: Array[Color] = [
		Color(0.58, 0.37, 0.26), Color(0.30, 0.43, 0.53),
		Color(0.60, 0.48, 0.27), Color(0.35, 0.48, 0.31),
		Color(0.52, 0.34, 0.47), Color(0.46, 0.46, 0.48),
	]
	return palette[absi(seed) % palette.size()]


static func _cutout_material(color: Color, ceiling_cutout: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CUTOUT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("material_roughness", 0.86)
	material.set_shader_parameter("cutout_radius", 0.9)
	material.set_shader_parameter("floor_height", 2.8)
	material.set_shader_parameter("ceiling_cutout", ceiling_cutout)
	return material


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
