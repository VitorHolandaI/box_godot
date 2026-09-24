# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WeaponConeAttack
extends RefCounted

## Dano em cone curto das armas continuas (motosserra, lanca-chamas): todo
## zumbi vivo dentro do alcance e do angulo, com linha de visao (parede
## bloqueia), leva o dano do tick; com "burn_seconds" na tabela ainda pega fogo.
## Uso:
##   var acertos := WeaponConeAttack.strike(get_tree(), origem, direcao, WeaponStats.stats_for(kind), self)

const LINE_OF_SIGHT_MASK := 1
const BODY_RADIUS := 0.5
const MAX_HEIGHT_DIFFERENCE := 2.0


## Zumbis vivos no cone, do mais perto para o mais longe.
## Uso: var alvos := WeaponConeAttack.targets_in_cone(tree, origem, Vector3.FORWARD, 3.0, 60.0)
static func targets_in_cone(tree: SceneTree, origin: Vector3, direction: Vector3, cone_range: float, cone_deg: float) -> Array[Node3D]:
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	var half_angle := deg_to_rad(cone_deg) * 0.5
	var found: Array[Node3D] = []
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or not zombie.is_inside_tree() or bool(zombie.get("is_dead")):
			continue
		var offset := zombie.global_position - origin
		if absf(offset.y) > MAX_HEIGHT_DIFFERENCE:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance > cone_range + BODY_RADIUS:
			continue
		if distance > BODY_RADIUS and flat_direction.angle_to(offset / distance) > half_angle:
			continue
		if not _has_line_of_sight(zombie, origin):
			continue
		found.append(zombie)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return found


## Aplica o tick da arma nos alvos do cone; devolve quantos foram acertados.
## Uso: WeaponConeAttack.strike(tree, origem, direcao, stats, atirador)
static func strike(tree: SceneTree, origin: Vector3, direction: Vector3, stats: Dictionary, shooter: Node) -> int:
	var burn_seconds := float(stats.get("burn_seconds", 0.0))
	var damage_kind := "fire" if burn_seconds > 0.0 else "saw"
	var targets := targets_in_cone(tree, origin, direction, float(stats["cone_range"]), float(stats.get("cone_deg", 60.0)))
	for target in targets:
		target.call("take_damage", int(stats["damage"]), direction, damage_kind, shooter)
		if burn_seconds > 0.0 and is_instance_valid(target) and not bool(target.get("is_dead")):
			target.call("ignite", burn_seconds, float(stats.get("burn_dps", 10.0)), shooter)
	return targets.size()


static func _has_line_of_sight(zombie: Node3D, origin: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, zombie.global_position + Vector3.UP * 0.5, LINE_OF_SIGHT_MASK)
	return zombie.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
