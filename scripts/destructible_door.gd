class_name DestructibleDoor
extends AnimatableBody3D

const PANEL_SPEED := 4.5
const OPEN_SWING := PI * 0.5

var panel_size := Vector3(2.2, 2.4, 0.14)
var panel_material: Material
var max_health := 75
var health := 75
var is_open := false
var is_destroyed := false
var target_rotation_y := 0.0
var swing_direction := 1.0


## Configures a door before it is added to the scene tree.
## Usage: door.configure(Vector3(2.2, 2.4, 0.14), wall_material)
func configure(size: Vector3, material: Material) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_error("Tamanho de porta invalido %s; esperado um Vector3 positivo." % size)
		return
	panel_size = size
	panel_material = material
	swing_direction = 1.0 if panel_size.z > panel_size.x else -1.0


func _ready() -> void:
	add_to_group("destructible_door")
	health = max_health
	_create_panel()


func _physics_process(delta: float) -> void:
	target_rotation_y = OPEN_SWING * swing_direction if is_open else 0.0
	rotation.y = move_toward(rotation.y, target_rotation_y, PANEL_SPEED * maxf(delta, 0.0))


## Toggles the door between its two player-visible states.
## Usage: door.interact()
func interact() -> void:
	if is_destroyed:
		return
	is_open = not is_open


## Damages a normal building door; destroyed doors remain open.
## Usage: door.take_damage(25)
func take_damage(amount: int, _attack_direction: Vector3 = Vector3.ZERO) -> void:
	if amount <= 0 or is_open:
		return
	health = maxi(health - amount, 0)
	if health == 0:
		is_destroyed = true
		is_open = true


## Applies the authoritative state received from the multiplayer server.
## Usage: door.apply_network_state(true, false)
func apply_network_state(should_open: bool, destroyed: bool) -> void:
	is_destroyed = destroyed
	is_open = should_open or destroyed
	health = 0 if destroyed else max_health


func _create_panel() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorPanel"
	var box_mesh := BoxMesh.new()
	box_mesh.size = panel_size
	box_mesh.material = panel_material
	mesh.mesh = box_mesh
	var hinge_offset := Vector3(panel_size.x * 0.5, panel_size.y * 0.5, 0.0) if panel_size.x > panel_size.z else Vector3(0.0, panel_size.y * 0.5, panel_size.z * 0.5)
	mesh.position = hinge_offset
	add_child(mesh)
	var knob := MeshInstance3D.new()
	knob.name = "DoorKnob"
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.07
	knob_mesh.height = 0.14
	var knob_material := StandardMaterial3D.new()
	knob_material.albedo_color = Color(0.72, 0.56, 0.18)
	knob_material.metallic = 0.7
	knob_mesh.material = knob_material
	knob.mesh = knob_mesh
	if panel_size.z < panel_size.x:
		knob.position = hinge_offset + Vector3(panel_size.x * 0.28, 0.0, -panel_size.z)
	else:
		knob.position = hinge_offset + Vector3(-panel_size.x, 0.0, panel_size.z * 0.28)
	add_child(knob)

	var collision := CollisionShape3D.new()
	collision.name = "DoorCollision"
	var shape := BoxShape3D.new()
	shape.size = panel_size
	collision.shape = shape
	collision.position = hinge_offset
	add_child(collision)
