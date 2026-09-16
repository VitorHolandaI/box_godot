class_name ZombieTongueVisual
extends MeshInstance3D

## Lingua do puxador desenhada da boca do zumbi ate o peito do jogador preso
## (cosmetico). Some quando a puxada acaba ou um dos dois deixa de existir.
## Uso:
##   var lingua := ZombieTongueVisual.new()
##   cena.add_child(lingua)
##   lingua.setup(zumbi, jogador)

const MAX_SECONDS := ZombieTongue.MAX_PULL_SECONDS + 0.5
const THICKNESS := 0.07

var zombie: Node3D = null
var target: Node3D = null
var _elapsed := 0.0


func setup(from_zombie: Node3D, to_target: Node3D) -> void:
	zombie = from_zombie
	target = to_target
	name = "Tongue_%s" % String(from_zombie.name)
	var box := BoxMesh.new()
	box.size = Vector3(THICKNESS, THICKNESS, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.12, 0.2)
	material.emission_enabled = true
	material.emission = Color(0.4, 0.05, 0.1)
	box.material = material
	mesh = box
	_update_shape()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MAX_SECONDS or not is_instance_valid(zombie) or not is_instance_valid(target):
		queue_free()
		return
	_update_shape()


func _update_shape() -> void:
	var from := zombie.global_position + Vector3.UP * 1.3
	var to := target.global_position + Vector3.UP * 0.9
	var length := from.distance_to(to)
	if length < 0.05:
		return
	global_position = (from + to) * 0.5
	look_at(to, Vector3.UP)
	scale = Vector3(1.0, 1.0, length)
