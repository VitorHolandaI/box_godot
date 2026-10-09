# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortSpawnProfile
extends RefCounted

## Perfil de spawn da escolta: a horda cresce POR TRECHO da rota (checkpoints
## vencidos) em vez de encher o mapa desde o inicio. Cada fase tem um teto de
## vivos, um intervalo entre nascimentos e um mix de variantes — comeco com
## poucos zumbis fracos e o fim com mais variedade e os tanques.
##
## O teto de vivos cresce PROPORCIONALMENTE a cada trecho: 50 no primeiro ate
## 200 no ultimo, e dai em diante fica em 200 (ver cap_for_leg). Quantos trechos
## existem sai da ROTA (casas + 1), nao de um numero solto aqui: mudar o desenho
## da rota sem mexer nisto deixava a horda parando de crescer no meio.
## Uso: var perfil := EscortSpawnProfile.profile(checkpoints_vencidos)

const ESCORT_ROUTE_SCRIPT := preload("res://scripts/escort_route.gd")
const CAP_FIRST := 50
const CAP_LAST := 200

const PHASES: Array[Dictionary] = [
	# Fase 0: primeiros trechos — horda pequena e basica.
	{
		"interval": 1.8,
		"mix": {
			ZombieMutator.Type.WALKER: 55,
			ZombieMutator.Type.LIMPER: 20,
			ZombieMutator.Type.ONE_ARM: 15,
			ZombieMutator.Type.CRAWLER: 10,
		},
	},
	# Fase 1: entram corredores e os primeiros especiais leves.
	{
		"interval": 1.4,
		"mix": {
			ZombieMutator.Type.WALKER: 35,
			ZombieMutator.Type.LIMPER: 15,
			ZombieMutator.Type.ONE_ARM: 12,
			ZombieMutator.Type.CRAWLER: 10,
			ZombieMutator.Type.SPRINTER: 10,
			ZombieMutator.Type.JUMPER: 6,
			ZombieMutator.Type.SPITTER: 6,
			ZombieMutator.Type.BLOATER: 6,
		},
	},
	# Fase 2: mais rapidos, bote e os primeiros de vida alta.
	{
		"interval": 1.1,
		"mix": {
			ZombieMutator.Type.WALKER: 20,
			ZombieMutator.Type.LIMPER: 10,
			ZombieMutator.Type.ONE_ARM: 10,
			ZombieMutator.Type.CRAWLER: 10,
			ZombieMutator.Type.SPRINTER: 12,
			ZombieMutator.Type.LEAPER: 8,
			ZombieMutator.Type.SPITTER: 8,
			ZombieMutator.Type.BLOATER: 8,
			ZombieMutator.Type.CHARGER: 6,
			ZombieMutator.Type.HALF_HEAD: 8,
		},
	},
	# Fase 3: reta final — tanques (brute/armored) e a horda cheia.
	{
		"interval": 0.9,
		"mix": {
			ZombieMutator.Type.WALKER: 10,
			ZombieMutator.Type.CRAWLER: 8,
			ZombieMutator.Type.SPRINTER: 14,
			ZombieMutator.Type.LEAPER: 10,
			ZombieMutator.Type.SPITTER: 8,
			ZombieMutator.Type.BLOATER: 8,
			ZombieMutator.Type.CHARGER: 8,
			ZombieMutator.Type.HALF_HEAD: 10,
			ZombieMutator.Type.SMOKER: 4,
			ZombieMutator.Type.STALKER: 4,
			ZombieMutator.Type.BRUTE: 8,
			ZombieMutator.Type.ARMORED: 8,
		},
	},
]


## Fase do trecho: as fases sao esticadas sobre os trechos da rota, entao com as
## 4 casas atuais cada checkpoint vencido troca a fase (0,1,2,3). Uso: phase_index(2)
static func phase_index(checkpoints_cleared: int) -> int:
	# Uma fase por trecho, esticando ou encolhendo com a rota: com 4 trechos e 4
	# fases, cada casa vencida ja troca o mix da horda.
	var spread := float(PHASES.size()) / float(maxi(leg_count(), 1))
	var phase := int(floorf(float(maxi(checkpoints_cleared, 0)) * spread))
	return clampi(phase, 0, PHASES.size() - 1)


## Quantos trechos a missao tem: uma casa a mais que os checkpoints (o ultimo
## trecho e o que termina na safehouse). Uso: EscortSpawnProfile.leg_count()
static func leg_count() -> int:
	return ESCORT_ROUTE_SCRIPT.checkpoint_corners().size() + 1


## Teto de vivos do trecho, proporcional: 50 no primeiro ate 200 no ultimo, e
## depois disso continua 200. Uso: cap_for_leg(0) == 50
static func cap_for_leg(checkpoints_cleared: int) -> int:
	var legs := maxi(leg_count(), 2)
	var leg := clampi(checkpoints_cleared + 1, 1, legs)
	var growth := float(CAP_LAST - CAP_FIRST) * float(leg - 1) / float(legs - 1)
	return CAP_FIRST + int(roundf(growth))


## Perfil do trecho: teto proporcional ao trecho + intervalo e mix da fase.
## Uso: var p := EscortSpawnProfile.profile(0)
static func profile(checkpoints_cleared: int) -> Dictionary:
	var phase: Dictionary = PHASES[phase_index(checkpoints_cleared)]
	return {
		"cap": cap_for_leg(checkpoints_cleared),
		"interval": float(phase["interval"]),
		"mix": phase["mix"],
	}


## Variante sorteada pelo mix da fase, com rolagem deterministica 0..99 (mesma
## ideia do survival_wave_schedule: sync de visual pelo snapshot).
## Uso: var tipo := EscortSpawnProfile.pick_variant(1, 42)
static func pick_variant(checkpoints_cleared: int, roll_percent: int) -> int:
	var mix: Dictionary = profile(checkpoints_cleared)["mix"]
	var cumulative := 0
	var ordered_kinds := mix.keys()
	ordered_kinds.sort()
	for kind in ordered_kinds:
		cumulative += int(mix[kind])
		if int(roll_percent) < cumulative:
			return int(kind)
	return int(ordered_kinds[0])
