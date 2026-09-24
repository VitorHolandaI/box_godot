# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieHealer
extends RefCounted

## Curandeiro: a cada HEAL_INTERVAL cura HEAL_AMOUNT dos zumbis vivos a
## HEAL_RADIUS e a cada REVIVE_INTERVAL levanta o cadaver mais proximo a
## REVIVE_RADIUS (a cena cria o zumbi novo). So na autoridade.
## Uso:
##   healer.update(self, delta)

const HEAL_RADIUS := 6.0
const HEAL_AMOUNT := 25
const HEAL_INTERVAL := 3.0
const REVIVE_RADIUS := 8.0
const REVIVE_INTERVAL := 8.0

var _heal_elapsed := 0.0
var _revive_elapsed := 0.0


## Cura quem esta ferido perto (nao o proprio curandeiro); devolve quantos.
## Uso: var curados := ZombieHealer.heal_nearby(get_tree(), self)
static func heal_nearby(tree: SceneTree, healer: Node3D) -> int:
	var healed := 0
	var radius_squared := HEAL_RADIUS * HEAL_RADIUS
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or zombie == healer or bool(zombie.get("is_dead")):
			continue
		if zombie.global_position.distance_squared_to(healer.global_position) > radius_squared:
			continue
		var health := int(zombie.get("health"))
		var max_health := int(zombie.get("max_health"))
		if health >= max_health:
			continue
		zombie.set("health", mini(health + HEAL_AMOUNT, max_health))
		healed += 1
	return healed


## Cadaver (zumbi morto ainda no mundo) mais proximo dentro do alcance, ou null.
## Uso: var cadaver := ZombieHealer.pick_corpse(global_position, cena.corpses)
static func pick_corpse(from: Vector3, corpses: Array) -> Node:
	var best: Node3D = null
	var best_distance := REVIVE_RADIUS * REVIVE_RADIUS
	for corpse_value in corpses:
		if not is_instance_valid(corpse_value):
			continue
		var corpse := corpse_value as Node3D
		if corpse == null or not bool(corpse.get("is_dead")) or corpse.is_queued_for_deletion():
			continue
		var distance := corpse.global_position.distance_squared_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = corpse
	return best


## Relogios de cura e de levantar cadaver; efeitos pedidos a cena.
## Uso: healer.update(self, delta)
func update(zombie: Node3D, delta: float) -> void:
	_heal_elapsed += delta
	_revive_elapsed += delta
	var scene := zombie.get_tree().current_scene
	if _heal_elapsed >= HEAL_INTERVAL:
		_heal_elapsed = 0.0
		if heal_nearby(zombie.get_tree(), zombie) > 0 and scene != null and scene.has_method("show_zombie_ability"):
			scene.call("show_zombie_ability", "heal", zombie.global_position)
	if _revive_elapsed < REVIVE_INTERVAL or scene == null or not scene.has_method("revive_zombie_corpse"):
		return
	var corpses: Variant = scene.get("corpses")
	var corpse := pick_corpse(zombie.global_position, corpses if corpses is Array else [])
	if corpse != null and bool(scene.call("revive_zombie_corpse", corpse)):
		_revive_elapsed = 0.0
