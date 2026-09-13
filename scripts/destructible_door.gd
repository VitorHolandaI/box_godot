class_name DestructibleDoor
extends AnimatableBody3D

const PANEL_SPEED := 5.0
const OPEN_LIFT := 2.55

var panel_size := Vector3(2.2, 2.4, 0.14)
var panel_material: Material
var max_health := 75
var health := 75
var is_open := false
var is_destroyed := false
var target_offset := 0.0
var base_position_y := 0.0


## Configures a door before it is added to the scene tree.
## Usage: door.configure(Vector3(2.2, 2.4, 0.14), wall_material)
func configure(size: Vector3, material: Material) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_error("Tamanho de porta invalido %s; esperado um Vector3 positivo." % size)
		return
	panel_size = size
	panel_material = material


func _ready() -> void:
	add_to_group("destructible_door")
	health = max_health
	base_position_y = position.y
	_create_panel()


func _physics_process(delta: float) -> void:
	target_offset = OPEN_LIFT if is_open else 0.0
	position.y = move_toward(position.y, base_position_y + target_offset, PANEL_SPEED * maxf(delta, 0.0))


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


func _create_panel() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorPanel"
	var box_mesh := BoxMesh.new()
	box_mesh.size = panel_size
	box_mesh.material = panel_material
	mesh.mesh = box_mesh
	mesh.position.y = panel_size.y * 0.5
	add_child(mesh)

	var collision := CollisionShape3D.new()
	collision.name = "DoorCollision"
	var shape := BoxShape3D.new()
	shape.size = panel_size
	collision.shape = shape
	collision.position.y = panel_size.y * 0.5
	add_child(collision)
