extends Camera3D

const OUTDOOR_OFFSET := Vector3(0.0, 19.0, 17.1)
const INDOOR_OFFSET := Vector3(0.0, 19.0, 3.0)
const CAMERA_MARGIN := 1.0
const INSIDE_CHECK_INTERVAL := 0.15
const CAMERA_SMOOTH_SPEED := 7.0

var target: Node3D
var camera_offset := OUTDOOR_OFFSET
var containing_building: Node3D
var inside_check_elapsed := 0.0
var camera_initialized := false


func _ready() -> void:
	rotation_degrees = Vector3(-48, 0, 0)
	fov = 72.0


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	inside_check_elapsed -= delta
	if inside_check_elapsed <= 0.0:
		inside_check_elapsed = INSIDE_CHECK_INTERVAL
		containing_building = _find_containing_building()
	camera_offset = INDOOR_OFFSET if is_instance_valid(containing_building) else OUTDOOR_OFFSET
	var desired_position := target.global_position + camera_offset
	if is_instance_valid(containing_building):
		desired_position = _clamp_inside_building(desired_position, containing_building)
	var desired_transform := Transform3D(Basis.IDENTITY, desired_position).looking_at(target.global_position, Vector3.UP)
	if not camera_initialized:
		global_transform = desired_transform
		camera_initialized = true
		return
	var blend := minf(delta * CAMERA_SMOOTH_SPEED, 1.0)
	global_position = global_position.lerp(desired_position, blend)
	quaternion = quaternion.slerp(desired_transform.basis.get_rotation_quaternion(), blend)


func _find_containing_building() -> Node3D:
	for building in get_tree().get_nodes_in_group("visibility_building"):
		var min_value: Variant = building.get_meta("visibility_min", null)
		var max_value: Variant = building.get_meta("visibility_max", null)
		if min_value is Vector3 and max_value is Vector3 and _position_inside_bounds(target.global_position, min_value, max_value):
			return building as Node3D
	return null


func _position_inside_bounds(position: Vector3, minimum: Vector3, maximum: Vector3) -> bool:
	return position.x >= minimum.x and position.x <= maximum.x and position.y >= minimum.y and position.y <= maximum.y and position.z >= minimum.z and position.z <= maximum.z


func _clamp_inside_building(position: Vector3, building: Node3D) -> Vector3:
	var minimum: Vector3 = building.get_meta("visibility_min")
	var maximum: Vector3 = building.get_meta("visibility_max")
	position.x = clampf(position.x, minimum.x + CAMERA_MARGIN, maximum.x - CAMERA_MARGIN)
	position.z = clampf(position.z, minimum.z + CAMERA_MARGIN, maximum.z - CAMERA_MARGIN)
	return position
