class_name WeaponBreakDebris
extends Node3D

## Animação de quebra da arma: 4 pedaços voxel caem fisicamente e somem em
## ~3s. Roda localmente em todos os clientes quando a arma quebra; nada de
## estado sincronizado. Uso:
##   WeaponBreakDebris.spawn(get_tree().current_scene, arma_global_position)

const LIFETIME := 3.0
const GRAVITY := 18.0
const PIECE_COUNT := 4

var velocities: Array[Vector3] = []
var elapsed := 0.0


func _physics_process(delta: float) -> void:
	elapsed += delta
	for piece in get_children():
		var mesh := piece as Node3D
		if mesh == null:
			continue
		var velocity: Vector3 = velocities[piece.get_index()]
		mesh.position += velocity * delta
		mesh.position.y = maxf(mesh.position.y - GRAVITY * delta * delta, 0.0)
		mesh.rotate_y(delta * 4.0)
	if elapsed >= LIFETIME:
		queue_free()


## Spawna pedacos de arma quebrada caindo no chao do jogador.
## Uso: WeaponBreakDebris.spawn(scene, origin)
static func spawn(scene_root: Node, origin: Vector3) -> void:
	if scene_root == null or not scene_root.is_inside_tree():
		return
	var debris := WeaponBreakDebris.new()
	debris.add_to_group("weapon_debris")
	scene_root.add_child(debris)
	debris.global_position = origin
	var metallic := StandardMaterial3D.new()
	metallic.albedo_color = Color(0.12, 0.13, 0.15)
	metallic.metallic = 0.6
	metallic.roughness = 0.45
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for piece_index in PIECE_COUNT:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.18)
		mesh.mesh = box
		mesh.material_override = metallic
		mesh.position = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.9, 1.1), 0.0)
		debris.add_child(mesh)
		debris.velocities.append(Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(2.5, 4.5), rng.randf_range(-2.2, 2.2)))
