# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WeaponConeVisual
extends RefCounted

## Visual das armas de cone e do fogo (so cosmetico, nunca no servidor
## dedicado): labareda do lanca-chamas, faiscas da motosserra e chamas presas
## no zumbi enquanto ele queima.
## Uso:
##   WeaponConeVisual.spawn(scene, origem, direcao, WeaponStats.Kind.FLAMETHROWER)
##   WeaponConeVisual.attach_burning(zombie, 4.0)

const BURN_NODE_NAME := "BurnFire"


## Rajada de particulas na direcao do disparo; some sozinha.
## Uso: WeaponConeVisual.spawn(get_tree().current_scene, origem, direcao, kind)
static func spawn(parent: Node, origin: Vector3, direction: Vector3, weapon_kind: int) -> void:
	if parent == null or ServerTickPolicy.is_dedicated_server():
		return
	var stats := WeaponStats.stats_for(weapon_kind)
	var is_flame := stats.has("burn_seconds")
	var cone_range := float(stats.get("cone_range", 2.0))
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 14 if is_flame else 8
	particles.lifetime = 0.45 if is_flame else 0.18
	particles.explosiveness = 0.85
	particles.local_coords = false
	particles.direction = direction.normalized()
	particles.spread = float(stats.get("cone_deg", 30.0)) * 0.5
	particles.initial_velocity_min = cone_range / particles.lifetime * 0.6
	particles.initial_velocity_max = cone_range / particles.lifetime
	particles.gravity = Vector3(0.0, 1.5 if is_flame else -6.0, 0.0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4 if is_flame else 0.5
	particles.mesh = _particle_mesh(WeaponStats.tracer_color_for(weapon_kind), 0.28 if is_flame else 0.05)
	parent.add_child(particles)
	particles.global_position = origin + direction.normalized() * 0.5
	particles.emitting = true
	particles.get_tree().create_timer(particles.lifetime + 0.2).timeout.connect(particles.queue_free)


## Chamas no corpo do zumbi por `seconds`; renova se ja estiver pegando fogo.
## Uso: WeaponConeVisual.attach_burning(zombie, 4.0)
static func attach_burning(zombie: Node3D, seconds: float) -> void:
	if zombie == null or not zombie.is_inside_tree() or ServerTickPolicy.is_dedicated_server():
		return
	var fire := zombie.get_node_or_null(BURN_NODE_NAME) as CPUParticles3D
	if fire == null:
		fire = CPUParticles3D.new()
		fire.name = BURN_NODE_NAME
		fire.amount = 16
		fire.lifetime = 0.6
		fire.local_coords = false
		fire.position = Vector3(0.0, 0.6, 0.0)
		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		fire.emission_box_extents = Vector3(0.3, 0.6, 0.3)
		fire.direction = Vector3.UP
		fire.spread = 20.0
		fire.initial_velocity_min = 0.8
		fire.initial_velocity_max = 1.8
		fire.gravity = Vector3(0.0, 1.0, 0.0)
		fire.mesh = _particle_mesh(Color(1.0, 0.45, 0.05), 0.18)
		zombie.add_child(fire)
	fire.emitting = true
	fire.set_meta("burn_until_msec", Time.get_ticks_msec() + int(seconds * 1000.0))
	zombie.get_tree().create_timer(seconds).timeout.connect(_stop_if_expired.bind(fire))


static func _stop_if_expired(fire: CPUParticles3D) -> void:
	if is_instance_valid(fire) and Time.get_ticks_msec() >= int(fire.get_meta("burn_until_msec", 0)):
		fire.emitting = false


static var _meshes: Dictionary = {}


static func _particle_mesh(color: Color, size: float) -> Mesh:
	var key := "%s|%s" % [color.to_html(), size]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_meshes[key] = mesh
	return mesh
