# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortEconomy
extends RefCounted

## Economia da escolta: quanto cada abate rende ao jogador, por variante de
## zumbi. A loja do mercador (EscortShopMenu) gasta esse saldo; o credito sai do
## main._award_escort_kill, so para abate do JOGADOR (o dos familiares nao conta).
##
## Os valores crescem com o perigo da variante: os fracos pagam pouco e os
## tanques pagam bem. Uso: var grana := EscortEconomy.reward_for_variant(int(zombie.zombie_type))

const REWARD_BY_VARIANT: Dictionary = {
	ZombieMutator.Type.WALKER: 5,
	ZombieMutator.Type.LIMPER: 5,
	ZombieMutator.Type.ONE_ARM: 5,
	ZombieMutator.Type.CRAWLER: 5,
	ZombieMutator.Type.HALF_ARM: 5,
	ZombieMutator.Type.ONE_LEG: 5,
	ZombieMutator.Type.HALF_LEG: 5,
	ZombieMutator.Type.SPRINTER: 8,
	ZombieMutator.Type.JUMPER: 8,
	ZombieMutator.Type.SPITTER: 8,
	ZombieMutator.Type.BLOATER: 8,
	ZombieMutator.Type.LEAPER: 8,
	ZombieMutator.Type.CHARGER: 12,
	ZombieMutator.Type.HALF_HEAD: 12,
	ZombieMutator.Type.SMOKER: 12,
	ZombieMutator.Type.STALKER: 12,
	ZombieMutator.Type.HEALER: 12,
	ZombieMutator.Type.SCREAMER: 10,
	ZombieMutator.Type.SPIDER: 10,
	ZombieMutator.Type.COLLECTOR: 15,
	ZombieMutator.Type.BRUTE: 20,
	ZombieMutator.Type.ARMORED: 20,
	ZombieMutator.Type.TITAN: 40,
}
## Variante sem entrada na tabela (nova, ou tipo invalido) paga o piso.
const DEFAULT_REWARD := 5
## Bonus por segurar cada uma das 3 paradas da escolta (checkpoint). Pago a
## todos os jogadores quando a familia chega e para no abrigo.
const CHECKPOINT_REWARD := 25


## Quanto a variante rende. Piso para tipo desconhecido. Uso: reward_for_variant(ZombieMutator.Type.BRUTE)
static func reward_for_variant(variant: int) -> int:
	return int(REWARD_BY_VARIANT.get(variant, DEFAULT_REWARD))


## Bonus de uma parada concluida. Uso: checkpoint_reward()
static func checkpoint_reward() -> int:
	return CHECKPOINT_REWARD
