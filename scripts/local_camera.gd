extends Camera3D

var target: Node3D
var camera_offset := Vector3(0, 15, 13.5)


func _ready() -> void:
	rotation_degrees = Vector3(-48, 0, 0)
	fov = 72.0


func _process(_delta: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position + camera_offset
