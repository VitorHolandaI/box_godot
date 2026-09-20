class_name ZombieLimbDebris
extends Node3D

## Fragmento visual de membro arrancado: replica a malha no impacto e some logo
## depois, sem adicionar corpo rigido ao custo da horda. Uso:
##   ZombieLimbDebris.spawn(get_tree().current_scene, arm_mesh, Vector3.UP * 3.0)

const LIFETIME := 3.5
const GRAVITY := 16.0

var velocity := Vector3.ZERO
var elapsed := 0.0


func _physics_process(delta: float) -> void:
	elapsed += delta
	velocity += Vector3.DOWN * GRAVITY * delta
	position += velocity * delta
	rotate_y(delta * 5.0)
	if elapsed >= LIFETIME:
		queue_free()


static func spawn(scene_root: Node, source_mesh: MeshInstance3D, launch_velocity: Vector3) -> void:
	if scene_root == null or source_mesh == null or source_mesh.mesh == null:
		return
	var debris := Node3D.new()
	debris.set_script(load("res://scripts/zombie_limb_debris.gd") as GDScript)
	debris.set("velocity", launch_velocity)
	debris.add_to_group("zombie_limb_debris")
	scene_root.add_child(debris)
	debris.global_transform = source_mesh.global_transform
	var mesh := MeshInstance3D.new()
	mesh.mesh = source_mesh.mesh
	mesh.material_override = source_mesh.material_override
	debris.add_child(mesh)
