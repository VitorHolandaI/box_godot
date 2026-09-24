# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieBossBrain
extends RefCounted

## Cerebro do super zumbi (Tita): decide quando usar cada habilidade. Nao move
## nem causa dano; devolve os nomes das habilidades para o zumbi executar e
## avisar a rede.
## - "slam": pisao em area quando ha jogador a SLAM_RANGE, a cada SLAM_COOLDOWN.
## - "summon": chama sprinters ao cruzar 66% e 33% de vida (uma vez cada).
## - "rage": abaixo de 25% de vida fica mais rapido (uma vez).
## Uso:
##   for ability in brain.tick(delta, float(health) / max_health, nearest_player_distance):
##       _use_boss_ability(ability)

const SLAM_RANGE := 6.0
const SLAM_COOLDOWN := 7.0
const SLAM_PLAYER_DAMAGE := 30
const SLAM_ZOMBIE_DAMAGE := 0
const SLAM_DOOR_DAMAGE := 80
const SUMMON_THRESHOLDS: Array[float] = [0.66, 0.33]
const SUMMON_COUNT := 5
const RAGE_THRESHOLD := 0.25
const RAGE_SPEED_FACTOR := 1.7

var _slam_cooldown := 0.0
var _summons_done := 0
var _raged := false


## Habilidades que disparam neste tick.
## Uso: var abilities := brain.tick(1.0 / 60.0, 0.5, 4.0)
func tick(delta: float, health_fraction: float, nearest_player_distance: float) -> Array[String]:
	var fired: Array[String] = []
	_slam_cooldown = maxf(_slam_cooldown - maxf(delta, 0.0), 0.0)
	if _slam_cooldown <= 0.0 and nearest_player_distance <= SLAM_RANGE:
		_slam_cooldown = SLAM_COOLDOWN
		fired.append("slam")
	while _summons_done < SUMMON_THRESHOLDS.size() and health_fraction <= SUMMON_THRESHOLDS[_summons_done]:
		_summons_done += 1
		fired.append("summon")
	if not _raged and health_fraction <= RAGE_THRESHOLD:
		_raged = true
		fired.append("rage")
	return fired
