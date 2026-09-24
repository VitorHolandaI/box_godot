# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ThrownGrenade
extends Node3D

## Granada de mao em arco: gravidade, quica no chao/parede e explode no pavio.
## Na autoridade fere zumbis e portas (nao jogadores); no cliente e so visual e a
## explosao chega pelo show_explosion replicado.
## Uso:
##   var granada := ThrownGrenade.new()
##   cena.add_child(granada)
##   granada.setup(mao, direcao * THROW_SPEED + Vector3.UP * THROW_LIFT, true, jogador)

const FUSE_SECONDS := 1.8
const RADIUS := 5.0
const ZOMBIE_DAMAGE := 140
const DOOR_DAMAGE := 60
const GRAVITY := 18.0
const THROW_SPEED := 12.0
const THROW_LIFT := 5.0
const BOUNCE := 0.3
const NOISE_RADIUS := 90.0
const WORLD_MASK := 1

var velocity := Vector3.ZERO
var fuse_left := FUSE_SECONDS
var deals_damage := true
var thrower: Node = null


func setup(start_position: Vector3, start_velocity: Vector3, authoritative: bool, thrown_by: Node) -> void:
	add_to_group("thrown_grenades")
	global_position = start_position
	velocity = start_velocity
	deals_damage = authoritative
	thrower = thrown_by
	if get_child_count() == 0 and not ServerTickPolicy.is_dedicated_server():
		_build_visual()


func _physics_process(delta: float) -> void:
	advance(delta)


## Avanca a granada; explode quando o pavio acaba.
## Uso: granada.advance(delta)
func advance(delta: float) -> void:
	fuse_left -= delta
	if fuse_left <= 0.0:
		_explode()
		return
	velocity.y -= GRAVITY * delta
	var motion := velocity * delta
	if motion.length_squared() < 0.000001 or not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += motion
		return
	var normal: Vector3 = hit["normal"]
	global_position = (hit["position"] as Vector3) + normal * 0.08
	velocity = velocity.bounce(normal) * BOUNCE


func _explode() -> void:
	if is_queued_for_deletion():
		return
	var impact := global_position
	if deals_damage and is_inside_tree():
		var source: Node = thrower if is_instance_valid(thrower) else null
		ZombieVariantAbilities.area_damage(get_tree(), impact, RADIUS, 0, ZOMBIE_DAMAGE, DOOR_DAMAGE, source)
		ZombieFlockCoordinator.relay_sound(get_tree(), impact, NOISE_RADIUS)
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("show_explosion"):
			scene.call("show_explosion", impact, RADIUS)
	queue_free()


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.3, 0.12)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.1)
	material.emission_energy_multiplier = 0.6
	sphere.material = material
	mesh.mesh = sphere
	add_child(mesh)
