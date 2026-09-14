class_name ProceduralBoxBuilder
extends RefCounted

## Cria uma caixa visual e, opcionalmente, a colisao correspondente no corpo.
## Compartilhado pelos assemblers para nao duplicar a montagem de BoxMesh/BoxShape3D.
## Uso: ProceduralBoxBuilder.add_box(body, "Wall", Vector3(4, 3, 0.12), Vector3(2, 1.5, 0), material, true)
static func add_box(body: StaticBody3D, node_name: String, size: Vector3, position: Vector3, material: Material, collision: bool) -> void:
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
