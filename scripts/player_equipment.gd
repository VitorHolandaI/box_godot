# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlayerEquipment
extends RefCounted

## Itens arremessaveis e chamadas do jogador (fora dos slots de arma): granada,
## faca de arremesso, ataque aereo e SWAT. Contagem autoritativa no servidor;
## viaja no snapshot como 4 bytes para o HUD do cliente.
## Uso:
##   var equipment := PlayerEquipment.new()
##   if equipment.try_consume(PlayerEquipment.Item.GRENADE): arremessar()

enum Item { GRENADE, THROWING_KNIFE, AIR_STRIKE, SWAT }

const START_COUNTS := {Item.GRENADE: 2, Item.THROWING_KNIFE: 3, Item.AIR_STRIKE: 0, Item.SWAT: 0}
const MAX_COUNTS := {Item.GRENADE: 5, Item.THROWING_KNIFE: 8, Item.AIR_STRIKE: 2, Item.SWAT: 1}
const AIR_STRIKE_EVERY_WAVES := 3
const SWAT_EVERY_WAVES := 5
const HUD_LABELS := {Item.GRENADE: "Granadas", Item.THROWING_KNIFE: "Facas", Item.AIR_STRIKE: "Aereo", Item.SWAT: "SWAT"}

var counts: Dictionary = {}


func _init() -> void:
	reset()


## Volta as contagens iniciais (nova partida).
## Uso: equipment.reset()
func reset() -> void:
	counts = START_COUNTS.duplicate()


func count_of(item: int) -> int:
	return int(counts.get(item, 0))


## Soma ate o maximo do item; devolve quanto entrou.
## Uso: var entrou := equipment.add(PlayerEquipment.Item.GRENADE, 2)
func add(item: int, amount: int) -> int:
	if not MAX_COUNTS.has(item) or amount <= 0:
		return 0
	var added := mini(amount, int(MAX_COUNTS[item]) - count_of(item))
	counts[item] = count_of(item) + added
	return added


## Gasta 1 do item; false quando acabou.
## Uso: if equipment.try_consume(PlayerEquipment.Item.SWAT): chamar_swat()
func try_consume(item: int) -> bool:
	if count_of(item) <= 0:
		return false
	counts[item] = count_of(item) - 1
	return true


## [granadas, facas, aereo, swat] para o snapshot.
## Uso: state["equipment"] = equipment.to_counts()
func to_counts() -> PackedByteArray:
	return PackedByteArray([count_of(Item.GRENADE), count_of(Item.THROWING_KNIFE), count_of(Item.AIR_STRIKE), count_of(Item.SWAT)])


## Uso: equipment.apply_counts(state["equipment"])
func apply_counts(values: PackedByteArray) -> void:
	for item in Item.values():
		if item < values.size():
			counts[item] = clampi(values[item], 0, int(MAX_COUNTS[item]))


## Cargas de chamada por onda: ataque aereo a cada AIR_STRIKE_EVERY_WAVES e
## SWAT a cada SWAT_EVERY_WAVES (contando a partir da onda 1 = indice 0).
## Uso: PlayerEquipment.grant_wave_rewards([player.equipment], wave_index)
static func grant_wave_rewards(equipments: Array, wave_index: int) -> void:
	var air := (wave_index + 1) % AIR_STRIKE_EVERY_WAVES == 0
	var swat := (wave_index + 1) % SWAT_EVERY_WAVES == 0
	for equipment_value in equipments:
		var equipment := equipment_value as PlayerEquipment
		if equipment == null:
			continue
		if air:
			equipment.add(Item.AIR_STRIKE, 1)
		if swat:
			equipment.add(Item.SWAT, 1)


## Linha do HUD: "Granadas 2 | Facas 3 | Aereo 0 | SWAT 0".
func summary_text() -> String:
	var parts: Array[String] = []
	for item in Item.values():
		parts.append("%s %d" % [HUD_LABELS[item], count_of(item)])
	return " | ".join(parts)
