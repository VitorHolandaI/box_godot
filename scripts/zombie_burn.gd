# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieBurn
extends RefCounted

## Fogo num zumbi (lanca-chamas): dano por segundo aplicado em ticks e passa
## para zumbis colados (SPREAD_RADIUS) ate MAX_GENERATION saltos, para a horda
## pegar fogo em cadeia sem incendiar o mapa inteiro. Roda so na autoridade.
## Uso:
##   burn.ignite(4.0, 12.0, atirador, 0)
##   burn.update(zombie, delta)

const DAMAGE_TICK_SECONDS := 0.5
const SPREAD_INTERVAL := 1.0
const SPREAD_RADIUS := 1.5
const MAX_GENERATION := 2

var burn_time := 0.0
var burn_dps := 0.0
var generation := 0
var _source: Node = null
var _pending_damage := 0.0
var _tick_elapsed := 0.0
var _spread_elapsed := 0.0


## Acende ou renova (fica com o maior tempo e o maior dano). true se acendeu agora.
## Uso: if burn.ignite(4.0, 12.0, player, 0): avisar_clientes()
func ignite(seconds: float, dps: float, source: Node, from_generation: int) -> bool:
	var was_burning := is_burning()
	burn_time = maxf(burn_time, seconds)
	burn_dps = maxf(burn_dps, dps)
	generation = from_generation if not was_burning else mini(generation, from_generation)
	if is_instance_valid(source):
		_source = source
	return not was_burning


func is_burning() -> bool:
	return burn_time > 0.0


## Avanca o fogo: acumula dano e aplica em ticks; espalha a cada SPREAD_INTERVAL.
## Uso: burn.update(self, delta)
func update(zombie: Node3D, delta: float) -> void:
	if not is_burning():
		return
	var step := minf(delta, burn_time)
	burn_time -= delta
	_pending_damage += burn_dps * step
	_tick_elapsed += delta
	if _tick_elapsed >= DAMAGE_TICK_SECONDS or not is_burning():
		_tick_elapsed = 0.0
		_apply_pending_damage(zombie)
	if not is_burning() or not is_instance_valid(zombie) or bool(zombie.get("is_dead")):
		return
	_spread_elapsed += delta
	if _spread_elapsed >= SPREAD_INTERVAL and generation < MAX_GENERATION:
		_spread_elapsed = 0.0
		_spread(zombie)


func _apply_pending_damage(zombie: Node3D) -> void:
	var amount := floori(_pending_damage)
	if amount <= 0 or not is_instance_valid(zombie) or bool(zombie.get("is_dead")):
		return
	_pending_damage -= amount
	var source: Node = _source if is_instance_valid(_source) else null
	zombie.call("take_damage", amount, Vector3.ZERO, "fire", source)


func _spread(zombie: Node3D) -> void:
	var radius_squared := SPREAD_RADIUS * SPREAD_RADIUS
	for node in zombie.get_tree().get_nodes_in_group("zombies"):
		var other := node as Node3D
		if other == null or other == zombie or bool(other.get("is_dead")):
			continue
		if other.global_position.distance_squared_to(zombie.global_position) > radius_squared:
			continue
		var other_burn = other.get("burn")
		if other_burn != null and not other_burn.is_burning():
			var source: Node = _source if is_instance_valid(_source) else null
			other.call("ignite_spread", burn_time, burn_dps, source, generation + 1)
