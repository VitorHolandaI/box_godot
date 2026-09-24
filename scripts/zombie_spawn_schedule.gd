# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieSpawnSchedule
extends RefCounted

const DEFAULT_TARGET := 600
const DEFAULT_INTERVAL := 1.0

var target: int
var interval: float
var elapsed := 0.0


func _init(target_count: int = DEFAULT_TARGET, spawn_interval: float = DEFAULT_INTERVAL) -> void:
	assert(target_count > 0, "Zombie target %d must be greater than zero." % target_count)
	assert(spawn_interval > 0.0, "Zombie spawn interval %.3f must be greater than zero." % spawn_interval)
	target = target_count
	interval = spawn_interval


## Advances the shared spawn clock and allows at most one spawn per interval.
## Usage: if schedule.is_spawn_due(delta): spawn_one_zombie()
func is_spawn_due(delta: float) -> bool:
	elapsed += maxf(delta, 0.0)
	if elapsed < interval:
		return false
	elapsed = 0.0
	return true


## Reports whether the match-wide living population is below its target.
## Usage: if schedule.has_capacity(active_zombies): spawn_one_zombie()
func has_capacity(active_zombies: int) -> bool:
	return active_zombies < target
